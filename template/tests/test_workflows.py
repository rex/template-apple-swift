"""Workflow surgery and Claude-surface wiring — pure functions plus one run."""

from __future__ import annotations

import json

import yaml
from conftest import REPO, make_ctx

from tmpl import settingsjson, workflows

CI = """name: ci
jobs:
  lint:
    runs-on: ubuntu-latest
    steps: [{run: make lint}]
  # >>> template-ci
  combos:
    runs-on: ubuntu-latest
    steps: [{run: make combos}]
  # <<< template-ci
  test:
    runs-on: macos-26
    steps: [{run: make test}]
"""

MATRIX_BLOCK = """jobs:
  verify:
    strategy:
      matrix:
        combo:
          - superset
          - minimal
          - no-health
"""

MATRIX_FLOW = "jobs:\n  verify:\n    strategy:\n      matrix:\n        combo: [superset, minimal]\n"


def test_template_only_jobs_are_stripped():
    out, removed = workflows.strip_marked_blocks(CI)
    assert removed == 1
    doc = yaml.safe_load(out)
    assert set(doc["jobs"]) == {"lint", "test"}
    assert "template-ci" not in out


def test_strip_is_a_noop_without_markers():
    plain = "name: ci\njobs: {}\n"
    assert workflows.strip_marked_blocks(plain) == (plain, 0)


def test_matrix_collapses_to_one_config():
    out, done = workflows.collapse_matrix(MATRIX_BLOCK, "probe")
    assert done
    assert yaml.safe_load(out)["jobs"]["verify"]["strategy"]["matrix"]["combo"] == ["probe"]
    out, done = workflows.collapse_matrix(MATRIX_FLOW, "probe")
    assert done
    assert yaml.safe_load(out)["jobs"]["verify"]["strategy"]["matrix"]["combo"] == ["probe"]


def test_matrix_without_a_combo_key_is_left_alone():
    text = "jobs:\n  verify:\n    strategy:\n      matrix:\n        os: [macos-26]\n"
    assert workflows.collapse_matrix(text, "probe") == (text, False)


def test_spinner_off_removes_corpus_and_keys(tmp_path, manifest):
    settings = tmp_path / ".claude/settings.json"
    settings.parent.mkdir(parents=True)
    settings.write_text(json.dumps({"spinnerVerbs": {"mode": "append"},
                                    "spinnerTipsOverride": {}, "hooks": {"x": 1}}))
    (tmp_path / ".claude/spinner-verbs.txt").write_text("brewing\n")
    (tmp_path / ".claude/statusline.sh").write_text("#!/bin/bash\n")
    ctx = make_ctx(tmp_path, REPO / "template/ci-combos/minimal.yaml", manifest)
    settingsjson.run(ctx)
    doc = json.loads(settings.read_text())
    assert doc == {"hooks": {"x": 1}}
    assert not (tmp_path / ".claude/spinner-verbs.txt").exists()
    assert not (tmp_path / ".claude/statusline.sh").exists()


def test_statusline_on_writes_the_contract_value(tmp_path, manifest):
    settings = tmp_path / ".claude/settings.json"
    settings.parent.mkdir(parents=True)
    settings.write_text("{}")
    ctx = make_ctx(tmp_path, REPO / "template/ci-combos/universal.yaml", manifest)
    settingsjson.run(ctx)
    doc = json.loads(settings.read_text())
    assert doc["statusLine"] == settingsjson.STATUSLINE_VALUE
    assert doc["statusLine"]["command"].endswith("/.claude/statusline.sh")


def test_missing_settings_file_is_a_note(tmp_path, manifest):
    ctx = make_ctx(tmp_path, REPO / "template/ci-combos/superset.yaml", manifest)
    settingsjson.run(ctx)
    assert any("settings.json absent" in n for n in ctx.plan.notes)


def test_files_removed_tracks_the_ops_flags():
    assert settingsjson.files_removed({"spinner_flavor": True, "statusline": True}) == []
    gone = settingsjson.files_removed({"spinner_flavor": False, "statusline": False})
    assert "scripts/sync_spinner_verbs.py" in gone
    assert ".claude/statusline.sh" in gone
