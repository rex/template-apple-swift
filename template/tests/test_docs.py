"""Doc generation: fragment selection, placeholders, line budgets."""

from __future__ import annotations

import pytest
from conftest import REPO, make_ctx

from tmpl import docs
from tmpl.context import DOC_BUDGETS, GENERATED_DOCS


def ctx_for(combo: str, manifest, tmp_path):
    return make_ctx(tmp_path, REPO / "template/ci-combos" / f"{combo}.yaml", manifest)


@pytest.mark.parametrize("combo", ["superset", "minimal", "ios-watch", "universal", "no-health"])
def test_every_doc_renders_within_budget(combo, manifest, tmp_path):
    ctx = ctx_for(combo, manifest, tmp_path)
    for doc in GENERATED_DOCS:
        text = docs.render(ctx, doc)
        assert text, f"{combo}/{doc} rendered empty"
        assert len(text.splitlines()) <= DOC_BUDGETS[doc], f"{combo}/{doc} over budget"
        assert "{{" not in text and "}}" not in text


def test_placeholders_resolve_to_the_new_identity(manifest, tmp_path):
    ctx = ctx_for("minimal", manifest, tmp_path)
    text = docs.render(ctx, "AGENTS.md")
    assert "Probe" in text and "io.example.probe" in text
    assert "MyApp" not in text and "com.example.myapp" not in text


def test_component_fragments_are_selected_by_answers(manifest, tmp_path):
    minimal = docs.render(ctx_for("minimal", manifest, tmp_path), "AGENTS.md")
    superset = docs.render(ctx_for("superset", manifest, tmp_path), "AGENTS.md")
    assert "HealthKit" in superset and "HealthKit" not in minimal
    assert "Live Activity" in superset and "Live Activity" not in minimal
    assert "watchOS companion" in superset and "watchOS companion" not in minimal


def test_ci_fragment_tracks_ops_ci_system(manifest, tmp_path):
    assert "Xcode Cloud" in docs.render(ctx_for("superset", manifest, tmp_path), "AGENTS.md")
    assert "GitHub Actions" in docs.render(ctx_for("universal", manifest, tmp_path), "AGENTS.md")
    assert "None wired" in docs.render(ctx_for("minimal", manifest, tmp_path), "AGENTS.md")


def test_no_persistence_fragment_flips_with_swiftdata(manifest, tmp_path):
    assert "in-memory" in docs.render(ctx_for("minimal", manifest, tmp_path), "MAP.md")
    assert "SwiftData" in docs.render(ctx_for("superset", manifest, tmp_path), "MAP.md")


def test_targets_table_lists_only_enabled_targets(manifest, tmp_path):
    text = docs.render(ctx_for("ios-widgets-la", manifest, tmp_path), "README.md")
    assert "`HomeWidget`" in text and "`LiveActivity`" in text
    assert "`MyAppMac`" not in text and "`MyAppWatch`" not in text
    assert "com.example.myapp.homewidget" in text


def test_over_budget_doc_is_a_hard_error(manifest, tmp_path):
    from tmpl.context import GenerateError

    with pytest.raises(GenerateError, match="budget"):
        docs._check_budget("PROGRESS.md", "line\n" * 200)


def test_keep_predicate():
    enabled, ops = {"mac"}, {"ci_system": "none", "signing": "match"}
    assert docs.keep("always", enabled, ops)
    assert docs.keep("mac", enabled, ops)
    assert not docs.keep("watch", enabled, ops)
    assert docs.keep("no-watch", enabled, ops)
    assert not docs.keep("no-mac", enabled, ops)
    assert docs.keep("ci-none", enabled, ops)
    assert docs.keep("signing-match", enabled, ops)
    assert not docs.keep("ci-github_actions", enabled, ops)
