# ADR 0004 — v1 component menu scope

- **Status:** Accepted
- **Date:** 2026-08-02
- **Deciders:** @pierce (owner)
- **Scope:** What the onboarding wizard offers in v1

## Context

Every component in the menu must be prunable, documented, ASC-registrable, and
CI-verifiable. Scope discipline keeps the compile matrix honest. Pennywise
proves one set in production; the lang-swift-apple north star prescribes
StoreKit 2 and Sign in with Apple patterns beyond it.

## Decision

v1 menu = the Pennywise-proven set — iOS app (always on), macOS app, watchOS
app, home widgets, Mac widgets, Live Activity, watch complications,
Notification Service (push), App Groups (always on), SwiftData toggle,
HealthKit toggle (off by default, iOS-only in v1) — **plus** two north-star
capability modules: StoreKit 2/IAP (`store`) and Sign in with Apple + CloudKit
(`account`). **No visionOS or tvOS in v1.** Component IDs and dependency rules
are frozen in `template/components.yaml`.

## Consequences

- visionOS/tvOS become additive component work in a future version (the
  include-based project.yml composition in ADR-0006 makes that a new component
  file, not a restructure).
- `store` and `account` are new ground not proven by Pennywise — they ship as
  deliberately minimal stubs exercising the real APIs, verified by the macOS
  compile matrix.
- The `store` stub is API-driven (`Product.products` / `purchase` /
  `Transaction.updates` / `Transaction.currentEntitlements`), not
  `SubscriptionStoreView`. SwiftUI's merchandising views need a real App Store
  Connect subscription group and render a failure state against the template's
  placeholder identifiers; they are documented as the production upgrade path.
  (R4 V16)
