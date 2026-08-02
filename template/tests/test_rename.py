"""The rename engine: single-pass, longest-first, no re-entry."""

from __future__ import annotations

from tmpl.answers import Ident
from tmpl.rename import substitute, token_map

PROBE = Ident("Probe", "Probe", "io.example.probe", "T1E2A3M4X5", "probe")
NOOP = Ident("MyApp", "MyApp", "com.example.myapp", "ABCDE12345", "myapp")
# The trap case: the new bundle root CONTAINS the old slug.
NESTED = Ident("Widget", "Widget", "com.acme.myapp", "T1E2A3M4X5", "widget")


def test_identity_answers_produce_no_tokens():
    assert token_map(NOOP) == []
    assert substitute("MyApp com.example.myapp", NOOP) == "MyApp com.example.myapp"


def test_longest_first_ordering():
    text = "group.com.example.myapp / com.example.myapp / MyApp / myapp"
    assert substitute(text, PROBE) == (
        "group.io.example.probe / io.example.probe / Probe / probe"
    )


def test_single_pass_never_rewrites_its_own_output():
    """`com.acme.myapp` must survive: a second pass would eat its `myapp`."""
    assert substitute("com.example.myapp", NESTED) == "com.acme.myapp"
    assert substitute("MyApp uses com.example.myapp", NESTED) == "Widget uses com.acme.myapp"


def test_derived_identifiers_follow_the_bundle_root():
    assert substitute("com.example.myapp.refresh", PROBE) == "io.example.probe.refresh"
    assert substitute("iCloud.com.example.myapp", PROBE) == "iCloud.io.example.probe"
    assert substitute("com.example.myapp.watch.complications", PROBE) == (
        "io.example.probe.watch.complications"
    )


def test_target_and_path_names():
    for old, new in [
        ("MyApp/MyAppApp.swift", "Probe/ProbeApp.swift"),
        ("Tests/MyAppTests/ThemeTests.swift", "Tests/ProbeTests/ThemeTests.swift"),
        ("MyAppMac/MacRootView.swift", "ProbeMac/MacRootView.swift"),
        ("MyAppScreenshots", "ProbeScreenshots"),
    ]:
        assert substitute(old, PROBE) == new


def test_team_id_is_a_token():
    assert substitute("DEVELOPMENT_TEAM = ABCDE12345", PROBE) == (
        "DEVELOPMENT_TEAM = T1E2A3M4X5"
    )


def test_case_sensitivity():
    assert substitute("MYAPP", PROBE) == "MYAPP"
    assert substitute("Myapp", PROBE) == "Myapp"
