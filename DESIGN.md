---
name: Hikki
description: A local-first notebook for Mac, iPhone and iPad — Notion's fluency, files you own, one red seal.
colors:
  paper: '#ffffff'
  paper-dark: '#191919'
  ink: '#37352f'
  ink-dark: 'rgba(255, 255, 255, 0.81)'
  ink-subtle: 'rgba(55, 53, 47, 0.65)'
  ink-muted: 'rgba(55, 53, 47, 0.45)'
  ink-placeholder: 'rgba(55, 53, 47, 0.3)'
  wash: 'rgba(55, 53, 47, 0.06)'
  wash-strong: 'rgba(55, 53, 47, 0.1)'
  hairline: 'rgba(55, 53, 47, 0.09)'
  field-line: 'rgba(55, 53, 47, 0.16)'
  card: '#ffffff'
  card-dark: '#252525'
  sidebar-paper: '#f8f8f7'
  sidebar-paper-dark: '#202020'
  sidebar-pill: 'rgba(55, 53, 47, 0.08)'
  sidebar-pill-dark: 'rgba(255, 255, 255, 0.14)'
  selection: 'rgba(28, 28, 28, 0.12)'
  selection-dark: 'rgba(230, 228, 223, 0.2)'
  kurenai-seal: '#cb1b45'
  kurenai-seal-dark: '#cc2049'
  kurenai-ink: '#cb1b45'
  kurenai-ink-dark: '#db617e'
  kurenai-wash: 'rgba(203, 27, 69, 0.16)'
  on-seal: '#ffffff'
  favorite: '#f2b705'
  destructive: '#e03e3e'
  destructive-dark: '#ff7369'
  code-wash: 'rgba(135, 131, 120, 0.15)'
typography:
  title:
    fontFamily: "ui-sans-serif, -apple-system, BlinkMacSystemFont, 'PingFang SC', 'Segoe UI', Helvetica, sans-serif"
    fontSize: '40px'
    fontWeight: 700
    lineHeight: 1.25
    letterSpacing: '-0.01em'
  heading:
    fontFamily: "ui-sans-serif, -apple-system, BlinkMacSystemFont, 'PingFang SC', 'Segoe UI', Helvetica, sans-serif"
    fontSize: '1.875em'
    fontWeight: 600
    lineHeight: 1.3
  body:
    fontFamily: "ui-sans-serif, -apple-system, BlinkMacSystemFont, 'PingFang SC', 'Segoe UI', Helvetica, sans-serif"
    fontSize: '16px'
    fontWeight: 400
    lineHeight: 1.5
  ui:
    fontFamily: "ui-sans-serif, -apple-system, BlinkMacSystemFont, 'PingFang SC', 'Segoe UI', Helvetica, sans-serif"
    fontSize: '13px'
    fontWeight: 400
    lineHeight: 1.4
  label:
    fontFamily: "ui-sans-serif, -apple-system, BlinkMacSystemFont, 'PingFang SC', 'Segoe UI', Helvetica, sans-serif"
    fontSize: '12px'
    fontWeight: 500
    lineHeight: 1.3
  mono:
    fontFamily: "ui-monospace, 'SF Mono', SFMono-Regular, Menlo, monospace"
    fontSize: '85%'
    fontWeight: 400
    lineHeight: 1.5
rounded:
  sm: '4px'
  md: '6px'
  lg: '8px'
  xl: '12px'
  2xl: '16px'
  sheet: '32px'
  full: '9999px'
spacing:
  1: '4px'
  2: '8px'
  3: '12px'
  4: '16px'
  5: '20px'
  6: '24px'
  8: '32px'
  12: '48px'
  24: '96px'
