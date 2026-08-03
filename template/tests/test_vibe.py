"""VIBE.yaml surgery: values change, comments survive, absent keys are left alone."""

from __future__ import annotations

from pathlib import Path

import pytest
import yaml
from conftest import REPO, make_ctx

from tmpl import vibe, yamledit
from tmpl.context import GenerateError

SAMPLE = """# VIBE.yaml — durable policy. Comments here ARE the documentation.
project:
  name: MyApp            # trailing comment must survive
  display_name: "MyApp"

apple:
  # Platforms this project ships to.
  platforms:
    - iOS
    - macOS
    - watchOS
  universal_purchase: true
  persistence: swiftdata
  monetization: iap
  authentication: [sign_in_with_apple]
  extensions:
    widget_kit: true
    live_activity: true
    notification_service: true
    watch_complications: true
  deployment_target:
    ios: '18.0'
    macos: '15.0'
    watchos: '11.0'
  ops:
    ci_system: xcode_cloud
    signing: automatic

ops:
  autonomy: continue-until-blocked
"""


@pytest.fixture
def tree(tmp_path: Path) -> Path:
    (tmp_path / "VIBE.yaml").write_text(SAMPLE)
    return tmp_path


def run(tree: Path, combo: str, manifest):
    ctx = make_ctx(tree, REPO / "template/ci-combos" / f"{combo}.yaml", manifest)
    vibe.run(ctx)
    text = (tree / "VIBE.yaml").read_text()
    return ctx, text, yaml.safe_load(text)


def test_minimal_turns_every_component_field_off(tree, manifest):
    _, text, doc = run(tree, "minimal", manifest)
    assert doc["apple"]["platforms"] == ["iOS"]
    assert doc["apple"]["universal_purchase"] is False
    assert doc["apple"]["persistence"] == "none"
    assert doc["apple"]["monetization"] == "none"
    assert doc["apple"]["authentication"] == []
    assert not any(doc["apple"]["extensions"].values())
    assert doc["project"]["name"] == "Probe"
    assert "# VIBE.yaml — durable policy" in text
    assert "# Platforms this project ships to." in text
    assert "# trailing comment must survive" in text


def test_superset_is_a_faithful_round_trip(tree, manifest):
    _, _, doc = run(tree, "superset", manifest)
    assert doc["apple"]["platforms"] == ["iOS", "macOS", "watchOS"]
    assert doc["apple"]["persistence"] == "swiftdata"
    assert all(doc["apple"]["extensions"].values())
    assert doc["apple"]["ops"]["ci_system"] == "xcode_cloud"


def test_ios_watch_keeps_watch_platform_only(tree, manifest):
    _, _, doc = run(tree, "ios-watch", manifest)
    assert doc["apple"]["platforms"] == ["iOS", "watchOS"]
    assert doc["apple"]["universal_purchase"] is False
    assert doc["apple"]["extensions"]["watch_complications"] is True
    assert doc["apple"]["extensions"]["widget_kit"] is False


def test_ops_fields_follow_the_answers(tree, manifest):
    _, _, doc = run(tree, "no-health", manifest)
    assert doc["apple"]["ops"]["signing"] == "match"
    assert doc["apple"]["deployment_target"]["ios"] == "18.0"
    assert isinstance(doc["apple"]["deployment_target"]["ios"], str)


def test_absent_keys_are_reported_not_invented(tmp_path, manifest):
    (tmp_path / "VIBE.yaml").write_text("project:\n  name: MyApp\n")
    ctx = make_ctx(tmp_path, REPO / "template/ci-combos/minimal.yaml", manifest)
    vibe.run(ctx)
    doc = yaml.safe_load((tmp_path / "VIBE.yaml").read_text())
    assert set(doc) == {"project"} and doc["project"]["name"] == "Probe"
    assert any("not present" in n for n in ctx.plan.notes)


def test_missing_file_is_a_note_not_a_failure(tmp_path, manifest):
    ctx = make_ctx(tmp_path, REPO / "template/ci-combos/minimal.yaml", manifest)
    vibe.run(ctx)
    assert any("absent" in n for n in ctx.plan.notes)


def test_component_fields_come_from_the_registry(manifest):
    fields = vibe.component_fields(manifest, set(manifest.component_ids))
    assert fields["platforms"] == ["iOS", "macOS", "watchOS"]
    assert fields["extensions.live_activity"] is True
    assert vibe.component_fields(manifest, set())["persistence"] == "none"


def test_broken_edit_is_caught_by_reparse(tmp_path):
    with pytest.raises(GenerateError, match="invalid YAML"):
        vibe._verify(tmp_path / "VIBE.yaml", "a:\n  - x\n b: 1\n", [])


def test_yamledit_scalars_round_trip():
    assert yaml.safe_load(f"k: {yamledit.scalar('18.0')}")["k"] == "18.0"
    assert yaml.safe_load(f"k: {yamledit.scalar(True)}")["k"] is True
    assert yaml.safe_load(f"k: {yamledit.scalar('none')}")["k"] == "none"
    assert yaml.safe_load(f"k: {yamledit.scalar('My App 2')}")["k"] == "My App 2"
