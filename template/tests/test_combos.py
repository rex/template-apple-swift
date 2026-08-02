"""The combo matrix — the load-bearing test.

For each of the six frozen combos: copy the git-visible tree, generate into it,
run `verify.py` on the result, and assert the produced file set matches
`predict.predict()` EXACTLY in both directions. Prediction is computed from
`components.yaml` and the answers alone, so an over-eager prune or a forgotten
deletion fails here rather than in a generated repo.
"""

from __future__ import annotations

import pytest
import yaml
from conftest import REPO, TEMPLATE, load_answers, run_generate, run_verify

from tmpl import fsutil, predict
from tmpl.context import ONBOARDING_ANSWERS, ONBOARDING_RECORD, TEMPLATE_DIR
from tmpl.rename import residual_tokens

COMBOS = ["superset", "minimal", "ios-widgets-la", "ios-watch", "universal", "no-health"]


@pytest.fixture(scope="module")
def generated(tmp_path_factory, request):
    """Generate every combo once; share the trees across the tests below."""
    out = {}
    for combo in COMBOS:
        dest = tmp_path_factory.mktemp(combo.replace("-", "_")) / "out"
        proc = run_generate(TEMPLATE / "ci-combos" / f"{combo}.yaml", dest)
        out[combo] = (dest, proc)
    return out


@pytest.mark.parametrize("combo", COMBOS)
def test_generation_succeeds(generated, combo):
    dest, proc = generated[combo]
    assert proc.returncode == 0, f"generate failed:\n{proc.stdout}\n{proc.stderr}"
    assert "verify: clean" in proc.stdout


@pytest.mark.parametrize("combo", COMBOS)
def test_file_set_matches_prediction(generated, combo, manifest, source_files):
    dest, _ = generated[combo]
    doc, ident, _ = load_answers(TEMPLATE / "ci-combos" / f"{combo}.yaml", manifest)
    expected = predict.predict(REPO, ident, doc, manifest, source_files=source_files)
    actual = {str(p.relative_to(dest)) for p in fsutil.walk_files(dest, skip_dirs=(".git",))}
    assert actual - expected == set(), "generator produced unpredicted files"
    assert expected - actual == set(), "generator failed to produce predicted files"


@pytest.mark.parametrize("combo", COMBOS)
def test_standalone_verify_passes(generated, combo):
    dest, _ = generated[combo]
    proc = run_verify(dest)
    assert proc.returncode == 0, proc.stdout + proc.stderr


@pytest.mark.parametrize("combo", COMBOS)
def test_template_self_destructed_and_artifacts_written(generated, combo):
    dest, _ = generated[combo]
    assert not (dest / TEMPLATE_DIR).exists()
    assert (dest / ONBOARDING_RECORD).is_file()
    archive = yaml.safe_load((dest / ONBOARDING_ANSWERS).read_text())
    assert archive["identity"]["app_name"]
    assert set(archive["components"])


@pytest.mark.parametrize("combo", COMBOS)
def test_project_yml_parses_and_include_list_is_exact(generated, combo, manifest):
    dest, _ = generated[combo]
    doc, _, _ = load_answers(TEMPLATE / "ci-combos" / f"{combo}.yaml", manifest)
    enabled = {c for c, on in doc["components"].items() if on}
    project = yaml.safe_load((dest / "project.yml").read_text())
    got = sorted(e["path"] for e in project.get("include") or [])
    assert got == sorted(manifest.kept_includes(enabled))
    assert project["name"] == doc["identity"]["app_name"]


def test_minimal_is_token_clean_and_stripped(generated, manifest):
    """minimal is the only renaming combo — it proves the substitution engine."""
    dest, _ = generated["minimal"]
    doc, ident, _ = load_answers(TEMPLATE / "ci-combos/minimal.yaml", manifest)
    assert residual_tokens(dest, ident, skip_dirs=(".git",)) == []
    assert (dest / "Probe/ProbeApp.swift").is_file()
    assert (dest / "Tests/ProbeTests").is_dir()
    assert not (dest / "MyApp").exists()
    text = (dest / "Probe/ProbeApp.swift").read_text()
    assert "@template:" not in text
    for gone in ("MyAppMac", "MyAppWatch", "HomeWidget", "NotificationService", "LiveActivity"):
        assert not (dest / gone).exists(), gone
    assert "include" not in yaml.safe_load((dest / "project.yml").read_text())


def test_superset_preserves_the_tree_verbatim(generated, manifest, source_files):
    """Nothing pruned, identity unchanged: only additions and doc rewrites."""
    dest, _ = generated["superset"]
    for rel in sorted(source_files):
        if rel.startswith(f"{TEMPLATE_DIR}/"):
            continue
        assert (dest / rel).exists(), f"superset lost {rel}"
    for rel in ("MyApp/MyAppApp.swift", "Shared/Store/CheckpointStore.swift"):
        assert (dest / rel).read_text() == (REPO / rel).read_text(), rel


def test_no_health_prunes_only_health(generated):
    dest, _ = generated["no-health"]
    assert not (dest / "Shared/Capabilities/Health").exists()
    assert (dest / "Shared/Capabilities/Store").is_dir()
    assert (dest / "Shared/Capabilities/Account").is_dir()
    assert (dest / "xcodegen/components/account-mac.yml").is_file()
    assert not (dest / "xcodegen/components/health.yml").exists()
    settings = (dest / "MyApp/Views/SettingsView.swift").read_text()
    assert "HealthService" not in settings and 'Section("Health")' not in settings
    assert "PaywallView()" in settings and "SignInView()" in settings
    assert "@template:health" not in settings and "@template:store" in settings


def test_universal_junction_fragment_is_dropped_without_account(generated):
    dest, _ = generated["universal"]
    assert not (dest / "xcodegen/components/account-mac.yml").exists()
    assert not (dest / "xcodegen/components/account.yml").exists()
    assert (dest / "xcodegen/components/mac.yml").is_file()
    assert (dest / "MyAppMac").is_dir()


def test_ios_watch_keeps_the_watch_dependency_edge(generated):
    dest, _ = generated["ios-watch"]
    watch = yaml.safe_load((dest / "xcodegen/components/watch.yml").read_text())
    assert {"target": "MyAppWatch"} in watch["targets"]["MyApp"]["dependencies"]
    assert (dest / "WatchComplications").is_dir()
    assert not (dest / "HomeWidget").exists()


def test_release_workflow_only_for_github_actions(generated):
    for combo in ("ios-widgets-la", "universal"):
        dest, _ = generated[combo]
        payload_installed = (dest / ".github/workflows/release.yml").is_file()
        assert payload_installed == (REPO / "template/payload/release.yml").is_file()
    for combo in ("superset", "minimal"):
        dest, _ = generated[combo]
        assert not (dest / ".github/workflows/release.yml").exists()


def test_generated_repo_carries_no_generator(generated):
    for combo in COMBOS:
        dest, _ = generated[combo]
        assert not (dest / "template/generate.py").exists()
        assert not list(dest.glob("template/**/*.py"))
