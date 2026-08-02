"""Shared fixtures. Run with:

    uv run --with pytest,pyyaml -m pytest template/tests -q
"""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

import pytest

TEMPLATE = Path(__file__).resolve().parent.parent
REPO = TEMPLATE.parent
sys.path.insert(0, str(TEMPLATE))

from tmpl import answers as answers_mod  # noqa: E402
from tmpl import fsutil  # noqa: E402
from tmpl import manifest as manifest_mod  # noqa: E402
from tmpl.context import Ctx  # noqa: E402


@pytest.fixture(scope="session")
def repo() -> Path:
    return REPO


@pytest.fixture(scope="session")
def manifest():
    return manifest_mod.load(TEMPLATE / "components.yaml")


@pytest.fixture(scope="session")
def source_files() -> set[str]:
    return set(fsutil.list_files(REPO))


@pytest.fixture(scope="session")
def combos() -> dict[str, Path]:
    return {p.stem: p for p in sorted((TEMPLATE / "ci-combos").glob("*.yaml"))}


def load_answers(path: Path, manifest):
    return answers_mod.load(path, TEMPLATE / "answers.schema.json", manifest)


def make_ctx(root: Path, answers_path: Path, manifest, *, dry_run: bool = False) -> Ctx:
    doc, ident, _ = load_answers(answers_path, manifest)
    return Ctx(root=root, source=REPO, ident=ident, answers=doc, manifest=manifest, dry_run=dry_run)


def copy_repo(dest: Path) -> Path:
    fsutil.copy_repo(REPO, dest)
    return dest


def run_generate(answers: Path, dest: Path, *extra: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(TEMPLATE / "generate.py"), "--answers", str(answers),
         "--dest", str(dest), *extra],
        capture_output=True,
        text=True,
        cwd=REPO,
    )


def run_verify(root: Path) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(TEMPLATE / "verify.py"), "--root", str(root)],
        capture_output=True,
        text=True,
        cwd=REPO,
    )


@pytest.fixture
def workdir(tmp_path: Path) -> Path:
    out = tmp_path / "tree"
    shutil.rmtree(out, ignore_errors=True)
    return out
