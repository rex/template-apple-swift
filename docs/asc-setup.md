# App Store Connect: the manual residue

Everything fastlane can automate is automated (`docs/release-automation.md`).
This file is the part that a human has to do, once, in a browser — and *why*
each item is here rather than in a lane. Nothing below is laziness on our
part: Apple's public API simply has no endpoint for it.

Work top to bottom. `make asc-bootstrap` fails with a pointer to the section
you skipped.

## 1. Enroll in the Apple Developer Program

$99/year, apple.com/developer. Individual or Organization — an Organization
needs a D-U-N-S number and takes days to weeks, so start it early if you need
one. You cannot ship to the App Store or notarise a Mac app without it.

Note your **Team ID** (10 characters, Membership Details). It replaces
`ABCDE12345` everywhere in the repo; onboarding does that rewrite for you.

## 2. Create the App Store Connect API key

Users and Access → Integrations → App Store Connect API → **Team Keys** → +

- Role: **App Manager** (Admin also works; Developer does not).
- Download the `.p8`. You get exactly one chance — Apple will not show it
  again.
- Copy the **Key ID** (10 chars) and the **Issuer ID** (a UUID, shown above
  the key list).

Not a Team key? `bootstrap_asc`, `certs` and `notarize` will fail: Individual
keys are barred from the provisioning endpoints and from notarytool.

Store all three in 1Password and wire `.env` as shown in
`docs/release-automation.md` §2. The `.p8` never enters git.

## 3. Create the app record

**App Store Connect → My Apps → + → New App.**

- Platforms: iOS (tick macOS too if the `mac` component is on — that is what
  makes Universal Purchase work, one record and one price for both stores).
- Bundle ID: pick `com.example.myapp` from the list. It only appears here
  after `make asc-bootstrap` has registered it, so run that first.
- SKU: any stable internal string; `myapp` is fine. Never changes, never
  shown to users.
- Primary language: matches your `fastlane/metadata/<locale>/` directory.

**Why this is manual:** Apple's public API has no create-app endpoint —
`POST /v1/apps` does not exist, and Apple's own guidance says to create apps
on the website. fastlane's `produce` *can* do it, but authenticates only with
an Apple ID + 2FA session, never with an API key. See §7 if you want that path
anyway.

## 4. Create the App Group

**Certificates, Identifiers & Profiles → Identifiers → App Groups → +**

- Description: `MyApp shared container`
- Identifier: **`group.com.example.myapp`** — exactly this string.

Then attach it to every identifier that needs it: Identifiers → each of the
bundle IDs `bootstrap_asc` registered → App Groups → Configure → tick the
group → Save.

This single string appears in 8 entitlements and one Swift constant. Get it
wrong and the failure is `exportArchive` exit 70 — a watch/extension pairing
error that says nothing about App Groups.

**Why this is manual:** there is no `/v1/appGroups` endpoint. The API can
enable the `APP_GROUPS` *capability* on a bundle ID (which `bootstrap_asc`
does) but cannot create the group itself or read back the association.
`bootstrap_asc` therefore stops and asks. Once you have verified the group
exists and is attached, acknowledge it:

```bash
export ASC_APP_GROUP_VERIFIED=1   # or put it in .env
```

## 5. Create the iCloud container (only with the `account` component)

**Identifiers → iCloud Containers → +**, identifier
`iCloud.com.example.myapp`. Then attach it to the app's bundle ID the same way
as the App Group. Same reason as §4: no public endpoint.

Skip this section entirely if `components.account` is false.

## 6. Drop in a 1024×1024 app icon

The template ships **empty icon wells on purpose** — a placeholder icon is
worse than none, because it survives to the App Store.

Put a 1024×1024 PNG in `MyApp/Assets.xcassets/AppIcon.appiconset/` and
reference it from `Contents.json` (dragging it onto the well in Xcode does
both). Requirements: no alpha channel, no rounded corners, no transparency —
Apple applies the mask.

The `beta` and `mac_beta` lanes preflight this and refuse to build without it,
which is much cheaper than discovering `ITMS-90022` after a 20-minute archive.

## 7. Optional: the Apple-ID escape hatch

If you would rather have `produce` create the app record than click through
the website, it can — interactively, on your machine, never in CI:

```bash
bundle exec fastlane spaceauth -u you@example.com   # complete 2FA, get a session
export FASTLANE_USER=you@example.com
export FASTLANE_SESSION='<the blob spaceauth printed>'
bundle exec fastlane produce -a com.example.myapp -q "MyApp" --skip_devcenter
```

`produce` also has `group`, `associate_group`, `cloud_container` and
`associate_cloud_container` subcommands that cover §4 and §5.

Two warnings. The session expires (days, sometimes hours) and re-authenticating
needs a human with the phone. And **never** shell out to `produce` from inside
an API-key lane: it will block on a 2FA prompt and hang the job until it times
out. This is why the lanes fail with instructions instead of trying.

## 8. Agreements, tax and banking

**App Store Connect → Business.** The Paid Applications agreement, tax forms
and a bank account are required before a paid app — or an app with any in-app
purchase — can be reviewed. The free-apps agreement is accepted automatically,
so a free app can skip this.

There is no API for any of it. Reviews sit in "Waiting for Review" forever
with no useful error when an agreement is unsigned, so check here first when
a submission seems stuck.

## 9. App Review

Fill in `fastlane/metadata/review_information/` before the first submission —
those files become the contact details and notes the reviewer sees. If your
app needs a login, add `demo_user.txt` and `demo_password.txt` alongside them
(use a throwaway demo account; anything in those files is committed).

`make release` runs `precheck` first and fails on the things App Review
rejects mechanically: placeholder copy, "coming soon", other platform names,
unreachable URLs, "free" next to a paid feature. What it cannot check is
whether the app does what the description says. Rejections, appeals and
expedited-review requests are a conversation with a human in the Resolution
Center — no lane will ever cover that.

## Checklist

- [ ] §1 Program membership active; Team ID noted
- [ ] §2 Team API key created; three values in 1Password
- [ ] `make asc-bootstrap` run (registers the bundle IDs)
- [ ] §3 App record created and bound to `com.example.myapp`
- [ ] §4 App Group created and attached; `ASC_APP_GROUP_VERIFIED=1`
- [ ] §5 iCloud container (only with the `account` component)
- [ ] §6 1024×1024 icon in the asset catalog
- [ ] §8 Agreements, tax and banking (only if you charge money)
- [ ] §9 `fastlane/metadata/review_information/` filled in
- [ ] `make asc-status` is clean, then `make testflight`
