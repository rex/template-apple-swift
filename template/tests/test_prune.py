"""Pure prune primitives: include-list surgery and marker stripping."""

from __future__ import annotations

import pytest
import yaml
from conftest import REPO

from tmpl.context import GenerateError
from tmpl.prune import rewrite_include_list, strip_marker_blocks

PROJECT = (REPO / "project.yml").read_text()

MARKED = """import SwiftUI

// @template:swiftdata BEGIN
import SwiftData
// @template:swiftdata END

struct Root: View {
    // @template:store BEGIN
    let store = StoreService()
    // @template:store END
    // @template:account BEGIN
    let account = AccountService()
    // @template:account END
}
"""


def test_strip_one_component_leaves_the_others():
    out, stripped = strip_marker_blocks(MARKED, {"store"})
    assert stripped == {"store": 1}
    assert "StoreService" not in out
    assert "AccountService" in out and "SwiftData" in out
    assert "@template:store" not in out


def test_strip_all_components_leaves_compiling_shape():
    out, stripped = strip_marker_blocks(MARKED, {"swiftdata", "store", "account"})
    assert stripped == {"swiftdata": 1, "store": 1, "account": 1}
    assert "@template:" not in out
    assert out.count("struct Root: View {") == 1


def test_strip_is_a_noop_for_enabled_components():
    out, stripped = strip_marker_blocks(MARKED, set())
    assert out == MARKED and stripped == {}


def test_unbalanced_marker_is_fatal():
    with pytest.raises(GenerateError, match="never closed"):
        strip_marker_blocks("// @template:store BEGIN\nlet x = 1\n", {"store"})


def test_every_real_marker_file_survives_a_full_strip(manifest):
    for rel, cids in manifest.all_marker_files.items():
        text = (REPO / rel).read_text()
        out, stripped = strip_marker_blocks(text, cids)
        assert stripped, rel
        assert "@template:" not in out, rel
        assert out.count("{") == out.count("}"), f"braces unbalanced after strip: {rel}"


def test_include_removal_drops_exactly_the_named_entries():
    out, removed = rewrite_include_list(PROJECT, ["xcodegen/components/mac.yml"])
    assert removed == ["xcodegen/components/mac.yml"]
    doc = yaml.safe_load(out)
    paths = [e["path"] for e in doc["include"]]
    assert "xcodegen/components/mac.yml" not in paths
    assert len(paths) == 9
    assert all(e["relativePaths"] is False for e in doc["include"])


def test_removing_every_include_removes_the_key_entirely():
    everything = [e["path"] for e in yaml.safe_load(PROJECT)["include"]]
    out, removed = rewrite_include_list(PROJECT, everything)
    assert sorted(removed) == sorted(everything)
    doc = yaml.safe_load(out)
    assert "include" not in doc, "an empty include: parses as null and fails xcodegen"
    assert doc["name"] == "MyApp" and doc["targets"]


def test_include_removal_is_idempotent():
    once, _ = rewrite_include_list(PROJECT, ["xcodegen/components/nse.yml"])
    twice, removed = rewrite_include_list(once, ["xcodegen/components/nse.yml"])
    assert removed == [] and twice == once


def test_include_removal_preserves_the_rest_of_the_document():
    out, _ = rewrite_include_list(PROJECT, ["xcodegen/components/health.yml"])
    before, after = yaml.safe_load(PROJECT), yaml.safe_load(out)
    before.pop("include"), after.pop("include")
    assert before == after
