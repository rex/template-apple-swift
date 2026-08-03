# ADR 0001 — Superset walking skeleton + prune/rename assembly

- **Status:** Accepted
- **Date:** 2026-08-02
- **Deciders:** @pierce (owner), Fable (orchestrating agent)
- **Scope:** How this template physically produces a new app repo

## Context

Three candidate assembly strategies for a template that must hand agents a
working, compilable codebase: (a) a complete superset app that onboarding
prunes and renames; (b) component fragments a generator assembles; (c)
instructions an agent follows by hand. Fragments drift out of compile-ability
because no complete app exists to build; instructions are non-deterministic.
Pennywise (`rex/pennywise-apple-universal`) proves the superset shape in
production: 10 xcodegen-managed targets sharing one `Shared/` tree.

## Decision

The repo contains a **complete, generic, compiling superset app** — iOS app,
macOS app, watchOS app, home/Mac widgets, Live Activity, watch complications,
Notification Service Extension, unit tests, UI tests — plus capability modules
(SwiftData, StoreKit 2, Sign in with Apple + CloudKit, HealthKit). Onboarding
runs a deterministic generator that **renames** identity tokens and **prunes**
disabled components (whole files/dirs preferred, marker blocks where surgical).
Subtraction from a known-good build, never assembly toward one. Every supported
combination is CI-verifiable by generating and building it.

## Consequences

- The committed tree must always compile as-is (the superset IS a test fixture).
- Every component must be prunable: file boundaries are design constraints.
- Template CI carries a combo matrix (structural on Linux, compile on macOS).
- One-shot: the generator self-destructs at finalize (see ADR-0009).
