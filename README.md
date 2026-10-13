<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="design/logo/lockup-hi-star-dark.svg">
    <img src="design/logo/lockup-hi-star-light.svg" alt="hikki" height="56">
  </picture>
</p>

# Hikki

Notion-like editor for macOS, iPhone and iPad: SwiftUI shell + Tiptap editor in a WKWebView.

```
Hikki/            SwiftUI app (shell, WKWebView host, keyboard toolbar, menus)
HikkiCore/        Framework: SQLite store (GRDB), bridge protocol, logging, crash collection
HikkiUI/          Framework: reusable SwiftUI components (no app state; plain values + closures)
HikkiUITests/     XCUITest end-to-end flows
editor/           Tiptap 3 web editor (vite → Hikki/Resources/Editor)
```

## Commands

|                    |                                                                                       |
| ------------------ | ------------------------------------------------------------------------------------- |
| `make bootstrap`   | install web deps + Swift packages                                                     |
| `make generate`    | build the editor bundle and generate the Xcode workspace                              |
| `make test`        | web unit tests (vitest) + HikkiCore tests (Swift Testing, macOS)                      |
| `make test-ui-ios` | end-to-end UI test on the iOS simulator                                               |
| `make test-ui-mac` | end-to-end UI test on macOS (takes over the screen — don't use the Mac while it runs) |
| `make check`       | tests + macOS and iOS builds                                                          |

`cd editor && pnpm dev` runs the editor alone in a browser with a console-logging bridge.

## Components

Reusable UI goes in `HikkiUI` rather than the app target: one component per file, a `#Preview` in each, and an
entry in the DEBUG gallery (`Hikki/Sources/ComponentGallery.swift`, launch with `-HikkiGallery`).

Web editor UI (`editor/src`) follows the same idea: `ui/` holds generic React pieces (`CommandList`,
`FloatingLayer`) reused by every popup; `blocks.ts` is the single block-type catalog (slash menu today,
"turn into"/"+" later); `extensions/` holds Tiptap extensions (title, slash command, block handle).

## Observability

- Logs: `Log.info/warn/error` → unified logging (`log stream --predicate 'subsystem == "app.hikki"'`) and
  rotating JSONL at `Application Support/Hikki/logs/`. Web console warnings/errors and uncaught JS errors are
  forwarded over the bridge into the same log (category `web`).
- Crashes: MetricKit diagnostic payloads persisted to `Application Support/Hikki/diagnostics/`; uncaught
  ObjC exceptions logged synchronously. WebContent process crashes are logged and the editor reloads itself.
- Sidebar ⋯ → Export Logs shares logs + diagnostics.
- Debug builds: the editor web view is inspectable from Safari's Develop menu.

## Notes

- Tuist must use Xcode's Swift, not swiftly's; the Makefile strips swiftly from `PATH`.
- `HIKKI_DATA_DIR` overrides the data directory (UI tests use a fresh one per run).
- Bridge protocol lives in `editor/src/protocol.ts` and `HikkiCore/Sources/Bridge/BridgeMessage.swift`;
  bump `PROTOCOL_VERSION` on both sides together.
