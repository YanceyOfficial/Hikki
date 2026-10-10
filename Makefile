# swiftly's toolchain shadows Xcode's and breaks SwiftPM manifest compilation under Tuist.
export PATH := $(shell echo "$$PATH" | tr ':' '\n' | grep -v swiftly | paste -sd: -)

IOS_SIM ?= generic/platform=iOS Simulator

.PHONY: bootstrap tokens lint-design editor generate test test-web test-core test-core-ios build-mac build-ios check

bootstrap:
	cd editor && pnpm install
	tuist install

# Design tokens: edit design/tokens.json, then regenerate Swift + the Tailwind theme.
tokens:
	node scripts/gen-tokens.mjs

# Fails on stale generated tokens or on literal colors/fonts/spacing in view code.
lint-design:
	node scripts/gen-tokens.mjs --check
	scripts/lint-design.sh

editor:
	cd editor && pnpm build

generate: editor
	tuist generate --no-open

test-web:
	cd editor && pnpm typecheck && pnpm test

# `tuist test` regenerates a test-focused workspace; regenerate the full one afterwards so the
# Hikki scheme exists again for builds and UI tests.
test-core:
	tuist test HikkiCore --platform macos
	tuist generate --no-open

test-core-ios:
	tuist test HikkiCore --platform ios

test: lint-design test-web test-core

build-mac: generate
	xcodebuild -workspace Hikki.xcworkspace -scheme Hikki -destination 'platform=macOS' build -quiet

build-ios: generate
	xcodebuild -workspace Hikki.xcworkspace -scheme Hikki -destination '$(IOS_SIM)' build -quiet

check: test build-mac build-ios

UI_SIM ?= platform=iOS Simulator,OS=26.5,name=iPhone 17 Pro

test-ui-ios: generate
	xcodebuild -workspace Hikki.xcworkspace -scheme Hikki -destination '$(UI_SIM)' -only-testing:HikkiUITests test -quiet

test-ui-mac: generate
	xcodebuild -workspace Hikki.xcworkspace -scheme Hikki -destination 'platform=macOS' -only-testing:HikkiUITests test -quiet
