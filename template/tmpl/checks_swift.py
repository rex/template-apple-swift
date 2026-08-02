"""Swift-source checks: marker hygiene, banned APIs, widget and API contracts.

Split out of `checks_structure` so each module stays inside the 250-line soft
cap and so the YAML/plist half can be read without wading through Swift rules.
"""

from __future__ import annotations

import re
from pathlib import Path

from .answers import Ident
from .manifest import MARKER_RE, Manifest

# Every one of these is a real regression the template must never reintroduce:
# the first four are pre-@Observable SwiftUI, `canImport(ActivityKit)` is the
# macOS trap (the module imports, the types do not exist), and the last two are
# residue from the repo this template's patterns were mined from.
FORBIDDEN = [
    (r"\bObservableObject\b", "ObservableObject"),
    (r"@Published\b", "@Published"),
    (r"@StateObject\b", "@StateObject"),
    (r"@EnvironmentObject\b", "@EnvironmentObject"),
    (r"canImport\(ActivityKit\)", "canImport(ActivityKit) guard"),
    (r"[Pp]ennywise", "Pennywise residue"),
    (r"(?i)influx", "influx residue"),
]

# Lock-screen Live Activity presentations use activityBackgroundTint, so
# LiveActivity/ is deliberately absent from this list. (R4 V8)
WIDGET_DIRS = ("HomeWidget", "MacWidget", "WatchComplications")


def markers(res, root: Path, manifest: Manifest) -> None:
    """Balanced, non-nested, known-ID marker blocks in declared files only."""
    known = manifest.component_ids
    by_base = {Path(rel).name: cids for rel, cids in manifest.all_marker_files.items()}
    for sw in sorted(root.rglob("*.swift")):
        rel, stack, here = str(sw.relative_to(root)), [], set()
        for i, line in enumerate(sw.read_text(encoding="utf-8").splitlines(), 1):
            if "@template:" not in line:
                continue
            match = MARKER_RE.match(line)
            if match is None:
                res.fail(f"malformed marker {rel}:{i}: {line.strip()}")
                continue
            cid, kind = match.groups()
            if cid not in known:
                res.fail(f"unknown component id '{cid}' {rel}:{i}")
            if kind == "BEGIN":
                if stack:
                    res.fail(f"nested marker {rel}:{i}")
                stack.append(cid)
            elif not stack or stack[-1] != cid:
                res.fail(f"unbalanced marker {rel}:{i}")
            else:
                stack.pop()
            here.add(cid)
        if stack:
            res.fail(f"unclosed marker(s) {rel}: {stack}")
        extra = here - by_base.get(Path(rel).name, set())
        if extra:
            res.fail(f"marker file {rel} carries undeclared ids {sorted(extra)}")


def forbidden(res, root: Path) -> None:
    for sw in sorted(root.rglob("*.swift")):
        code = "\n".join(
            l for l in sw.read_text(encoding="utf-8").splitlines()
            if not l.lstrip().startswith("//")
        )
        for pattern, name in FORBIDDEN:
            if re.search(pattern, code):
                res.fail(f"forbidden [{name}] in {sw.relative_to(root)}")


def container_background(res, root: Path) -> None:
    """Without it the system renders an 'adopt containerBackground' placeholder."""
    for name in WIDGET_DIRS:
        directory = root / name
        if not directory.is_dir():
            continue
        text = "".join(p.read_text(encoding="utf-8") for p in sorted(directory.glob("*.swift")))
        if "containerBackground" not in text:
            res.fail(f"no .containerBackground(for: .widget) call in {name}/ (R4 V8)")


def cross_target_api(res, root: Path, ident: Ident) -> None:
    """APIs one target calls and another declares. Absent files are pruned, not broken."""
    checks = [
        ("Shared/Sync/WatchLink.swift", ["func pushContext(", "static let shared"]),
        ("Shared/Sync/WatchSync.swift", ["init(_ snapshot: WidgetSnapshot)"]),
        (f"{ident.app_name}/Services/LiveActivityController.swift", ["func sync("]),
        ("Shared/Store/SwiftDataCheckpointStore.swift", ["func makeContainer"]),
        ("NotificationService/NotificationService.swift", ["class NotificationService"]),
    ]
    for rel, needles in checks:
        path = root / rel
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        for needle in needles:
            if needle not in text:
                res.fail(f"{rel}: expected API '{needle}' not found")
