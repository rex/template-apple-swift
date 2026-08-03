"""The component registry must describe the tree it actually ships with."""

from __future__ import annotations

import yaml
from conftest import REPO, TEMPLATE

from tmpl import manifest as manifest_mod


def test_schema_version_is_current(manifest):
    assert manifest.doc["schema_version"] == manifest_mod.SCHEMA_VERSION


def test_registry_matches_the_real_tree(manifest):
    assert manifest_mod.validate_against_tree(manifest, REPO) == []


def test_every_include_entry_is_declared(manifest):
    project = yaml.safe_load((REPO / "project.yml").read_text())
    on_disk = sorted(e["path"] for e in project["include"])
    declared = sorted(manifest.include_path(n) for n in manifest.includes)
    assert on_disk == declared


def test_include_requires_are_satisfiable(manifest):
    for name, needs in manifest.includes.items():
        for need in needs:
            assert need in manifest.component_ids, f"{name} -> {need}"


def test_kept_includes_track_enabled_components(manifest):
    assert manifest.kept_includes(set(manifest.component_ids)) == [
        manifest.include_path(n) for n in manifest.includes
    ]
    assert manifest.kept_includes(set()) == []
    # account-mac.yml is the junction: it needs BOTH sides.
    assert "xcodegen/components/account-mac.yml" not in manifest.kept_includes({"account"})
    assert "xcodegen/components/account-mac.yml" in manifest.kept_includes({"account", "mac"})


def test_target_bearing_components(manifest):
    assert manifest.target_bearing() == {
        "mac", "watch", "complications", "widgets-home",
        "widget-mac", "live-activity", "nse",
    }
    assert manifest.enabled_target_count(set(manifest.component_ids)) == 8
    assert manifest.enabled_target_count(set()) == 1


def test_combo_files_cover_the_frozen_six(combos):
    assert set(combos) == {
        "superset", "minimal", "ios-widgets-la",
        "ios-watch", "universal", "no-health",
    }


def test_superset_is_all_on_and_minimal_is_all_off(combos, manifest):
    superset = yaml.safe_load(combos["superset"].read_text())["components"]
    minimal = yaml.safe_load(combos["minimal"].read_text())["components"]
    assert set(superset) == manifest.component_ids and all(superset.values())
    assert set(minimal) == manifest.component_ids and not any(minimal.values())
    assert yaml.safe_load(combos["minimal"].read_text())["identity"]["app_name"] == "Probe"


def test_payload_directory_exists():
    assert (TEMPLATE / "payload").is_dir()
