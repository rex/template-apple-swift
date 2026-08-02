#!/usr/bin/env python3
"""Wave-1 Linux structural gate for template-apple-swift."""
import json, plistlib, re, subprocess, sys
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit("pyyaml missing")

ROOT = Path("/home/user/template-apple-swift")
fails, warns = [], []

def fail(msg): fails.append(msg)
def warn(msg): warns.append(msg)

tracked = subprocess.run(["git", "ls-files"], cwd=ROOT, capture_output=True, text=True).stdout.splitlines()
all_files = [p for p in ROOT.rglob("*") if p.is_file() and ".git" not in p.parts]

# 1. YAML parses
ymls = [ROOT / "project.yml"] + sorted((ROOT / "xcodegen/components").glob("*.yml")) + [ROOT / "template/components.yaml"]
docs = {}
for y in ymls:
    try:
        docs[y] = yaml.safe_load(y.read_text())
    except Exception as e:
        fail(f"YAML parse {y.name}: {e}")

# 2. No YAML markers remain
for y in ymls:
    if "@template:" in y.read_text() and y.name != "components.yaml":
        for i, line in enumerate(y.read_text().splitlines(), 1):
            if re.search(r"#\s*@template:\w", line):
                fail(f"YAML marker survives: {y.name}:{i}")

# 3. Swift marker lint
comp_doc = docs.get(ROOT / "template/components.yaml") or {}
known_ids = set((comp_doc.get("components") or {}).keys())
declared_marker_files = {}
for cid, c in (comp_doc.get("components") or {}).items():
    for mf in (c.get("marker_files") or []):
        declared_marker_files.setdefault(mf, set()).add(cid)
marker_re = re.compile(r"^\s*// @template:([\w-]+) (BEGIN|END)\s*$")
found_marker_files = {}
for sw in ROOT.rglob("*.swift"):
    rel = str(sw.relative_to(ROOT))
    stack = []
    ids_here = set()
    for i, line in enumerate(sw.read_text().splitlines(), 1):
        if "@template:" in line:
            m = marker_re.match(line)
            if not m:
                fail(f"malformed marker {rel}:{i}: {line.strip()}")
                continue
            cid, kind = m.groups()
            if cid not in known_ids:
                fail(f"unknown component id '{cid}' {rel}:{i}")
            if kind == "BEGIN":
                if stack: fail(f"nested marker {rel}:{i}")
                stack.append(cid)
            else:
                if not stack or stack[-1] != cid:
                    fail(f"unbalanced marker {rel}:{i}")
                else:
                    stack.pop()
            ids_here.add(cid)
    if stack:
        fail(f"unclosed marker(s) {rel}: {stack}")
    if ids_here:
        found_marker_files[rel] = ids_here
for rel, ids in found_marker_files.items():
    decl = declared_marker_files.get(rel, set())
    if not ids <= decl:
        fail(f"marker file {rel} carries undeclared ids {ids - decl} (declared: {decl or '{}'})")
for rel, ids in declared_marker_files.items():
    if rel not in found_marker_files:
        warn(f"declared marker file has no markers: {rel} ({ids})")

# 4. version/team keys only in Config/ (comment lines don't count)
for y in ymls:
    if y.name == "components.yaml": continue
    code_lines = [l for l in y.read_text().splitlines() if not l.lstrip().startswith("#")]
    for key in ("MARKETING_VERSION", "CURRENT_PROJECT_VERSION", "DEVELOPMENT_TEAM"):
        hits = [l for l in code_lines if key in l]
        if hits:
            fail(f"{key} appears in {y.name} (must live only in Config/*.xcconfig): {hits[0].strip()}")

# 5. include list <-> includes map <-> files on disk
proj = docs.get(ROOT / "project.yml") or {}
inc_entries = proj.get("include") or []
inc_paths = []
for e in inc_entries:
    if not isinstance(e, dict) or e.get("relativePaths") is not False:
        fail(f"include entry not object-form relativePaths:false: {e}")
    else:
        inc_paths.append(e["path"])
        if not (ROOT / e["path"]).is_file():
            fail(f"include file missing: {e['path']}")
inc_map = comp_doc.get("includes") or {}
map_paths = [f"xcodegen/components/{k}" for k in inc_map]
if sorted(inc_paths) != sorted(map_paths):
    fail(f"include list != components.yaml includes map:\n  project.yml: {sorted(inc_paths)}\n  map: {sorted(map_paths)}")
for k, req in inc_map.items():
    for r in req:
        if r not in known_ids: fail(f"includes map {k} requires unknown component {r}")

# 6. line caps (hard 400) on code files
for f in all_files:
    if f.suffix in (".swift", ".py", ".sh", ".rb"):
        n = len(f.read_text().splitlines())
        if n > 400: fail(f"line cap: {f.relative_to(ROOT)} = {n} > 400")
        elif n > 250: warn(f"soft cap: {f.relative_to(ROOT)} = {n} > 250")

