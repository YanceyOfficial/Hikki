# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

(The app is one SwiftUI code base for macOS, iPhone and iPad; the page editor inside it is a web view. The marketing
site is its own `web` surface: `apps/website/PRODUCT.md`.)

## Users

Confirmed 2026-10-22: individuals keeping their own notes and study material. The developer is the first user:
writes on the Mac, reads and edits on iPhone and iPad; keeps notes, language study pages (Japanese grammar with
readings, Chinese), reference material; works offline, with the data in a folder of their own (iCloud Drive).

## Product Purpose

A Notion-like notebook that is local-first. Pages are files in the user's own folder (one JSON file per page; SQLite
only a rebuildable cache), on every Apple device, working offline. Success: the editor is as capable as Notion's for
daily notes and study, while every page stays a file the user owns.

## Positioning

Confirmed 2026-10-22, two claims a neighbouring product can't truthfully make:

1. **Local-first; the files are yours.** A folder of page files the user can open, move and back up — not a hosted
   database. Sync is the folder (iCloud Drive today; CloudKit planned, `docs/cloudkit-sync.md`).
2. **AI with the user's own keys.** OpenAI and Anthropic called directly, keys in the Keychain, nothing routed
   through a server of ours; an AI edit is shown in the page as a review and lands only when the user approves it.

Capabilities, not the positioning: the breadth of the block editor (drawings, embeds, comments, history), the
Japanese/Chinese study helpers (ruby readings, pinyin search, CJK word counts).

## Operating Context

- Mac: the writing desk — tabs, split view, inspector (outline, comments, AI), keyboard shortcuts. iPhone: reading
  and quick edits — a floating bar, the keyboard bar, sheets. iPad: between the two, by window width.
- The workspace is a folder: `pages/`, `assets/`, `history/`, `comments/`, `ai/`, `drawings/`, `workspace.json`.
- The user writes Chinese, Japanese and English in one page; the app ships in English (source) and zh-Hans.
- Notion's Mac and iOS apps are the reference the user compares every screen with.

## Capabilities and Constraints

- Shell: SwiftUI on macOS 26 / iOS 26 (Liquid Glass, system navigation and toolbars). Editor: Tiptap 3 (React 19,
  Tailwind v4, shadcn `base-vega`) in one long-lived `WKWebView` per window, bridged to Swift.
- One design-token source for both sides (`design/tokens.json` → HikkiUI `Theme` / the editor's Tailwind theme);
  one colour tone (Kurenai); SF Symbols natively, Phosphor icons on the web, one icon list (`design/icons.json`).
- Every user-facing string is a localization key; every failure has a code and reaches the user as a toast; logs
  never contain page content.
- Undecided: shared workspaces and live collaboration (later, CloudKit `CKShare`); an App Store listing (none yet).

## Brand Commitments

- Name **Hikki**. Mark **Hi✦** (an h with a sparkle i-dot), wordmark in Outfit, accent **Kurenai #D7003A**
  (`design/icon/`, `design/logo/`). Binding.
- Copy: plain, short, the product's own words; controls name their action. (Observed, not yet a stated rule.)

## Evidence on Hand

- Website screenshots: `apps/website/public/shots/` (light and dark twins), made from the app.
- A demo workspace the app can seed (`HIKKI_DEMO_PAGES`).
- No testimonials, customers, press or store listing exist (`APP_STORE_URL` is empty: "Coming to the App Store").
  Future work must not fabricate any.

## Product Principles

1. The file is the truth; the app is a view of it.
2. Native where the user touches the system (windows, keyboard, sheets, menus); the web where the page is.
3. Notion's fluency without Notion's lock-in.
4. AI proposes; the user disposes.
5. One token source, both platforms, every screen.

## Accessibility & Inclusion

No product-specific requirement established yet. Everyday needs: CJK text set well alongside Latin, Dynamic Type on
iOS, both appearances first-class.
