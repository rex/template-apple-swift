# Questions — W2B (fastlane suite)

Cross-partition items and documented deviations. None blocked delivery; each
is coded to the contract as written, with the workaround isolated and
commented so a gate decision is a one-line change.

## Q1 — `SIGN_IN_WITH_APPLE` is not a real ASC capability type (components.yaml)

`template/components.yaml` (W2A partition) declares:

```yaml
  account:
    asc:
      capabilities: [SIGN_IN_WITH_APPLE, ICLOUD]
```

Apple's `BundleIdCapability.capabilityType` enum has no `SIGN_IN_WITH_APPLE`.
The value is **`APPLE_ID_AUTH`** — verified in the installed gem at
`spaceship/lib/spaceship/connect_api/models/bundle_id_capability.rb` (R1 V6
says the same). Posting the registry spelling would 400 at
`POST /v1/bundleIdCapabilities`.

**Done:** `fastlane/Fastfile`'s `COMPONENT_ASC` table uses `APPLE_ID_AUTH`
with a comment naming the normalisation.
**Ask:** W2A/Fable change components.yaml to `APPLE_ID_AUTH` so the registry
and the wire agree, and drop the comment.

Related, smaller: components.yaml puts `PUSH_NOTIFICATIONS` under
`nse.asc.capabilities` next to the NSE's own bundle ID. `aps-environment`
lives in the **host** entitlements (contracts §3), so the lane enables
`PUSH_NOTIFICATIONS` on `com.example.myapp` and `APP_GROUPS` on the extension
ID. Same ask: make the registry say which ID each capability lands on, or
confirm the current reading is intended.

## Q2 — Snapfile devices: 6.9" iPhone, not the plain iPhone 17

The brief said "devices per R2: iPhone 17 + one iPad". Shipped instead:
`iPhone 17 Pro Max` + `iPad Pro 13-inch (M5)` — both names verified on the
macos-26 image (R2 V4).

Reason: deliver routes screenshots by pixel resolution, and Apple's required
slot is the **6.9" iPhone** (1320×2868 → `APP_IPHONE_67`). A plain iPhone 17
is 6.3" and produces 1206×2622, which lands in the optional `APP_IPHONE_61`
slot — the required set would come out empty and App Store Connect would
reject the submission. `iPhone 17` remains the default *test* device
(ADR-0003, Makefile `DEVICE`); this is only the screenshot matrix. The
trade-off is written out in `fastlane/Snapfile` so nobody "fixes" it back.

**Ask:** confirm, or say the word and I'll flip it.

## Q3 — `notarize` lane name collides with the `notarize` action

fastlane prints one red line per invocation:

```
Name of the lane 'notarize' is already taken by the action named 'notarize'
```

It is cosmetic and there is no opt-out (`Lane#ensure_name_not_conflicts`
always logs). Behaviour is unambiguous and verified here: `fastlane notarize`
on the CLI runs the LANE, `notarize(...)` inside the lane runs the ACTION
(`Runner#trigger_action_by_name` resolves actions first), so there is no
recursion.

`notarize` is a frozen lane name (contracts §8) and `make notarize-mac`
depends on it, so it stays. `fastlane/MacFastfile` carries a
"do not rename this to silence the warning" comment above the lane.

**Ask:** accept the warning (recommended), or rename to something like
`notarize_mac` at the gate — a contracts §8 amendment plus one Make target.

## Q4 — `.gitignore` additions (W1A partition)

`.gitignore` already covers `fastlane/screenshots/**/*.png`,
`fastlane/report.xml`, `fastlane/Preview.html`, `fastlane/test_output`,
`build/`, `.env`, `*.p8`, `*.p12`, `*.mobileprovision` — everything W2B
produces except one path:

```
fastlane/screenshots-mac/**/*.png
```

That directory is where hand-captured Mac screenshots go (snapshot cannot
drive macOS). It does not exist in the template — its absence is what makes
the `metadata` lane skip the macOS screenshot upload — so this is a
nice-to-have for generated repos, not a defect.

**Ask:** W1A/W2C append the line, or explicitly decide Mac screenshots are
committed.

## Q5 — no Make target for `mac_beta` / `certs`

contracts §8 freezes seven Make targets and nine lanes. `mac_beta` and
`certs` therefore have no target and are invoked as
`bundle exec fastlane mac_beta` / `certs`. I did not invent
`make mac-testflight` / `make certs` — that is W2C's partition and a contract
question, not an implementation one. Documented in `handoff-w2b.md` §1.

## Q6 — five Fastfiles, not one

A single Fastfile carrying all nine lanes plus the Spaceship bootstrap came to
466 lines, over the 400 hard cap. Split by responsibility, all `import`ed from
`fastlane/Fastfile` and all listed by `fastlane lanes` as one flat set:

| File | Lines | Owns |
|---|---|---|
| `Fastfile` | 171 | identity, component map, hooks, guards/preflights |
| `SigningFastfile` | 151 | ASC auth, key materialisation, xcargs, `certs` |
| `ShipFastfile` | 139 | `beta`, `screenshots`, `metadata`, `release` |
| `MacFastfile` | 100 | `mac_beta`, `notarize` |
| `ASCFastfile` | 246 | `bootstrap_asc`, `status` |

Flagged only so W2A/W2D docs that enumerate files list all five.

## Q7 — `BUNDLED WITH 4.0.17`

`Gemfile.lock` was generated here with Bundler 4.0.17 and records it. Ruby
3.4.10 ships Bundler 2.6.x, so the first `bundle install` on a fresh Mac or
runner auto-fetches 4.0.17 before installing. Standard behaviour, needs
network, adds a few seconds once. Called out in
`docs/release-automation.md` §1.

**Ask:** none — flagging in case the gate prefers a 2.x lock, which would
mean regenerating with `gem install bundler -v 2.6.9 && bundle _2.6.9_ lock`.
