# Keys, auth and signing

Setup instructions live in `docs/release-automation.md` §2 (the API key) and
§6 (signing). This file is the contract and the reasoning — the parts that
decide whether a lane can work at all.

## The App Store Connect API key

**It must be a Team key** with the App Manager or Admin role. An *Individual*
key cannot use the provisioning endpoints or notarytool, so it breaks
`bootstrap_asc`, `certs` and `notarize` — and the error message never says
"your key is the wrong type". If a lane fails at auth and the credentials look
correct, check the key type first.

Three environment names, ours and not fastlane's:

| Variable | Holds |
|---|---|
| `APP_STORE_CONNECT_API_KEY` | the `.p8` **base64-encoded** (CI-friendly form) |
| `APP_STORE_CONNECT_API_KEY_P8_PATH` | *or* a path to a real `.p8` on disk (local only) |
| `APP_STORE_CONNECT_API_KEY_ID` | the 10-character Key ID |
| `APP_STORE_CONNECT_API_ISSUER` | the issuer UUID |

Set exactly one of the first two; the Fastfile errors when both or neither are
present. fastlane's own `APP_STORE_CONNECT_API_KEY_KEY_ID` / `_ISSUER_ID` /
`_KEY` names are deliberately **not** used — `before_all` calls
`app_store_connect_api_key` explicitly with our names as parameters
(`duration: 1200`, `in_house: false`), so there is one place to look when auth
misbehaves rather than an ambient env-var contract.

Storage: 1Password references in `.env`, resolved at exec time by
`op run --env-file=.env -- bundle exec fastlane <lane>`. Never a `.p8` in the
repo. `.gitignore` blocks `*.p8`, `*.p12` and `*.mobileprovision`, and
`.claude/settings.json` denies agent reads of all of them plus
`fastlane/.env*`. Do not route around either.

In CI the same three names become repository secrets.

## Automatic (cloud) signing — the default

For **App Store distribution** it genuinely works on an ephemeral runner:
Xcode 13+ cloud-managed distribution certificates keep the private key with
Apple, so there is nothing to import.

The plumbing is less obvious than it looks. **gym has no native
`-allowProvisioningUpdates` and no ASC-key support** — none of its 55 options
touch provisioning, and its command generators never emit those flags. The
only injection points are `xcargs` (build phase) and `export_xcargs` (export
phase), and the lane must thread the flags through **both**:

```
-allowProvisioningUpdates
-authenticationKeyPath <absolute path to a real .p8>
-authenticationKeyID <key id>
-authenticationKeyIssuerID <issuer>
```

`-authenticationKeyPath` needs a real file at an absolute path, so a base64
env var must be materialised to a temporary `.p8` first. That is why the lane
does it rather than leaving it to gym.

`ExportOptions.plist` is committed for the manual
`xcodebuild -exportArchive` path; gym regenerates its own copy every run, so
the two can drift and `assert_export_options` fails the lane when they
disagree. It must use the **legacy** method spellings — `app-store`,
`developer-id` — because gym's `export_method` whitelist rejects Xcode 15's
`app-store-connect` and `release-testing`.

## When to switch to `match`

Turn it on when any of these is true:

- **You ship a Developer ID / notarised Mac build.** Developer ID certificates
  are not cloud-managed. This is the strongest reason and it is not negotiable
  by preference.
- More than one human or machine signs the app.
- You want signing state reviewable and revocable in one private repo.

Turning it on: create a private certs repo, set `MATCH_GIT_URL` and
`MATCH_PASSWORD`, run `bundle exec fastlane certs readonly:false` once on a
Mac, and set `ops.signing: match` so the documentation agrees with reality.

**CI must never mint certificates.** `certs` defaults `readonly` to `is_ci`,
and when `match` is on every CI lane calls `setup_ci` — which creates the
temporary keychain, so nobody hand-rolls `security create-keychain`. `setup_ci`
forces read-only anyway.

## Ruby and platform constraints

`Gemfile` and `Gemfile.lock` are committed, `fastlane` is pinned, and
`.ruby-version` is a 3.4.x. There is no `Pluginfile` — every lane uses core
actions only, so `bundle install` is the whole setup.

Linux jobs export `LC_ALL=C.UTF-8 LANG=C.UTF-8`. API-only lanes (`metadata`,
`status`, `bootstrap_asc`, and pilot's distribute half) run there happily.
`beta`, `mac_beta`, `screenshots`, `notarize` and `certs` guard with an
explicit `FastlaneCore::Helper.mac?` check, because gym does **not** fail
closed on a non-Mac host — it fails confusingly instead.

## Coexisting with Xcode Cloud

Both are supported and they do not conflict. Xcode Cloud runs
`ci_scripts/ci_post_clone.sh` on Apple's runners and needs no API key; archive
and TestFlight distribution are native Xcode Cloud actions. fastlane and Xcode
Cloud are disjoint consumers of the same `Config/Versions.xcconfig` write step.

One rule: **pick one archiver per tag.** Two archivers on one commit means
double-incremented build numbers and two App Store Connect builds claiming the
same version.
