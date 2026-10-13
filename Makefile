# swiftly's toolchain shadows Xcode's and breaks SwiftPM manifest compilation under Tuist.
export PATH := $(shell echo "$$PATH" | tr ':' '\n' | grep -v swiftly | paste -sd: -)

IOS_SIM ?= generic/platform=iOS Simulator

.PHONY: bootstrap test-bff tokens icons lint lint-design lint-docs lint-l10n fmt fmt-check editor generate test test-web test-core test-core-ios build-mac build-ios check

bootstrap:
	bun install
	tuist install

# Design tokens: edit design/tokens.json, then regenerate Swift + the Tailwind theme.
tokens:
	node scripts/gen-tokens.mjs

# Phosphor icons for the native app: edit design/icons.json, then regenerate the asset catalog + Icon enum.
icons:
	node scripts/gen-icons.mjs

# Keyboard shortcuts for both sides: edit design/shortcuts.json, then regenerate the Swift enum + TS table.
shortcuts:
	node scripts/gen-shortcuts.mjs

# Fails on stale generated tokens or on literal colors/fonts/spacing in view code.
lint-design:
	node scripts/gen-tokens.mjs --check
	node scripts/gen-icons.mjs --check
	node scripts/gen-shortcuts.mjs --check
	scripts/lint-design.sh

SWIFT_DIRS := Hikki HikkiCore HikkiUI HikkiUITests Project.swift Tuist.swift

lint:
	bunx oxlint
	xcrun swift-format lint --strict -r -p $(SWIFT_DIRS)

fmt:
	bunx oxfmt
	xcrun swift-format format -i -r -p $(SWIFT_DIRS)

fmt-check:
	bunx oxfmt --check
	xcrun swift-format lint --strict -r -p $(SWIFT_DIRS)

# Every UI string is a key with en + zh-Hans translations (native String Catalog, web locales).
lint-l10n:
	bun scripts/l10n-audit.mjs

# CLAUDE.md must only reference paths that exist.
lint-docs:
	bun scripts/check-claude-md.mjs

editor:
	cd editor && bun run build

generate: editor
	tuist generate --no-open

test-web:
	cd editor && bun run typecheck && bun run test

test-bff:
	cd bff && bun run typecheck && bun run test

# `tuist test` regenerates a test-focused workspace; regenerate the full one afterwards so the
# Hikki scheme exists again for builds and UI tests.
test-core:
	tuist test HikkiCore --platform macos
	tuist generate --no-open

test-core-ios:
	tuist test HikkiCore --platform ios

test: lint fmt-check lint-design lint-docs lint-l10n test-web test-bff test-core

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
