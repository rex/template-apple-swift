"""Answers validation: schema subset, dependency rules, identity derivation."""

from __future__ import annotations

import json
from pathlib import Path

import pytest
import yaml
from conftest import TEMPLATE, load_answers

from tmpl import answers as answers_mod
from tmpl import schema as schema_mod
from tmpl.context import GenerateError

SCHEMA = json.loads((TEMPLATE / "answers.schema.json").read_text())


def write(tmp_path: Path, doc: dict) -> Path:
    path = tmp_path / "answers.yaml"
    path.write_text(yaml.safe_dump(doc))
    return path


def base(**overrides) -> dict:
    doc = {
        "identity": {"app_name": "Probe", "bundle_root": "io.example.probe", "team_id": "ABCDE12345"},
        "components": {"swiftdata": True},
    }
    doc.update(overrides)
    return doc


def test_schema_is_v1_and_fully_supported():
    assert SCHEMA["$id"].endswith("/v1")
    assert schema_mod.verify_support(SCHEMA) == []


def test_example_and_every_combo_validate(manifest, combos):
    for path in [TEMPLATE / "answers.example.yaml", *combos.values()]:
        doc, ident, _ = load_answers(path, manifest)
        assert ident.app_name and ident.bundle_root


def test_defaults_are_filled(tmp_path, manifest):
    doc, _, _ = load_answers(write(tmp_path, base()), manifest)
    assert doc["ops"]["ci_system"] == "xcode_cloud"
    assert doc["deployment"]["ios"] == "18.0"
    assert doc["components"]["mac"] is False


def test_unknown_key_is_an_error(tmp_path, manifest):
    with pytest.raises(GenerateError, match="unknown key 'compnents'"):
        load_answers(write(tmp_path, base(compnents={})), manifest)


def test_unknown_component_is_an_error(tmp_path, manifest):
    doc = base()
    doc["components"]["widgets_home"] = True
    with pytest.raises(GenerateError, match="unknown key 'widgets_home'"):
        load_answers(write(tmp_path, doc), manifest)


@pytest.mark.parametrize(
    "component,needs", [("complications", "watch"), ("widget-mac", "mac")]
)
def test_dependency_violation_names_the_fix(tmp_path, manifest, component, needs):
    doc = base()
    doc["components"][component] = True
    with pytest.raises(GenerateError, match=f"requires '{needs}'"):
        load_answers(write(tmp_path, doc), manifest)
    doc["components"][needs] = True
    assert load_answers(write(tmp_path, doc), manifest)


def test_bad_identity_patterns_rejected(tmp_path, manifest):
    for field, value in [
        ("app_name", "my app"),
        ("app_name", "lowercase"),
        ("bundle_root", "NoDots"),
        ("team_id", "SHORT"),
    ]:
        doc = base()
        doc["identity"][field] = value
        with pytest.raises(GenerateError, match=field):
            load_answers(write(tmp_path, doc), manifest)


def test_identity_derivation_and_bundle_nesting(tmp_path, manifest):
    _, ident, _ = load_answers(write(tmp_path, base()), manifest)
    assert ident.slug == "probe"
    assert ident.display_name == "Probe"
    assert ident.app_group == "group.io.example.probe"
    ids = ident.bundle_ids
    assert ids["complications"] == "io.example.probe.watch.complications"
    for name, bid in ids.items():
        if name in ("app", "mac"):
            continue
        assert bid.rsplit(".", 1)[0] in {ids["app"], ids["watch"]}, name


def test_mixed_os_cohort_warns_but_passes(tmp_path, manifest):
    doc = base(deployment={"ios": "26.0", "macos": "15.0", "watchos": "11.0"})
    _, _, warns = load_answers(write(tmp_path, doc), manifest)
    assert warns and "cohort" in warns[0]


def test_unsupported_schema_keyword_fails_closed(tmp_path, manifest):
    bad = dict(SCHEMA)
    bad["oneOf"] = []
    schema_path = tmp_path / "schema.json"
    schema_path.write_text(json.dumps(bad))
    with pytest.raises(GenerateError, match="oneOf"):
        answers_mod.load(write(tmp_path, base()), schema_path, manifest)
