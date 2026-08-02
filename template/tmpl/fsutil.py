"""Filesystem primitives: which files exist, which are text, how to copy.

The generator only ever touches files git would track. `git ls-files
--cached --others --exclude-standard` is the source of truth (tracked plus
untracked-but-not-ignored), so a build directory, a DerivedData tree or a
local `answers.local.yaml` never rides along into a generated repo.
"""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

# Extensions the rename engine must never rewrite (contracts §1 skip-list,
# widened to every binary asset an Apple repo realistically carries).
# .txt and .json are deliberately ABSENT: the spinner corpora and
# .claude/settings.json are normal text for substitution (contracts §12).
BINARY_SUFFIXES = frozenset(
    """
    .png .jpg .jpeg .gif .heic .heif .webp .tiff .icns .ico .pdf .car
    .ttf .otf .woff .woff2 .dfont
    .zip .gz .bz2 .xz .tar .dmg .ipa .xcarchive .a .dylib .framework .o
    .mp3 .mp4 .m4a .mov .wav .aiff .caf .aac
    .p8 .p12 .cer .mobileprovision .der .pem .keystore
    .xcuserstate .xcuserdatad .profraw .profdata .bin .dat .sqlite .db
    """.split()
)

# Directories the generator never rewrites or renames.
SKIP_DIRS = ("template", ".git")


def list_files(root: Path) -> list[str]:
    """Relative paths of every file git would consider part of the repo."""
    try:
        proc = subprocess.run(
            ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
            cwd=root,
            capture_output=True,
            check=True,
        )
        rels = [r for r in proc.stdout.decode().split("\0") if r]
        if rels:
            return sorted({r for r in rels if (root / r).is_file()})
    except (OSError, subprocess.CalledProcessError):
        pass
    return sorted(
        str(p.relative_to(root))
        for p in root.rglob("*")
        if p.is_file() and ".git" not in p.parts
    )


def walk_files(root: Path, *, skip_dirs: tuple[str, ...] = SKIP_DIRS) -> list[Path]:
    """Every file on disk under `root`, minus the skipped top-level trees.

    Used after mutation, when `git ls-files` would still be describing the
    pre-generation tree.
    """
    out: list[Path] = []
    for p in root.rglob("*"):
        if not p.is_file():
            continue
        parts = p.relative_to(root).parts
        if parts and parts[0] in skip_dirs:
            continue
        out.append(p)
    return sorted(out)


def is_binary(path: Path) -> bool:
    """Extension skip-list first, NUL-byte sniff as the backstop."""
    if path.suffix.lower() in BINARY_SUFFIXES:
        return True
    try:
        chunk = path.open("rb").read(8192)
    except OSError:
        return True
    if b"\0" in chunk:
        return True
    try:
        chunk.decode("utf-8")
    except UnicodeDecodeError:
        return True
    return False


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def copy_repo(src: Path, dest: Path) -> list[str]:
    """Copy the git-visible tree from `src` into `dest`. Returns the paths."""
    rels = list_files(src)
    if not rels:
        raise RuntimeError(f"no files to copy from {src}")
    dest.mkdir(parents=True, exist_ok=True)
    for rel in rels:
        target = dest / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src / rel, target)
    return rels


def prune_empty_dirs(root: Path, *, skip_dirs: tuple[str, ...] = (".git",)) -> list[str]:
    """Remove directories left empty by pruning. Deepest first."""
    removed: list[str] = []
    dirs = sorted(
        (p for p in root.rglob("*") if p.is_dir()),
        key=lambda p: len(p.parts),
        reverse=True,
    )
    for d in dirs:
        parts = d.relative_to(root).parts
        if parts and parts[0] in skip_dirs:
            continue
        try:
            next(d.iterdir())
        except StopIteration:
            d.rmdir()
            removed.append(str(d.relative_to(root)))
        except OSError:
            continue
    return removed
