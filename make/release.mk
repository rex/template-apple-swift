# make/release.mk — 1:1 delegation to the fastlane lanes (contracts §8).
#
# The lane names are the API; these targets add nothing but a memorable verb.
# Every lane resolves its own credentials (App Store Connect API key via the
# three APP_STORE_CONNECT_* env names) and guards itself on macOS where it has
# to, so there is deliberately no logic here to keep in sync.
#
# Two lanes have no Make target by contract: run them directly as
#   bundle exec fastlane mac_beta
#   bundle exec fastlane certs
#
# Setup, auth and the manual App Store Connect residue: docs/release-automation.md
# and docs/asc-setup.md.

.PHONY: testflight screenshots metadata-push release asc-status asc-bootstrap notarize-mac

## testflight: Archive the iOS app and ship it to TestFlight
testflight:
	$(FASTLANE) beta

## screenshots: Capture App Store screenshots (iOS simulators)
screenshots:
	$(FASTLANE) screenshots

## metadata-push: Push metadata + screenshots to App Store Connect
metadata-push:
	$(FASTLANE) metadata

## release: precheck, then submit for App Store review
release:
	$(FASTLANE) release

## asc-status: Dump App Store Connect state + verify the bundle-ID registry
asc-status:
	$(FASTLANE) status

## asc-bootstrap: Register/verify bundle IDs + capabilities in ASC
asc-bootstrap:
	$(FASTLANE) bootstrap_asc

## notarize-mac: Developer ID build + notarytool
notarize-mac:
	$(FASTLANE) notarize