components:
  button-primary:
    backgroundColor: '{colors.kurenai-seal}'
    textColor: '{colors.on-seal}'
    rounded: '{rounded.md}'
    padding: '6px 12px'
    typography: '{typography.ui}'
  button-ghost:
    backgroundColor: 'transparent'
    textColor: '{colors.ink}'
    rounded: '{rounded.md}'
    padding: '6px 10px'
    typography: '{typography.ui}'
  button-ghost-hover:
    backgroundColor: '{colors.wash}'
  toolbar-icon-quiet:
    backgroundColor: 'transparent'
    textColor: '{colors.ink-subtle}'
    rounded: '{rounded.lg}'
    size: '44px'
  toolbar-icon-quiet-on:
    textColor: '{colors.kurenai-ink}'
  menu-row:
    backgroundColor: 'transparent'
    textColor: '{colors.ink}'
    rounded: '{rounded.md}'
    height: '31px'
    padding: '0 8px'
    typography: '{typography.ui}'
  menu-row-selected:
    backgroundColor: '{colors.wash}'
  input:
    backgroundColor: '{colors.paper}'
    textColor: '{colors.ink}'
    rounded: '{rounded.md}'
    padding: '6px 10px'
    typography: '{typography.ui}'
  chip:
    backgroundColor: '{colors.wash}'
    textColor: '{colors.ink}'
    rounded: '{rounded.full}'
    padding: '4px 10px'
    typography: '{typography.label}'
  card:
    backgroundColor: '{colors.card}'
    textColor: '{colors.ink}'
    rounded: '{rounded.xl}'
    padding: '16px'
---

# Design System: Hikki

## Overview

**Creative North Star: "The Study Desk"**

Hikki looks like a quiet desk someone studies at: white paper, one warm ink, and a single red seal. Everything a
person wrote sits on the paper in a system face set generously (16 px, 1.5); everything the app says around it is
smaller, quieter and drawn from the same ink at a lower strength — washes, hairlines, muted labels are all the ink
`#37352F` at an alpha, never a second grey. The seal, Kurenai (紅, nipponcolors' traditional red), is the only
chromatic voice: it marks _the one thing_ on a screen — the primary action, the tool that is open, the tile that is
current — and nothing else. The density is Notion's (31 px rows, 13 px UI text, 6 px corners on controls); the
materials are the platform's (Liquid Glass bars and sheets on Apple's own navigation), so brand lives in the ink, the
seal and the typography, not in chrome.

The app is one system on two renderers: SwiftUI shells (`HikkiUI/`, `Theme.*`) and a web editor inside them
(Tailwind over the same `design/tokens.json`). The marketing site (`apps/website/`) is deliberately another world — a
Mondrian canvas with the same red — and is not described here.

Confirmed anti-reference: none of the "AI product" idiom — no gradient text, no violet-to-blue glows, no glass as
decoration, no neon. Glass appears only where the platform puts it (bars, sheets), motion only where something
appears, leaves or reacts.

**Key Characteristics:**

- One ink at many strengths; one seal, used once per screen.
- The platform's own chrome, our tokens inside it; the same tokens on both renderers.
- Reading first: the page's words are the largest, most contrasted thing on any screen.
- Quiet motion from one pair of curves; nothing loops but the AI-at-work shimmer.
- CJK and Latin as equals: PingFang in the stack, CJK counted per character, readings (ruby) as first-class text.

## Colors

A warm ink on white paper, with one red seal; dark mode is the same desk at night, not an inversion.

### Primary

