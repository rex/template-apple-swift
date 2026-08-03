"""template-apple-swift generator internals.

Every module here is imported by `template/generate.py` (the one-shot
onboarding transform) or `template/verify.py` (the structural gate). The
package self-destructs with `template/` at the end of a successful
generation — nothing outside `template/` may import it.
"""

from __future__ import annotations

__all__ = [
    "answers",
    "checks_generated",
    "checks_structure",
    "checks_swift",
    "context",
    "docs",
    "fsutil",
    "gitops",
    "manifest",
    "predict",
    "prune",
    "rename",
    "schema",
    "settingsjson",
    "vibe",
    "workflows",
    "yamledit",
]
