# frozen_string_literal: true

# Ruby toolchain for release automation (ADR-0002).
#
#   bundle install            # once, after `brew install rbenv` / mise / rvm
#   bundle exec fastlane lanes
#
# `Gemfile.lock` is committed and CI installs against it unchanged
# (`bundle install --frozen` / `BUNDLE_FROZEN=true`). The lock carries the
# darwin platforms as well as x86_64-linux so the same lock resolves on an
# Apple-silicon Mac, an Intel Mac, and a Linux CI runner.
#
# `.ruby-version` pins the interpreter (3.4.x — the only Ruby line fastlane
# tests against Xcode 26.x). macOS system Ruby is NOT usable; install a real
# Ruby with rbenv/mise/rvm first.

source "https://rubygems.org"

# fastlane 2.237.0 (2026-07-05). Pinned exactly, not `~>`: a fastlane minor
# bump can change action option names, and every lane in fastlane/Fastfile is
# written against this version's surface (`fastlane_version` in the Fastfile
# asserts the same floor at runtime).
gem "fastlane", "2.237.0"

# Deliberately NO Pluginfile.
#
# The conventional fastlane Gemfile ends with:
#     plugins_path = File.join(File.dirname(__FILE__), "fastlane", "Pluginfile")
#     eval_gemfile(plugins_path) if File.exist?(plugins_path)
#
# Every lane here uses core actions only (gym, pilot, deliver, precheck,
# snapshot, frameit, match, notarize, app_store_connect_api_key, setup_ci,
# produce, plus the Spaceship library directly). The absence of a Pluginfile
# is itself the signal: if you ever run `fastlane add_plugin`, re-add the
# eval_gemfile lines above and say why in an ADR.