- **Kurenai Seal** (#CB1B45 / dark #CC2049): the one chromatic element — the primary action button, the tone of an
  "on" glyph, the current tile's outline, the favorite star's outline. Text on it is **On Seal** (#FFFFFF).
- **Kurenai Ink** (#CB1B45 / dark #DB617E): the seal as text or a glyph on paper (≥ 4.6:1); **Kurenai Wash**
  (seal at 16 % / 30 %) is its selection fill in the few places a tinted fill is wanted (the Mac toolbar's marked
  buttons). The tone is one of seven (`ColorTone`); the system is built so any of them can take the seal's place.

### Neutral

- **Paper** (#FFFFFF / #191919): the page and every surface it reads on.
- **Card** (#FFFFFF / #252525): popovers, link cards, dark surfaces that must lift off the night paper.
- **Sidebar Paper** (#F8F8F7 / #202020): the sidebar, a shade off the page so the two read as desk and sheet.
- **Ink** (#37352F / white 81 %): words. **Ink Subtle** (65 %): secondary words and quiet glyphs. **Ink Muted**
  (45 %): labels, hints, timestamps. **Ink Placeholder** (30 %): placeholders only.
- **Wash** (ink 6 %) and **Wash Strong** (10 %): hover, the selected row, the muted field; **Sidebar Pill** (8 % /
  white 14 %): the selected sidebar row.
- **Hairline** (ink 9 %): borders; **Field Line** (16 %): inputs at rest.
- **Selection** (#1C1C1C 12 % / #E6E4DF 20 %): text selection on the page, painted by the page itself.
- **Favorite** (#F2B705), **Destructive** (#E03E3E / #FF7369), **Code Wash** (#878378 15 %): the three named
  exceptions, each with one job.

### Named Rules

**The One Seal Rule.** Kurenai marks at most one thing per screen, and that thing is an action or a state — never
decoration, never a heading, never an illustration.

**The Ink Wash Rule.** Every grey is the ink at an alpha. There is no second grey; a tint that isn't the ink or the
seal doesn't exist in the system (the palette inks and washes are the page's own content colours, chosen by the
writer, not the UI's).

## Typography

**Display Font:** the system face (SF / PingFang SC on Apple platforms; the stack falls to Segoe UI, Helvetica)
**Body Font:** the same stack
**Label/Mono Font:** ui-monospace / SF Mono for code and references

**Character:** one family, set in two registers — the page's words large and relaxed, the app's words small and
exact. Weight carries hierarchy; size steps are Tailwind's (so shadcn's components fit) plus 13 px for UI text and
11 px for the smallest labels.

### Hierarchy

- **Title** (700, 40 px — 30 px on a phone, 1.25, −0.01em): the page's title, once.
- **Heading** (600, 1.875em / 1.5em / 1.25em / 1.1em relative to the body): H1–H4 inside the page.
- **Body** (400, 16 px, 1.5): the page's words; the column is 708 px wide (≈ 70 characters). On iOS the body and the
  title follow Dynamic Type (`--hk-text-scale`, 0.85–2×); the UI around them keeps its size.
- **UI** (400, 13 px, 1.4): menus, rows, sheets, settings — Notion's UI size.
- **Label** (500, 12 px; 11 px at the smallest): section titles, chips, timestamps, in Ink Muted.
- **Mono** (85 % of the surrounding size): inline code and code blocks, coloured by the `syntax-*` tokens (Xcode's
  Default Light/Dark).

### Named Rules

**The Reading Rule.** On any screen the page's words are the largest, highest-contrast text; the app's words never
compete. Nothing in the UI goes above 20 px except a title.

**The Scaled Rule.** On iOS every native size scales with the system text size (`Font.hk`), and the page's words
with it; a fixed point size is a bug.

## Layout

A single column of words on paper, with chrome that stays out of its way. The page column is 708 px, centred, with
96 px side margins on wide windows and the phone's 24 px on a narrow one; the sidebar is 240–400 px (280 ideal); the
inspector 280–560 px. Spacing is a 4 px scale (`Spacing.s1` … `s24`); rows are 31 px; icon buttons 28 px; toolbar
buttons 40 × 36 with 44 × 44 touch targets on the phone's keyboard bar. The phone is its own layout chosen by window
width (compact = phone, regular = iPad), never by device; the Mac and iPad put the page under a glass toolbar, the
phone under glass buttons with the cover bleeding to the status bar. Split view is two equal panes meeting at a
hairline. Tight groups, generous separation: 8 px inside a group, 16–24 px between groups, more above a heading
than below it.

## Elevation & Depth

Flat by default. The page, the sidebar and the panels are flat surfaces told apart by paper shade and hairlines,
not shadows. Depth appears only on what floats over the page: popovers, menus and link previews carry the one
popover shadow; bars and sheets take the platform's material (Liquid Glass) and no shadow of ours.

### Shadow Vocabulary

- **Popover** (`box-shadow: 0 0 0 1px rgba(15,15,15,0.05), 0 3px 6px rgba(15,15,15,0.1), 0 9px 24px rgba(15,15,15,0.2)`;
  dark: hairline white 9 %, 0 3px 6px black 20 %, 0 9px 24px black 40 %): anything that floats over the page.

### Named Rules

**The Flat Page Rule.** Surfaces are flat at rest; a shadow means "this floats and will go away". Cards in the page
(link previews, embeds) take a hairline and a 12 px corner, never a shadow.

## Shapes

Small, consistent corners: 6 px on controls and menu rows (`md`), 8 px on toolbar pills and tiles (`lg`), 12 px on
cards and panels (`xl`), 16 px on sheets' inner groups (`2xl`), 32 px on sheet corners (`sheet`), full capsules for
chips, the floating bar and the keyboard bar. Borders are one hairline of ink at 9 %; a focused field's ring is the
ink at 30 %. No pills on anything that isn't a small control; no nested cards.

## Components

Native components (`HikkiUI`) and the web's shadcn components (`base-vega`, restyled) draw the same shapes from the
same tokens; a control looks the same on both renderers.

### Buttons

- **Shape:** 6 px corners (`Radius.md`); capsules only for the floating bar's round buttons.
- **Primary:** Kurenai Seal fill, On Seal text, 13 px medium; one per screen (the pencil on the phone, Send, Save).
- **Ghost (MenuRow, toolbar text buttons):** no fill, Ink text; hover is Wash, press scales to 97 %; menus and lists
  mark the selected row with one gliding Wash surface (`GlidingHighlight`).
- **Toolbar icon, filled (Mac toolbar):** 40 × 36, "on" = Kurenai Wash box with Kurenai Ink glyph.
- **Toolbar icon, quiet (phone keyboard bar):** 44 × 44, Ink Subtle glyph; "on" = the glyph alone in Kurenai Ink, no
  box.
- **Destructive:** Destructive text in a ghost button, never a red fill.

### Chips

- **Style:** Wash fill, full capsule, 12 px medium Ink; selected = Wash Strong (filter chips, AI context chips).

### Cards / Containers

- **Corner Style:** 12 px (`xl`).
- **Background:** Card; **Border:** one hairline; **Shadow:** none (The Flat Page Rule); **Padding:** 16 px.
- Link previews and embeds sit in one such card; a page cover is edge to edge with no frame.

### Inputs / Fields

- **Style:** Paper fill, Field Line border, 6 px corners, 13 px (16 px on touch screens, so iOS doesn't zoom).
- **Focus:** ring of ink at 30 %; no glow.
- **Error:** Destructive text under the field; the field's line turns Destructive.

### Navigation

- Platform navigation only: `NavigationSplitView`, the window toolbar's glass groups, tabs in the toolbar on
  Mac/iPad, a side drawer and a floating bar on the phone. The sidebar is our own rows: 31 px, 13 px text, the
  selected row a Sidebar Pill, the page's own emoji as its icon.

### The Keyboard Bar (signature)

One Liquid Glass capsule over the phone's keyboard: quiet 44 pt tools, the open tool's glyph in the seal, panels in
the keyboard's place at the keyboard's height; AI, link and comment as a glass field over the keyboard. Notion's bar,
in the desk's ink.

### Toasts

Card surface, popover shadow, 14 px medium message in Ink, a code reference in Mono, one ghost action and a close;
warning and error only differ by the glyph's tint.

## Do's and Don'ts

### Do:

- **Do** take every colour, size, radius and duration from `design/tokens.json` (`Theme.*`, `Spacing.*`,
  `Radius.*`, Tailwind classes); `make lint-design` refuses literals.
- **Do** mark exactly one thing per screen with Kurenai, and make it an action or a state.
- **Do** build greys as the ink at an alpha (6 / 8 / 9 / 10 / 16 / 30 / 45 / 65 %) — pick the strength, not a hue.
- **Do** use the platform's component for anything the platform has (sheets, menus, switches, pickers, Liquid Glass
  bars) and the shadcn component on the web; never a bare `<button>` or `<input>`.
- **Do** move everything with the one pair of curves (`ease-out` 200 ms in, 150 ms out; `hk-pop`, `Motion.easeOut()`);
  loop only the AI shimmer (1400 ms), and honour Reduce Motion.
- **Do** draw icons from one list (`design/icons.json`): SF Symbols natively and inside the page on iOS, Phosphor
  (regular, stroke +4) on the Mac's page — one weight, baseline-aligned.
- **Do** keep the page's words at 16 px / 1.5 on a 708 px column and let them scale with the reader's text size.

### Don't:

- **Don't** add gradients, gradient text, coloured glows, glass as decoration, or a second accent — the committed
  anti-reference is the "AI product" idiom.
- **Don't** put a shadow on anything that doesn't float, or a coloured left border on cards, callouts or alerts.
- **Don't** introduce a grey that isn't the ink, a radius that isn't on the scale, or a duration of its own.
- **Don't** let UI text grow past 20 px, or use the title size anywhere but the page's title.
- **Don't** decorate with emoji or Unicode glyphs where an icon belongs (the page's own emoji icons are content, not
  UI).
- **Don't** reintroduce a custom title bar or custom navigation; the window chrome is the system's.
