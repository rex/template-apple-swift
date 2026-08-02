"""CLI contract: modes, refusals, and the dry-run plan."""

from __future__ import annotations

import sys

import pytest
from conftest import REPO, TEMPLATE, run_generate

import generate as gen

SUPERSET = TEMPLATE / "ci-combos/superset.yaml"
MINIMAL = TEMPLATE / "ci-combos/minimal.yaml"


def capture(argv, capsys) -> tuple[int, str]:
    code = gen.main(argv)
    return code, capsys.readouterr().out


def test_mode_is_mandatory():
    with pytest.raises(SystemExit):
        gen.main(["--answers", str(SUPERSET)])


def test_dest_and_apply_are_mutually_exclusive(workdir):
    with pytest.raises(SystemExit):
        gen.main(["--answers", str(SUPERSET), "--dest", str(workdir), "--apply"])


def test_answers_is_required():
    with pytest.raises(SystemExit):
        gen.main(["--dry-run"])


def test_dry_run_needs_no_mode_and_writes_nothing(capsys, workdir):
    code, out = capture(["--answers", str(SUPERSET), "--dry-run"], capsys)
    assert code == 0
    assert "PLAN for MyApp" in out
    assert not workdir.exists()
    assert (REPO / "template/generate.py").is_file()


def test_superset_dry_run_has_zero_destructive_operations(capsys):
    _, out = capture(["--answers", str(SUPERSET), "--dry-run"], capsys)
    assert "; 0 destructive operation(s)" in out
    assert "PRUNE files (disabled components / ops flags) (0)" in out
    assert "REMOVE include entries from project.yml (0)" in out
    assert "STRIP Swift marker blocks (0)" in out
    assert "RENAME paths (0)" in out


def test_minimal_dry_run_lists_prunes_renames_and_strips(capsys):
    _, out = capture(["--answers", str(MINIMAL), "--dry-run"], capsys)
    assert "MyApp/MyAppApp.swift -> Probe/ProbeApp.swift" in out
    assert "xcodegen/components/mac.yml" in out
    assert "MyApp/MyAppApp.swift: swiftdata x" in out
    assert "docs/onboarding-record.md" in out
    assert "; 0 destructive operation(s)" not in out


def test_missing_answers_file_is_an_error(capsys, workdir):
    code, _ = capture(["--answers", str(REPO / "nope.yaml"), "--dest", str(workdir)], capsys)
    assert code == 1


def test_dest_must_be_empty(workdir):
    workdir.mkdir(parents=True)
    (workdir / "stray.txt").write_text("x\n")
    proc = run_generate(SUPERSET, workdir)
    assert proc.returncode == 1
    assert "not empty" in proc.stderr


def test_dest_must_differ_from_the_template_repo():
    proc = run_generate(SUPERSET, REPO)
    assert proc.returncode == 1
    assert "must differ" in proc.stderr


def test_one_shot_refusal_when_template_is_gone(monkeypatch, tmp_path, capsys):
    monkeypatch.setattr(gen, "SOURCE", tmp_path)
    code = gen.main(["--answers", str(SUPERSET), "--apply"])
    captured = capsys.readouterr()
    assert code == 1
    assert "already been generated" in captured.err


def test_verify_runs_standalone_against_this_repo():
    import subprocess

    proc = subprocess.run(
        [sys.executable, str(TEMPLATE / "verify.py"), "--root", str(REPO)],
        capture_output=True, text=True,
    )
    assert proc.returncode == 0, proc.stdout + proc.stderr
    assert "template mode" in proc.stdout