# 7. forbidden patterns in Swift
forbidden = [
    (r"\bObservableObject\b", "ObservableObject"), (r"@Published\b", "@Published"),
    (r"@StateObject\b", "@StateObject"), (r"@EnvironmentObject\b", "@EnvironmentObject"),
    (r"canImport\(ActivityKit\)", "canImport(ActivityKit) guard"),
    (r"[Pp]ennywise", "Pennywise residue"), (r"(?i)influx", "influx residue"),
]
for sw in ROOT.rglob("*.swift"):
    code = "\n".join(l for l in sw.read_text().splitlines()
                     if not l.lstrip().startswith("//") and not l.lstrip().startswith("///"))
    for pat, name in forbidden:
        if re.search(pat, code):
            fail(f"forbidden [{name}] in {sw.relative_to(ROOT)}")

# 8. containerBackground in widget/complication view files (NOT LiveActivity —
# lock-screen presentations use activityBackgroundTint, not containerBackground)
for d in ("HomeWidget", "MacWidget", "WatchComplications"):
    texts = "".join(p.read_text() for p in (ROOT / d).glob("*.swift"))
    if "containerBackground" not in texts:
        fail(f"no containerBackground call in {d}/")

# 9. yml source paths exist (skip optional:true, generated plists/entitlements, Generated/)
def walk_sources(target_name, tdef, src_yml):
    for s in (tdef.get("sources") or []):
        if isinstance(s, str): s = {"path": s}
        p, opt = s.get("path"), s.get("optional", False)
        if p is None: continue
        if opt: continue
        if not (ROOT / p).exists():
            fail(f"{src_yml}: target {target_name} source path missing: {p}")
merged_targets = {}
for y in ymls:
    if y.name == "components.yaml": continue
    d = docs.get(y) or {}
    for tn, td in (d.get("targets") or {}).items():
        merged_targets.setdefault(tn, []).append(y.name)
        if isinstance(td, dict): walk_sources(tn, td, y.name)

# 10. components.yaml owns paths exist
for cid, c in (comp_doc.get("components") or {}).items():
    for dpath in ((c.get("owns") or {}).get("dirs") or []):
        if not (ROOT / dpath).is_dir(): fail(f"components.yaml {cid} owns.dir missing: {dpath}")
    for fpath in ((c.get("owns") or {}).get("files") or []):
        if not (ROOT / fpath).is_file(): fail(f"components.yaml {cid} owns.file missing: {fpath}")

# 11. plists parse
for p in list(ROOT.rglob("PrivacyInfo.xcprivacy")) + [ROOT / "Shared/Env/Environment.example.plist"]:
    try: plistlib.loads(p.read_bytes())
    except Exception as e: fail(f"plist parse {p.relative_to(ROOT)}: {e}")

# 12. JSON assets parse
for j in list((ROOT / "MyApp/Assets.xcassets").rglob("*.json")) + [ROOT / "Shared/Resources/Localizable.xcstrings", ROOT / "template/answers.schema.json"]:
    try: json.loads(j.read_text())
    except Exception as e: fail(f"JSON parse {j.relative_to(ROOT)}: {e}")

# 13. App Group count in YAML == 8
ag = sum(y.read_text().count("group.com.example.myapp") for y in ymls if y.name != "components.yaml")
if ag != 8: fail(f"App Group appears {ag}x in xcodegen YAML (expect 8: one per target)")

# 14. cross-partition API checks
sds = (ROOT / "Shared/Store/SwiftDataCheckpointStore.swift").read_text()
app = (ROOT / "MyApp/MyAppApp.swift").read_text()
if "makeContainer" in app and "static func makeContainer" not in sds.replace("public static func makeContainer", "static func makeContainer"):
    if "func makeContainer" not in sds: fail("MyAppApp calls SwiftDataCheckpointStore.makeContainer but no such func")
if "SwiftDataCheckpointStore(container:" in app and "init(container:" not in sds:
    fail("MyAppApp calls SwiftDataCheckpointStore(container:) but no such init")
lac = (ROOT / "MyApp/Services/LiveActivityController.swift").read_text()
if "func sync(session:" not in lac.replace("public func sync(session:", "func sync(session:"):
    if "func sync(" not in lac: fail("LiveActivityController.sync missing")
wl = (ROOT / "Shared/Sync/WatchLink.swift").read_text()
for need in ("func pushContext(", "static let shared"):
    if need not in wl: fail(f"WatchLink missing {need}")
ws = (ROOT / "Shared/Sync/WatchSync.swift").read_text()
if "init(_ snapshot: WidgetSnapshot)" not in ws: fail("WatchPayload(WidgetSnapshot) init missing")

# 15. NSE principal class name matches nse.yml
nse_yml = (ROOT / "xcodegen/components/nse.yml").read_text()
if "NotificationService" not in nse_yml: warn("nse.yml has no principal-class reference to check")
if "class NotificationService" not in (ROOT / "NotificationService/NotificationService.swift").read_text():
    fail("NSE principal class 'NotificationService' not found")

print(f"tracked files: {len(tracked)}; scanned: {len(all_files)}")
print(f"\n== {len(fails)} FAIL ==")
for f in fails: print("  FAIL:", f)
print(f"== {len(warns)} WARN ==")
for w in warns: print("  warn:", w)
sys.exit(1 if fails else 0)
