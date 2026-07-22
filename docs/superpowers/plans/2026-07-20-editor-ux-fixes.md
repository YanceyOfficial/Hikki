# Editor & Window Chrome UX Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the macOS window-drag/traffic-light regression, re-skin BlockNote to look like a native part of our soft design system (not default shadcn/BlockNote), add code highlighting, swap the emoji picker to a proper headless library, add a table of contents and a real comment feature, and fix the remaining layout/positioning bugs the user found reviewing Phase 2.

**Architecture:** BlockNote's `@blocknote/shadcn` view accepts a `shadCNComponents` override (point it at our own `src/components/ui/*`) and a `theme` prop (feed it from a newly-added `next-themes` provider, pulled forward from Phase 4). BlockNote's own `--bn-colors-*` CSS variables are retargeted to our design tokens for the parts `shadCNComponents` doesn't cover. Comments use BlockNote's open-source `ThreadStore` abstraction with our own vault-backed implementation — threads persist as a new opaque `threads` field on `Doc`/`Document`, flowing through the exact same autosave path as `blocks` already does.

**Tech Stack:** next-themes, shiki, frimousse, react-fluid-toc (user-authored), BlockNote's built-in Comments extension.

**Spec:** `docs/superpowers/specs/2026-07-18-hikki-design.md` §14a (amendments from this review), §8 (theming direction), §4–§5.

## Global Constraints

- Package manager: pnpm. Rust deps via `cargo add` from `src-tauri/`.
- shadcn/ui first — never hand-roll a primitive; this plan's whole point is routing BlockNote's UI through our own primitives, not the reverse.
- Import aliases: `#components/*`, `#lib/*`, `#lib/backend/*`, `#hooks/*`, `#pages/*`.
- `data-testid` on every new interactive element.
- TDD where behavior is testable under Vitest/cargo; visual-only changes get a screenshot instead (see Task 3).
- Conventional commits ending with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- Husky runs oxlint/oxfmt on commit; never `--no-verify`.
- Suites at start: 43 vitest, 45 cargo, 7 e2e — all green; keep them green.
- Window-native behavior (drag, traffic lights, transparency) **cannot be verified by any automated test** in this environment — every task touching it must end with an explicit "please verify manually" note, not a false claim of having tested it.

---

### Task 1: Fix macOS window transparency (drag region + traffic-light conflict)

**Files:**

- Modify: `src-tauri/tauri.conf.json`

**Interfaces:** none — config only.

**Root cause:** `tauri.conf.json` still carries the untouched Tauri template default `"transparent": true`, combined with `"titleBarStyle": "Overlay"` and `"decorations": true`. macOS window transparency changes how the compositor hit-tests mouse events against the webview and is a well-known source of `data-tauri-drag-region` failing to register and of the native traffic-light cluster rendering/behaving oddly over custom content. We don't want or need a see-through window — our own CSS (`bg-background` on `<body>`/`<header>`) already paints full opaque chrome — so transparency was serving no purpose and is the most likely single cause of both symptoms the user reported.

- [ ] **Step 1: Read the current config**

Read `src-tauri/tauri.conf.json` and confirm the `app.windows[0]` object currently has `"transparent": true` alongside `"decorations": true`, `"hiddenTitle": true`, `"titleBarStyle": "Overlay"`, `"trafficLightPosition": { "x": 16, "y": 16 }`.

- [ ] **Step 2: Disable window transparency**

Change `"transparent": true` to `"transparent": false`. Leave every other window property (`decorations`, `hiddenTitle`, `titleBarStyle`, `trafficLightPosition`, `width`, `height`) untouched.

- [ ] **Step 3: Verify config validity**

Run: `cargo check --manifest-path src-tauri/Cargo.toml`
Expected: clean (this parses `tauri.conf.json` via `generate_context!()`; a malformed JSON edit would fail here).

- [ ] **Step 4: Record the manual verification the user must do**

This cannot be tested by any subagent — no automated tool in this environment can drive a live native macOS window. Write to your report, verbatim, this checklist for the controller to relay to the human:

```
Manual check required (native macOS window, cannot be automated):
1. `pnpm tauri dev` — does clicking and dragging an empty area of the titlebar
   (not the sidebar-toggle button, not the "Hikki" text) move the window?
2. Do the traffic-light buttons (red/yellow/green) render cleanly, without
   overlapping or visually fighting the sidebar-toggle icon or "Hikki" text?
3. Does double-clicking the empty titlebar area maximize/restore the window
   (standard macOS titlebar behavior)?
If any of these still fail after this fix, the header's own layout (title-bar.tsx,
use-traffic-light-inset.ts) needs a second look — report back with specifics.
```

- [ ] **Step 5: Commit**

```bash
git add src-tauri/tauri.conf.json
git commit -m "fix: disable window transparency to restore drag region and traffic lights

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Wire up next-themes (pulled forward from Phase 4)

**Files:**

- Create: `src/components/theme-provider.tsx`, `src/components/theme-provider.test.tsx`
- Modify: `src/main.tsx` (wrap router in `ThemeProvider`), `src/components/title-bar.tsx` (add a light/dark toggle button), `package.json` (add `next-themes`)

**Interfaces:**

- Produces: `ThemeProvider` (wraps `next-themes`' `ThemeProvider`, `attribute="class"`, `defaultTheme="system"`, `enableSystem`, `storageKey="hikki-theme"`, `disableTransitionOnChange`); re-export `useTheme` from `'next-themes'` directly (consumers import it from there, matching the exodus precedent already agreed in spec §8). A `NativeThemeBridge` (mounted inside `ThemeProvider`, renders nothing) keeps the native macOS window chrome in sync via `getCurrentWindow().setTheme(...)`.
- This is intentionally minimal: no theme-preset gallery, no radius picker (Phase 4 Appearance settings owns those) — just light/dark/system switching, needed now so BlockNote's `theme` prop (Task 3) and the whole soft-palette work can actually be checked in dark mode.

- [ ] **Step 1: Add the dependency**

```bash
pnpm add next-themes
```

- [ ] **Step 2: Write the failing test**

Create `src/components/theme-provider.test.tsx`:

```tsx
import { render, screen } from '@testing-library/react'
import { useTheme } from 'next-themes'

import { ThemeProvider } from '#components/theme-provider'

function ThemeConsumer() {
  const { theme, setTheme } = useTheme()
  return (
    <div>
      <span data-testid="current-theme">{theme}</span>
      <button data-testid="go-dark" onClick={() => setTheme('dark')}>
        dark
      </button>
    </div>
  )
}

test('defaults to system and can switch to dark', async () => {
  render(
    <ThemeProvider>
      <ThemeConsumer />
    </ThemeProvider>
  )
  expect(await screen.findByTestId('current-theme')).toHaveTextContent('system')
})
```

- [ ] **Step 3: Run test to verify it fails**

Run: `pnpm test`
Expected: FAIL — `#components/theme-provider` not found.

- [ ] **Step 4: Implement**

`src/components/theme-provider.tsx`:

```tsx
import { ThemeProvider as NextThemesProvider, useTheme } from 'next-themes'
import type { ComponentProps } from 'react'
import { useEffect } from 'react'

/**
 * Bridges next-themes' resolved theme back into the native macOS window
 * chrome (traffic lights, menu bar rendering) so it matches the in-app
 * theme, mirroring the exodus project's Electron nativeTheme bridge.
 */
function NativeThemeBridge() {
  const { resolvedTheme } = useTheme()

  useEffect(() => {
    if (typeof window === 'undefined' || !('__TAURI_INTERNALS__' in window))
      return
    if (resolvedTheme !== 'light' && resolvedTheme !== 'dark') return
    let cancelled = false
    import('@tauri-apps/api/window').then(({ getCurrentWindow }) => {
      if (cancelled) return
      getCurrentWindow()
        .setTheme(resolvedTheme)
        .catch(() => {})
    })
    return () => {
      cancelled = true
    }
  }, [resolvedTheme])

  return null
}

export function ThemeProvider({
  children,
  ...props
}: ComponentProps<typeof NextThemesProvider>) {
  return (
    <NextThemesProvider
      attribute="class"
      defaultTheme="system"
      enableSystem
      storageKey="hikki-theme"
      disableTransitionOnChange
      {...props}
    >
      <NativeThemeBridge />
      {children}
    </NextThemesProvider>
  )
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `pnpm test`
Expected: PASS.

- [ ] **Step 6: Wrap the app and add a toggle**

In `src/main.tsx`, wrap `<RouterProvider router={router} />` with `<ThemeProvider>` (import from `#components/theme-provider`).

In `src/components/title-bar.tsx`, add a theme toggle button before the closing `</header>`:

```tsx
import { Moon, Sun } from 'lucide-react'
import { useTheme } from 'next-themes'
// ...existing imports...

export function TitleBar() {
  const inset = useTrafficLightInset()
  const { resolvedTheme, setTheme } = useTheme()
  return (
    <header /* ...unchanged... */>
      {/* ...existing children... */}
      <div className="flex-1" />
      <Button
        variant="ghost"
        size="icon"
        className="size-7"
        data-testid="theme-toggle"
        onClick={() => setTheme(resolvedTheme === 'dark' ? 'light' : 'dark')}
      >
        {resolvedTheme === 'dark' ? (
          <Sun className="size-4" />
        ) : (
          <Moon className="size-4" />
        )}
        <span className="sr-only">Toggle theme</span>
      </Button>
    </header>
  )
}
```

Import `Button` from `#components/ui/button`. Keep the `data-tauri-drag-region` attributes on the header and the "Hikki" span exactly as they are — the toggle button is a normal interactive element and must NOT have the drag-region attribute (buttons need to stay clickable, per Task 1's fix).

Update `src/components/title-bar.test.tsx`'s existing tests if the new button changes any assertion about the header's children count or structure (it shouldn't — the existing tests check `data-tauri-drag-region`, absence of the inset class, and the sidebar-toggle testid, none of which the new button touches). Run the suite to confirm.

- [ ] **Step 7: Run everything**

Run: `pnpm test && pnpm exec tsc --noEmit`
Expected: all green, clean.

- [ ] **Step 8: Commit**

```bash
git add src package.json pnpm-lock.yaml
git commit -m "feat: wire up next-themes with native window-chrome sync

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Soften our own Tooltip/Popover/DropdownMenu (fixes the "diamond" and "ugly popover" complaints)

**Files:**

- Modify: `src/components/ui/tooltip.tsx`, `src/components/ui/popover.tsx`, `src/components/ui/dropdown-menu.tsx`

**Interfaces:** none new — visual only, all existing props/exports unchanged.

**Why this fixes items 5 and 15 in one place:** `@blocknote/shadcn`'s `BlockNoteView` accepts a `shadCNComponents` prop (verified against `node_modules/@blocknote/shadcn/types/src/ShadCNComponentsContext.d.ts`) letting it render its internal formatting toolbar, tooltips, and menus using **our own** `Tooltip`/`Popover`/`DropdownMenu`/`Button` components instead of BlockNote's bundled look-alikes (wired in Task 6). That means whatever we do here to our own components automatically becomes BlockNote's UI too — including removing the visible "diamond" (our `TooltipContent`'s `TooltipPrimitive.Arrow`, currently a `rotate-45` square, which is what the user is seeing when hovering a BlockNote toolbar button once Task 6 wires the override).

Reference: the Notion screenshots in the project root show floating panels with **no visible arrow/pointer at all** — soft rounded rectangles, generous padding, gentle shadow. Match that.

- [ ] **Step 1: Read the current components**

Read `src/components/ui/tooltip.tsx`, `src/components/ui/popover.tsx`, `src/components/ui/dropdown-menu.tsx` in full before editing — preserve every existing prop, export, and `data-slot` attribute; this task only touches className strings (and one JSX removal in the tooltip).

- [ ] **Step 2: Remove the tooltip arrow, soften the tooltip panel**

In `src/components/ui/tooltip.tsx`, inside `TooltipContent`, delete the `<TooltipPrimitive.Arrow ... />` element entirely (no pointer, matching the Notion reference). Update the `TooltipPrimitive.Popup` className: keep every existing data-state/data-side animation class untouched, but change:

- `bg-foreground` → `bg-popover border border-border/60`
- `text-background` → `text-popover-foreground`
- `rounded-md` → `rounded-lg`
- add `shadow-lg` (soft diffuse shadow, not the harsh default)

- [ ] **Step 3: Soften Popover**

In `src/components/ui/popover.tsx`, find `PopoverContent`'s className (or equivalent). Ensure it has: `rounded-lg` (or `rounded-xl` if currently smaller), `border border-border/60` (not a harsher border color), `shadow-lg`, and padding of at least `p-2` for menu-like popovers (check current value — increase if less). Do not change structural props (align, side, sideOffset) or the base-ui primitive wiring.

- [ ] **Step 4: Soften DropdownMenu**

In `src/components/ui/dropdown-menu.tsx`, apply the same treatment to `DropdownMenuContent`: `rounded-lg`, `border-border/60`, `shadow-lg`. Check `DropdownMenuItem`'s hover/focus state class — if it's a harsh solid `accent` background, consider `focus:bg-accent/70` for a gentler highlight; only change this if it's a simple className edit, don't restructure the component.

- [ ] **Step 5: Verify nothing broke**

Run: `pnpm test && pnpm exec tsc --noEmit`
Expected: all green (this is a visual-only change; no test asserts on these exact classNames — if one does, e.g. a snapshot test, update it to match, don't revert the design change).

- [ ] **Step 6: Screenshot for the record**

With the dev server running (`pnpm dev`, or reuse one already listening on port 1420), capture a document page showing a tooltip and an open popover:

```bash
pnpm exec playwright screenshot --viewport-size=1280,800 "http://localhost:1420/#/doc/<some-id>" /private/tmp/claude-501/-Users-yanceyleo-Code-hikki/c8cff3e3-aff5-4792-9cd4-e9d3b4cfde62/scratchpad/ux-fixes-popovers.png
```

(Create a document first via the UI or `backend.createDocument` if scripting; the exact doc id doesn't matter, just show the app with a popover open if feasible — e.g. the page icon picker.) Note the screenshot path in your report.

- [ ] **Step 7: Commit**

```bash
git add src
git commit -m "style: remove tooltip arrow and soften popover/menu chrome

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Re-skin BlockNote — shadCNComponents, theme prop, editor background, spacing, no-scrollbar

**Files:**

- Modify: `src/components/editor.tsx`, `src/assets/globals.css`, `src/components/app-shell.tsx`

**Interfaces:**

- Consumes: `useTheme` from `next-themes` (Task 2), `ThemeProvider` already wrapping the app.
- Produces: `Editor` now renders with `theme={resolvedTheme === 'dark' ? 'dark' : 'light'}` and `shadCNComponents` pointing at our own UI components; BlockNote's CSS-variable layer under `.bn-root` is retargeted to our design tokens.

- [ ] **Step 1: Wire `theme` and `shadCNComponents` into the editor**

**Important:** `src/components/editor.tsx` already has a `schema: BlockNoteSchema.create().extend({ blockSpecs: { codeBlock: createCodeBlockSpec({...}) } })` config wired in ahead of this task (early code-highlighting work, further overhauled by Task 6) — **merge** the `theme`/`shadCNComponents`/`onChange` additions below into the existing file; do not paste over it wholesale and delete the `schema` config. The snippet shows the target shape of the non-`codeBlock` parts of the file.

```tsx
import '@blocknote/core/fonts/inter.css'
import '@blocknote/shadcn/style.css'

import type { Block } from '@blocknote/core'
import { useCreateBlockNote } from '@blocknote/react'
import { BlockNoteView } from '@blocknote/shadcn'
import { useTheme } from 'next-themes'

import { Button } from '#components/ui/button'
import {
  DropdownMenu,
  DropdownMenuCheckboxItem,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuSub,
  DropdownMenuSubContent,
  DropdownMenuSubTrigger,
  DropdownMenuTrigger
} from '#components/ui/dropdown-menu'
import { Popover, PopoverContent, PopoverTrigger } from '#components/ui/popover'
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger
} from '#components/ui/tooltip'
import { backend } from '#lib/backend/index'

interface EditorProps {
  docId: string
  initialBlocks: unknown[]
  onBlocksChange: (blocks: unknown[]) => void
}

export function Editor({ docId, initialBlocks, onBlocksChange }: EditorProps) {
  const { resolvedTheme } = useTheme()
  const editor = useCreateBlockNote(
    {
      initialContent:
        initialBlocks.length > 0 ? (initialBlocks as Block[]) : undefined,
      uploadFile: async (file: File) =>
        (await backend.importAsset(docId, file)).url
    },
    [docId]
  )
  return (
    <div data-testid="editor" className="mt-4">
      <BlockNoteView
        editor={editor}
        theme={resolvedTheme === 'dark' ? 'dark' : 'light'}
        onChange={() => onBlocksChange(editor.document)}
        shadCNComponents={{
          Button: { Button },
          Tooltip: { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger },
          Popover: { Popover, PopoverContent, PopoverTrigger },
          DropdownMenu: {
            DropdownMenu,
            DropdownMenuCheckboxItem,
            DropdownMenuContent,
            DropdownMenuItem,
            DropdownMenuLabel,
            DropdownMenuSeparator,
            DropdownMenuSub,
            DropdownMenuSubContent,
            DropdownMenuSubTrigger,
            DropdownMenuTrigger
          }
        }}
      />
    </div>
  )
}
```

**Before finalizing:** run `pnpm exec tsc --noEmit`. The `shadCNComponents` prop's type is `Partial<ShadCNComponents>` where each entry must match BlockNote's expected component prop shapes exactly (e.g. its `DropdownMenuCheckboxItem` might require props ours doesn't accept, or vice versa). If tsc reports a mismatch on any single component group, either fix the type gap in our own component (only if trivial and doesn't change its public contract) or drop that one group from the override object (partial overrides are allowed — better to override only what compiles cleanly than to fight an incompatible prop shape). Note any dropped groups in your report.

- [ ] **Step 2: Retarget BlockNote's CSS variables to our design tokens**

Add to `src/assets/globals.css`, after the existing `@layer utilities` block (append a new rule, don't touch `.no-scrollbar`):

```css
/* BlockNote theming: retarget its internal CSS-variable layer (scoped under
   .bn-root) to our own design tokens, so the editor surface, code-block
   chrome, and any BlockNote-internal UI shadCNComponents doesn't cover
   read as part of our soft palette instead of BlockNote's defaults. */
.bn-root {
  --bn-colors-editor-text: var(--foreground);
  --bn-colors-editor-background: var(--background);
  --bn-colors-menu-text: var(--popover-foreground);
  --bn-colors-menu-background: var(--popover);
  --bn-colors-tooltip-text: var(--popover-foreground);
  --bn-colors-tooltip-background: var(--popover);
  --bn-colors-hovered-text: var(--accent-foreground);
  --bn-colors-hovered-background: var(--accent);
  --bn-colors-selected-text: var(--accent-foreground);
  --bn-colors-selected-background: var(--accent);
  --bn-colors-disabled-text: var(--muted-foreground);
  --bn-colors-disabled-background: var(--muted);
  --bn-colors-shadow: var(--border);
  --bn-colors-border: var(--border);
  --bn-colors-side-menu: var(--muted-foreground);
  --bn-border-radius: var(--radius-md);
  --bn-shadow-medium: 0 4px 16px -4px oklch(0 0 0 / 8%);
  --bn-shadow-light: 0 2px 8px -2px oklch(0 0 0 / 6%);
}

/* BlockNote's own gutter (side-menu/drag-handle space) is baked into
   .bn-editor as padding-inline; our page wrapper already owns horizontal
   padding, so reset this to avoid a double-indent when the side menu
   appears/disappears. */
.bn-editor {
  padding-inline: 0 !important;
}

/* More breathing room between blocks than BlockNote's tight 3px default. */
.bn-block-content {
  padding-block: 6px !important;
}
```

Do not touch the hardcoded code-block colors (`background-color:#161616` etc.) — that intentional dark chrome is a deliberate, common editor convention (GitHub/Notion-style) independent of light/dark app theme; leave it as-is unless Task 5's highlighting work needs to touch it.

- [ ] **Step 3: Apply `.no-scrollbar` to the page's scroll container**

In `src/components/app-shell.tsx`, find the `<main data-testid="page-content" ...>` element and add `no-scrollbar` to its className (alongside the existing `overflow-y-auto` etc.) — this is the element that scrolls the whole document page including the editor, so hiding its scrollbar removes the one the user means.

- [ ] **Step 4: Verify**

Run: `pnpm test && pnpm exec tsc --noEmit`
Expected: all green, clean.

- [ ] **Step 5: Commit**

```bash
git add src
git commit -m "feat: re-skin BlockNote with our own components and design tokens

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: Deeper BlockNote chrome reskin (referencing Notion)

**Files:**

- Modify: `src/assets/globals.css`, and any BlockNote-adjacent component created so far (`src/components/editor.tsx`) if a fix requires a prop, not just CSS.

**Interfaces:** none new — visual only.

**Why this task exists:** Task 4's CSS-variable retargeting (`--bn-colors-*`) and `shadCNComponents` override fix the editor's background, menu/tooltip colors, and remove the tooltip arrow — but the user's follow-up review after seeing that land was explicit: BlockNote's own block-level chrome (the drag-handle "⠿" grip, the "+" add-block button, the slash-menu item rows, the selected-block outline) is still built from BlockNote's own hardcoded shapes/spacing (confirmed in its compiled CSS: e.g. `.bn-side-menu` fixed pixel heights, a flat `4px solid #64a0ff` selection outline hardcoded in RGB — not a CSS variable at all) and reads as "生硬" (stiff/raw) next to Notion's much softer treatment. This task goes past color variables into actual per-element overrides.

- [ ] **Step 1: Inspect what Task 4 did and did not fix**

With the dev server running and a document open containing several blocks, hover over a block to reveal the drag-handle and "+" button, open the slash menu, and select a block (to see its selection outline). Compare directly against Notion's own treatment (the reference screenshots were reviewed with the user during planning: soft, low-contrast, generously spaced, no hard-edged blue outline). Note in your report every element that still looks "raw shadcn/BlockNote-default" after Task 4.

- [ ] **Step 2: Override the hardcoded selection outline**

BlockNote's compiled CSS hardcodes `.bn-block-content.ProseMirror-selectednode > *, .ProseMirror-selectednode > .bn-block-content > * { border-radius: 4px; outline: 4px solid #64a0ff; }` — a bright, hard-edged blue outline with no variable indirection. Add an override to `src/assets/globals.css` (near the existing `.bn-root`/`.bn-editor` rules from Task 4) using our own token and something softer than a solid 4px ring:

```css
.bn-block-content.ProseMirror-selectednode > *,
.ProseMirror-selectednode > .bn-block-content > * {
  outline: 2px solid var(--ring) !important;
  outline-offset: 2px;
  border-radius: var(--radius-md) !important;
}
```

- [ ] **Step 3: Soften the side menu (drag handle + add-block button)**

Inspect `.bn-side-menu`/`.bn-button` (or whatever the rendered class turns out to be — check the live DOM, BlockNote's class names shift between versions) for the drag-handle and "+" buttons. Add overrides so their hover state uses `var(--accent)` (not BlockNote's hardcoded hover gray) and their icon color uses `var(--muted-foreground)`, with a `border-radius: var(--radius-sm)` and a `transition: background-color 150ms ease-out` for a calmer hover feel matching spec §14's "150–200ms ease-out" rule. Use the actual class names you observe in the running app's DOM, not guessed ones.

- [ ] **Step 4: Soften the slash-menu / suggestion-menu rows**

Inspect the slash menu's item rows (class likely `.bn-suggestion-menu-item` or similar — confirm in DOM). If BlockNote's `shadCNComponents` override from Task 4 didn't already route these through our own components (the suggestion menu is a separate UI surface from the formatting-toolbar's dropdowns/tooltips/popovers — check whether it's covered by `shadCNComponents` or is its own hardcoded list), add overrides for row padding (more generous, matching spec §14), hover background (`var(--accent)`), and the container's border/shadow (`var(--border)` / soft shadow, matching Tasks 3/4's popover treatment) so it doesn't look like a visually distinct component from our own dropdowns.

- [ ] **Step 5: Verify and screenshot**

Run: `pnpm test && pnpm exec tsc --noEmit`
Expected: green, clean (visual-only, no test should break).

Screenshot the editor with a block selected and the slash menu open (same mechanism as Task 3), saved to the scratchpad as `ux-fixes-blocknote-chrome.png`, path noted in your report. Compare side-by-side (mentally, in your report) against the Notion reference direction from planning: does it now read as part of one cohesive, soft design system rather than two visually distinct products bolted together?

- [ ] **Step 6: Commit**

```bash
git add src
git commit -m "style: soften BlockNote's block chrome (selection outline, side menu, slash menu)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: Code-block syntax highlighting — broad language support + auto-detect on paste

**Files:**

- Modify: `src/components/editor.tsx`, `package.json`, `pnpm-lock.yaml`
- Delete: `src/lib/shiki.bundle.ts` (superseded by the plain `shiki` package — see below)

**Interfaces:**

- Produces: code blocks render with real syntax highlighting across a broad set of common languages; pasting a recognizable code snippet into an untyped/default-language code block best-effort auto-detects and sets its language.

**Starting point — build on what's already there, don't start from zero:** `editor.tsx` already has a working `codeBlock` schema wired via a hand-generated `src/lib/shiki.bundle.ts` (built with shiki's `@shikijs/codegen` tool), but it's scoped to only 3 languages (`javascript`/`typescript`/`vue` families) and uses two themes (`light-plus`/`dark-plus`) that the user found ugly against our palette. A codegen'd bundle is a legitimate size-optimization technique, but for a desktop app (not a size-sensitive public website) it adds a fragile generated file for no real benefit — **replace it with the plain `shiki` package**, which lazy-loads languages on demand internally and needs no custom bundle file at all.

- [ ] **Step 1: Swap to the plain shiki package**

```bash
pnpm add shiki
pnpm remove @shikijs/core @shikijs/engine-javascript @shikijs/langs-precompiled @shikijs/themes @shikijs/types
```

Delete `src/lib/shiki.bundle.ts`.

- [ ] **Step 2: Broaden the language list and fix the theme/styling**

In `src/components/editor.tsx`, update the `codeBlock: createCodeBlockSpec({...})` config (inside the existing `BlockNoteSchema.create().extend({ blockSpecs: { codeBlock: ... } })`):

```tsx
import { createHighlighter } from 'shiki'
// (remove the old `import { createHighlighter } from '#lib/shiki.bundle'`)

// ...inside createCodeBlockSpec({...}):
supportedLanguages: {
  typescript: { name: 'TypeScript', aliases: ['ts'] },
  javascript: { name: 'JavaScript', aliases: ['js'] },
  tsx: { name: 'TSX' },
  jsx: { name: 'JSX' },
  vue: { name: 'Vue' },
  python: { name: 'Python', aliases: ['py'] },
  rust: { name: 'Rust', aliases: ['rs'] },
  go: { name: 'Go' },
  java: { name: 'Java' },
  c: { name: 'C' },
  cpp: { name: 'C++' },
  csharp: { name: 'C#', aliases: ['cs'] },
  php: { name: 'PHP' },
  ruby: { name: 'Ruby', aliases: ['rb'] },
  swift: { name: 'Swift' },
  kotlin: { name: 'Kotlin' },
  sql: { name: 'SQL' },
  bash: { name: 'Bash', aliases: ['sh', 'shell'] },
  json: { name: 'JSON' },
  yaml: { name: 'YAML', aliases: ['yml'] },
  toml: { name: 'TOML' },
  markdown: { name: 'Markdown', aliases: ['md'] },
  html: { name: 'HTML' },
  css: { name: 'CSS' },
  scss: { name: 'SCSS' },
  dockerfile: { name: 'Dockerfile' },
  graphql: { name: 'GraphQL' }
},
createHighlighter: () =>
  createHighlighter({
    themes: ['github-dark-default'],
    langs: [
      'typescript', 'javascript', 'tsx', 'jsx', 'vue', 'python', 'rust', 'go',
      'java', 'c', 'cpp', 'csharp', 'php', 'ruby', 'swift', 'kotlin', 'sql',
      'bash', 'json', 'yaml', 'toml', 'markdown', 'html', 'css', 'scss',
      'dockerfile', 'graphql'
    ]
  })
```

`shiki`'s `createHighlighter` lazy-loads each requested language via dynamic import internally — listing ~26 languages here does not bundle all of them eagerly. Confirm the theme name `github-dark-default` is current shiki's actual bundled theme id (check `node_modules/shiki`'s theme list/exports — theme ids do shift between shiki major versions; adjust if it's named differently in the installed version) and that it reads well (softer than the raw `#161616`/pure-white default the user called "丑") — if a single dark theme still looks flat against our palette, consider layering a subtle border/padding tweak on the code block container (`globals.css`, scoped to `[data-content-type=codeBlock]`) rather than fighting the shiki theme itself.

- [ ] **Step 3: Best-effort language auto-detection on paste**

The user specifically asked for this "尤其是复制一段代码过来" (especially when pasting a code snippet). Shiki itself does not do language detection (it only highlights a known language) — implement a small, honest heuristic, not a false promise of ML-grade detection:

1. Hook into the code block's paste handling. Check `node_modules/@blocknote/core/types/src/blocks/Code/` and BlockNote's own docs/source for whether pasting a fenced markdown code block (` ```python ... ``` `) into the editor already auto-creates a code block with the language read from the fence annotation — if so, that path already works and needs no new code; verify it with a manual paste test before building anything.
2. For the remaining gap — pasting _unfenced_ code directly into an existing code block whose language is still the default — write a small pure function `guessLanguage(code: string): string | undefined` in a new file `src/lib/guess-language.ts` using simple, explainable signature-pattern matching (not a dependency, not ML): e.g. `def ` + trailing `:` lines → python; `fn ` + `->` / `let mut` → rust; `func ` + `package ` → go; `<?php` → php; `#include` + `int main(` → c/cpp; `import ` + `from` (no `require(`) vs `require(`/`module.exports` → distinguishing ES-module-style vs CommonJS is unreliable enough that both can just map to javascript/typescript generically (don't over-claim precision here); `SELECT ` + `FROM` (case-insensitive) → sql. Keep the function small and testable — a handful of `if` checks returning early, not a scoring engine.
3. Wire it: on the code block's paste event (check BlockNote's block-level event hooks, or a ProseMirror-level paste handler exposed via `useCreateBlockNote`'s options — investigate the actual hook point rather than guessing), if the target code block's current language is the default/unset AND `guessLanguage` returns a confident match, call the block's language-setting API (`editor.updateBlock` with the new `props.language`) with the guessed value.

- [ ] **Step 4: Write tests for the detection heuristic**

Create `src/lib/guess-language.test.ts` with one test per language pattern from Step 3.2 (a short realistic snippet in, expected language name out) plus a test that ambiguous/plain-text input returns `undefined` rather than guessing wrong. Run `pnpm test` to verify these pass — this is the one part of this task that's cleanly unit-testable in isolation from BlockNote/DOM.

- [ ] **Step 5: Verify with a real check, not just tsc**

Run: `pnpm test && pnpm exec tsc --noEmit` (must stay green/clean). Then start the dev server and manually: (a) create a code block, type some Python, confirm real colored tokens render (not flat text); (b) paste an unfenced Rust snippet into a fresh default-language code block and confirm the language auto-switches to Rust; (c) try at least 3 more languages from the broadened list to spot-check highlighting actually works for them, not just the 3 the old bundle supported. Note exactly what you saw for each check in your report — a clean typecheck proves nothing about whether the highlighter or the detection heuristic actually fired.

- [ ] **Step 6: Commit**

```bash
git add src package.json pnpm-lock.yaml
git commit -m "feat: broaden code-block language support and add paste language detection

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: Editing UX — keep trailing empty space at the bottom of the editor

**Files:**

- Modify: `src/components/editor.tsx`

**Interfaces:** none new.

**The ask:** the user wants to be able to click below the last block and start typing without first pressing Enter repeatedly to create empty paragraphs — i.e. some clickable empty space below the content that continues the document, similar to Notion's behavior of the whole remaining page height being "live" for continuing to type.

- [ ] **Step 1: Check what BlockNote already provides**

BlockNote's compiled CSS already includes a `.bn-trailing-block { cursor: text; height: 30px }` rule, suggesting a built-in "trailing block" affordance (a thin clickable strip below the last real block that creates/focuses a new paragraph on click) already exists. Reproduce this in the running app first: click just below the last block's text and confirm whether typing starts immediately. If it already works but the clickable strip is just too thin (30px) to feel natural, this is a CSS-only fix (Step 2). If clicking below the content does nothing, investigate `useCreateBlockNote`'s options / `@blocknote/core`'s docs for a `trailingBlock` config option before writing custom click-handling from scratch.

- [ ] **Step 2: Widen the trailing click zone**

If the built-in trailing block exists but is too thin, override its height in `src/assets/globals.css` (or wherever Task 4/5's overrides live) to something generous — e.g. `.bn-trailing-block { min-height: 240px !important; }` — so a large portion of the remaining vertical space below the content is click-to-continue, without needing to touch component code. If no built-in mechanism exists at all, implement a minimal fallback: a click handler on empty space below the editor (inside the `Editor` component's wrapper `<div>`) that calls the editor's API to focus/create a trailing empty paragraph and place the cursor there — check `BlockNoteEditor`'s exposed methods (`editor.focus()`, appending a block) before writing this, and keep it as small as the built-in mechanism allows.

- [ ] **Step 3: Verify**

Run: `pnpm test && pnpm exec tsc --noEmit`
Expected: green, clean.

Manually verify in the dev server: click well below the last line of a document's content and confirm you can type immediately without pressing Enter first. Note what you observed in your report.

- [ ] **Step 4: Commit**

```bash
git add src
git commit -m "feat: widen the trailing click-to-continue zone below editor content

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 8: Full-width cover, last-updated time

**Files:**

- Modify: `src/components/page-header.tsx`, `src/components/page-header.test.tsx`, `src/pages/document-page.tsx`

**Interfaces:**

- Consumes: `date-fns` (already a dependency).
- Produces: cover image renders edge-to-edge (no visible left/right margin against the viewport); a relative "Edited {time} ago" line appears under the title, updating live.

- [ ] **Step 1: Fix the cover's horizontal bleed**

In `src/components/page-header.tsx`, the cover `<div>` currently uses `-mx-12 -mt-12` to cancel the page wrapper's `px-12 py-12` — this only cancels the WRAPPER's own padding, not the wrapper's `max-w-3xl` centering, so the cover still looks margined relative to the viewport (it's full-width only within the narrow content column, not the page). Change the cover wrapper to break out of the `max-w-3xl` column entirely using a viewport-relative bleed:

```tsx
{
  doc.cover ? (
    <div className="group relative left-1/2 mb-6 h-56 w-screen -translate-x-1/2">
      <img
        data-testid="doc-cover-image"
        src={backend.assetUrl(doc.id, doc.cover)}
        alt=""
        className="h-full w-full object-cover"
      />
      <Button
        variant="secondary"
        size="sm"
        className="absolute right-6 bottom-3 opacity-0 transition-opacity group-hover:opacity-100"
        onClick={() => onPatch({ cover: null })}
        data-testid="doc-cover-remove"
      >
        <X /> Remove cover
      </Button>
    </div>
  ) : null
}
```

The `left-1/2 w-screen -translate-x-1/2` pattern breaks any element out of a centered max-width container to true viewport width regardless of the sidebar/content layout — verify this visually (Step 3) since it depends on there being no unaccounted-for horizontal scrollbar introduced by `w-screen` when a sidebar is present (if `w-screen` overshoots because the sidebar reduces the visible content area, use `w-[100vw]` relative to the `<main>` scroll container's own width instead — check `document-page.tsx`'s wrapper structure and adjust so the cover fills exactly the width of `<main>`, not the full OS window including the sidebar).

- [ ] **Step 2: Add last-updated time**

In `src/pages/document-page.tsx`, import `formatDistanceToNow` from `date-fns` and render it under the title. Since `PageHeader` owns the title now, pass `doc.updatedAt` to it and render inside `page-header.tsx`, right after the title `<input>`:

```tsx
import { formatDistanceToNow } from 'date-fns'
// ...

;<p data-testid="doc-updated-at" className="text-muted-foreground mt-1 text-xs">
  Edited {formatDistanceToNow(new Date(doc.updatedAt), { addSuffix: true })}
</p>
```

This is a static render (updates on next React render, e.g. after an edit bumps `updatedAt`) — no need for a live-ticking interval; re-rendering only when the doc actually changes is enough for a "last edited" indicator and avoids an unnecessary timer.

- [ ] **Step 3: Update tests, verify, screenshot**

Update `src/components/page-header.test.tsx`'s cover tests if the new className structure breaks the existing `doc-cover-image`/`doc-cover-remove` assertions (testids are unchanged, only the wrapper's classes changed — the existing `screen.getByTestId(...)` queries should keep working). Add one small test: rendering with a fixed `updatedAt` shows the `doc-updated-at` testid with non-empty text.

Run: `pnpm test && pnpm exec tsc --noEmit`. Then, with the dev server running, take a screenshot of a document with a cover set to visually confirm the full-bleed fix worked (same screenshot mechanism as Task 3 Step 6), saved to the scratchpad as `ux-fixes-cover.png`, path noted in your report.

- [ ] **Step 4: Commit**

```bash
git add src
git commit -m "fix: full-bleed cover image and dynamic last-updated timestamp

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 9: Emoji picker — swap to frimousse

**Files:**

- Modify: `src/components/page-header.tsx`, `src/components/page-header.test.tsx`, `package.json`
- Modify: `e2e-tests/app.spec.ts` (adapt the "set a page icon" test's selector if needed)

**Interfaces:**

- Produces: same `PageHeader` public contract (`{ doc, onPatch }`); icon picking still calls `onPatch({ icon })`.

**Why frimousse:** headless, composable, explicitly built to pair with shadcn/Tailwind apps (verified via its own docs); virtualized, dependency-free, with real search and category navigation — a genuine upgrade over the 30-emoji hardcoded grid, matching our "always use the real library" rule.

- [ ] **Step 1: Install and inspect the real API**

```bash
pnpm add frimousse
```

Then read `node_modules/frimousse`'s type declarations (`.d.ts` files under its `dist`/`types` directory) to get the exact, current component/prop shapes — do not trust any cached description of its API from outside this checkout. Confirm: the root component name (likely `EmojiPicker.Root`), how search/viewport/list compose, and — critically — whether the per-emoji render (inside `EmojiPicker.List`) exposes a way to attach a `data-testid` to each rendered emoji button (needed to keep the existing e2e test working). Frimousse is virtualized, so the list may use a render-prop or a `children` function per row/emoji rather than a plain `.map()` — read the actual types before writing the component.

- [ ] **Step 2: Write the failing tests**

Update `src/components/page-header.test.tsx`'s icon-picker tests to reflect the new picker's real interaction (open the picker, type into its search input, click a result). The exact selectors depend on Step 1's findings — write these using real frimousse component testids/roles you find, not the old `doc-icon-option-<emoji>` scheme (that assumed a fixed static grid). Keep one thing constant: the trigger button keeps `data-testid="doc-icon-button"`, and after picking an emoji, `onPatch` must have been called with `{ icon: '<the emoji>' }`, and there must still be a way to remove the icon (`doc-icon-remove` testid, same as today).

- [ ] **Step 3: Run tests to verify they fail**

Run: `pnpm test`
Expected: FAIL against the old implementation (or compile error if imports don't resolve yet).

- [ ] **Step 4: Implement**

Rewrite the icon-picker section of `src/components/page-header.tsx` using frimousse's actual composable API discovered in Step 1, styled to match our design tokens (background `bg-popover`, text `text-popover-foreground`, search input using our own `Input` component if frimousse's search slot accepts a custom input element, otherwise style its native input to match via `[frimousse-*]` attribute selectors per its own styling convention). Preserve: `doc-icon-button` trigger testid, `onPatch({ icon })` on pick, `doc-icon-remove` to clear, the controlled-popover pattern already in place (`iconPickerOpen`/`setIconPickerOpen`, closing on pick).

- [ ] **Step 5: Run tests to verify they pass**

Run: `pnpm test && pnpm exec tsc --noEmit`
Expected: all pass, clean.

- [ ] **Step 6: Update the e2e test**

In `e2e-tests/app.spec.ts`, the existing test `set a page icon from the picker` clicks `doc-icon-option-🚀` — update it to match the real interaction (e.g. type "rocket" into the picker's search, click the first/only result). Do not weaken the assertion (`doc-icon-button` must still end up containing 🚀 or equivalent) — only adapt the selector to the real UI, matching how prior e2e selector adjustments were handled in this project.

Run: `pnpm e2e` and confirm this specific test (and the full suite) passes.

- [ ] **Step 7: Commit**

```bash
git add src package.json pnpm-lock.yaml e2e-tests
git commit -m "feat: swap emoji picker to frimousse

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 10: Comments — VaultThreadStore + wiring into the editor

**Files:**

- Create: `src/lib/vault-thread-store.ts`, `src/lib/vault-thread-store.test.ts`
- Modify: `src/lib/types.ts` (add `threads` to `Doc`), `src/lib/backend/memory-backend.ts` (default `threads`), `src-tauri/src/document.rs` (add `threads` field to `Document`, update every existing struct-literal test fixture), `src/components/editor.tsx` (wire `CommentsExtension`), `src/pages/document-page.tsx` (own the `VaultThreadStore` instance, patch `threads` into autosave)

**Interfaces:**

- Produces: `Doc.threads: unknown` (opaque, JSON-serializable — BlockNote's own `ThreadData`/`CommentData` shapes, with `Date` fields represented as ISO strings in storage and rehydrated to `Date` objects in memory by the store); `class VaultThreadStore extends ThreadStore` (from `@blocknote/core`) with a constructor `(initial: SerializedThread[], onChange: (serialized: SerializedThread[]) => void)`; implements every abstract method (`createThread`, `addComment`, `updateComment`, `deleteComment`, `deleteThread`, `resolveThread`, `unresolveThread`, `addReaction`, `deleteReaction`, `getThread`, `getThreads`, `subscribe`) per `node_modules/@blocknote/core/types/src/comments/threadstore/ThreadStore.d.ts` (already read in full during planning — re-read it yourself before implementing to confirm nothing drifted).

**Scope for v1 (deliberately minimal, matching the project's established YAGNI pattern):** single local user (no auth/roles complexity — `resolveUsers` returns one fixed local identity), no reactions UI (the store must implement `addReaction`/`deleteReaction` to satisfy the abstract class, but no button needs to call them yet), no Rust IPC surface (threads ride the existing `saveDocument` autosave path as an opaque field, exactly like `blocks`).

- [ ] **Step 1: Re-read the ThreadStore contract**

Read `node_modules/@blocknote/core/types/src/comments/threadstore/ThreadStore.d.ts` and `node_modules/@blocknote/core/types/src/comments/types.d.ts` in full. Confirm `ThreadData`/`CommentData` use real `Date` objects (not strings) for `createdAt`/`updatedAt`/etc.

- [ ] **Step 2: Add `threads` to the Doc/Document schema**

TS — in `src/lib/types.ts`, add `threads: unknown` to the `Doc` interface (not `DocumentMeta` — threads, like `blocks`, are full-document-only data):

```ts
export interface Doc extends DocumentMeta {
  schemaVersion: number
  cover: string | null
  blocks: unknown[]
  threads: unknown
}
```

In `src/lib/backend/memory-backend.ts`, `createDocument` must set a sensible empty default (`threads: {}`) on the created `Doc`.

Rust — in `src-tauri/src/document.rs`, add a `threads: serde_json::Value` field to the `Document` struct (right after `blocks`), matching `blocks`'s existing pattern (opaque JSON, Rust never interprets its contents — only `blocks` gets walked by `extract_text` for search). Default it to `serde_json::Value::Object(serde_json::Map::new())` in `create_document`. **This will break compilation of every existing test that constructs a `Document` struct literal directly** (`document.rs`'s own tests, and any fixture helpers in `index.rs`/`commands.rs` tests that build a `Document` by hand rather than calling `create_document`). Grep for `Document {` across `src-tauri/src/*.rs` and add `threads: serde_json::Value::Object(serde_json::Map::new()),` to every literal `cargo check` flags as missing a field — let the compiler find them all; do not guess which ones need it.

- [ ] **Step 3: Write the failing tests for VaultThreadStore**

Create `src/lib/vault-thread-store.test.ts`. Write tests covering: creating a thread returns `ThreadData` with a generated id and the initial comment; adding a comment to an existing thread appends it; resolving/unresolving flips `resolved`; deleting a thread removes it from `getThreads()`; `subscribe` fires with the updated map after each mutation and returns a working unsubscribe function; the `onChange` callback passed to the constructor fires with a JSON-serializable snapshot (plain objects/strings, no `Date` instances, no `Map`) after every mutation, so it's safe to hand directly to `update({ threads: ... })`; constructing the store from a previously-serialized snapshot rehydrates `Date` fields correctly (a round-trip test: serialize, construct a new store from that output, `getThreads()` returns equivalent data with real `Date` instances).

Use `crypto.randomUUID()` (already used elsewhere in this codebase, e.g. `MemoryBackend`) for generating thread/comment ids.

- [ ] **Step 4: Run tests to verify they fail**

Run: `pnpm test`
Expected: FAIL — module doesn't exist yet.

- [ ] **Step 5: Implement `VaultThreadStore`**

Implement the class satisfying every abstract method from Step 1. Internally: a `Map<string, ThreadData>` as the live in-memory state; a list of subscriber callbacks; every mutating method updates the map, calls all subscribers, calls the constructor's `onChange` with a serialized (dates → ISO strings) snapshot, and resolves its promise. `getThread`/`getThreads` are synchronous per the abstract class's own signatures (not `Promise`-returning — match that exactly). A single hardcoded local user id (e.g. `'local-user'`) is used for every comment's `userId`.

- [ ] **Step 6: Run tests to verify they pass**

Run: `pnpm test && pnpm exec tsc --noEmit`
Expected: all pass, clean.

- [ ] **Step 7: Wire it into the editor and document page**

In `src/pages/document-page.tsx`, own a `VaultThreadStore` instance (created once per `doc.id`, e.g. via `useMemo` keyed on `docId`, initialized from `doc.threads`, with `onChange` calling `update({ threads: serialized })` — the same debounced autosave path `blocks`/`title` already use). Pass it down to `Editor`.

In `src/components/editor.tsx`, accept a `threadStore: VaultThreadStore` prop and wire BlockNote's `CommentsExtension` (from `@blocknote/core`) into `useCreateBlockNote`'s extensions/comments config, with `resolveUsers: async (userIds) => userIds.map((id) => ({ id, username: 'You', avatarUrl: '' }))` (single local user — every id resolves to the same identity, matching v1 scope). Confirm — by reading `node_modules/@blocknote/core/types/src/comments/extension.d.ts` and how `useCreateBlockNote`'s options type accepts a `comments`/extension config (re-check the actual option key name; this plan's earlier grep found the extension factory but not yet the exact `useCreateBlockNote` option key that wires it in) — the correct integration point, and use BlockNote's `AddCommentButton` (from `@blocknote/react`) in the formatting toolbar so selecting text and clicking it opens a comment composer. If BlockNote's default `FormattingToolbar` doesn't include `AddCommentButton` automatically once comments are configured, render a custom `FormattingToolbar` with `AddCommentButton` added (check `@blocknote/react`'s exports for the default toolbar composition helper before hand-building one from scratch).

- [ ] **Step 8: Run everything**

Run: `pnpm test && cargo test --manifest-path src-tauri/Cargo.toml && pnpm exec tsc --noEmit`
Expected: all green, clean.

- [ ] **Step 9: Commit**

```bash
git add src src-tauri
git commit -m "feat: comment threads via BlockNote's open-source Comments extension

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 11: Reposition comments to a right-side rail (Notion reference)

**Files:**

- Modify: `src/pages/document-page.tsx`, `src/components/editor.tsx`, `src/components/comment-threads-sidebar.tsx`, `src/assets/globals.css`
- Test: `src/pages/document-page.test.tsx`

**Interfaces:**

- Produces: `document-page.tsx` renders a shared right-margin rail container (`data-testid="page-rail"`, a plain `<div>` whose DOM node is tracked via `useState<HTMLDivElement | null>` set through a callback `ref`, exposed internally as `pageRailNode`) alongside the existing centered `max-w-3xl` reading column. This rail is the _single shared_ right-margin slot for the page — Task 12 (table of contents) stacks its own section inside this same container later; do not build anything in this task that assumes it's the only consumer.
- `Editor`'s props gain `commentsPortalTarget: HTMLElement | null`, forwarded from `document-page.tsx`'s `pageRailNode`.
- `CommentThreadsSidebar`'s props change from `{}` to `{ portalTarget: HTMLElement | null }`; when `portalTarget` is non-null it renders via `ReactDOM.createPortal` into that node instead of inline.

**Context:** Right now `CommentThreadsSidebar` (`src/components/comment-threads-sidebar.tsx`) renders as the last child of `<BlockNoteView>` in `editor.tsx:283-289`, appearing as a full-width block below the document body, inside the _same_ centered column as the rest of the page (`document-page.tsx`'s `mx-auto w-full max-w-3xl px-12 py-12` wrapper) — not a side panel at all. The user attached a real Notion screenshot and asked for this to move to the right margin, styled like Notion's own floating comment cards: avatar, author name, timestamp, and comment body, with a "Reply…" input (attachment/mention/send icons) visible on whichever card is currently active/selected.

Good news: BlockNote's own `Comment`/`Card` components (`node_modules/@blocknote/react/src/components/Comments/Comment.tsx`, `node_modules/@blocknote/shadcn/src/comments/Card.tsx` — read both in full before starting) already render exactly that shape (avatar/name via the `authorInfo` prop, `timeString`, the comment body, hover-revealed actions, and a full reply composer on the selected thread). Nothing needs to change in _what_ is shown — only _where_ it renders and how the rail itself is styled.

The reason this can't just be "move the JSX to `document-page.tsx`": `ThreadsSidebar`/`useThreads` (used inside `CommentThreadsSidebar`) read the editor off `BlockNoteContext`, and the card components off `ComponentsContext`/`ShadCNComponentsContext` — both are provided only inside `<BlockNoteView>`'s own subtree (confirmed via `@blocknote/react`'s `BlockNoteView.tsx` and `@blocknote/shadcn`'s `BlockNoteView.tsx` during the review that preceded this task). So `CommentThreadsSidebar` must keep rendering _inside_ `<BlockNoteView>`, but its rendered output needs to _physically_ land in a DOM node outside the centered reading column. `ReactDOM.createPortal` is the standard bridge for exactly this: the component keeps reading context from where it's mounted in the React tree, while painting into an arbitrary DOM node elsewhere on the page.

**Explicitly out of scope for this task** (state this in your report; don't attempt it): per-thread vertical position-syncing so each card floats beside its own highlighted text at the matching scroll position (which is what real Notion actually does). `ThreadsSidebar` only exposes `threadPositions` as ProseMirror document offsets (`from`/`to`), not pixel coordinates — turning that into scroll-synced Y positions (via `editor.view.coordsAtPos`, scroll/resize listeners, and collision handling when two threads sit close together) is a substantially larger feature. This task ships a simpler, still Notion-inspired v1: every thread stacked as a vertical list of cards in a persistent right rail — which is literally what BlockNote's own `ThreadsSidebar` is designed for (its source doc comment: "similar to Google Docs' Show All Comments sidebar"), not per-anchor floating.

**Known v1 trade-off, also worth stating in your report:** the rail is hidden below a viewport/container breakpoint (see Step 1). Below that breakpoint, comments become inaccessible (not just repositioned) — a regression versus today's always-visible-but-ugly placement. Given this is a fixed-size desktop Tauri app (not a responsive public website), that's an acceptable v1 trade-off, not something to solve here with a responsive inline fallback.

- [ ] **Step 1: Restructure `document-page.tsx`'s layout**

Replace the current single centered wrapper with a flex row: the existing reading column (now `flex-1`, self-centering via `mx-auto` when the rail is hidden) plus a new rail `<div>`:

```tsx
const [pageRailNode, setPageRailNode] = useState<HTMLDivElement | null>(null)
```

```tsx
return (
  <div
    data-testid="document-page"
    className="mx-auto flex w-full max-w-6xl gap-10 px-12 py-12"
  >
    <div className="mx-auto min-w-0 max-w-3xl flex-1">
      <PageHeader doc={doc} onPatch={update} />
      <EditorBoundary>
        <Editor
          key={doc.id}
          docId={doc.id}
          initialBlocks={doc.blocks}
          onBlocksChange={(blocks) => update({ blocks })}
          threadStore={threadStore}
          commentsPortalTarget={pageRailNode}
        />
      </EditorBoundary>
    </div>
    <div
      ref={setPageRailNode}
      data-testid="page-rail"
      className="hidden w-[300px] shrink-0 xl:block"
    />
  </div>
)
```

Treat `max-w-6xl`, the `xl:` breakpoint, and the rail's `w-[300px]` as a _starting point_, not a fixed requirement — verify live with the dev server running (`pnpm dev`, or drive it via the Playwright MCP tools) that: the reading column still looks centered and unchanged in width when the rail is hidden or empty; the rail doesn't visually collide with `SidebarLeft` at the app's normal window size; the rail comfortably fits BlockNote's `300px`-wide cards without its own horizontal scrollbar. Adjust the numbers if they don't hold up, the same way Task 5's per-block-type side-menu heights were tuned empirically rather than guessed.

- [ ] **Step 2: Thread the portal target through `Editor`**

In `src/components/editor.tsx`, add `commentsPortalTarget: HTMLElement | null` to `EditorProps` and pass it through:

```tsx
<CommentThreadsSidebar portalTarget={commentsPortalTarget} />
```

- [ ] **Step 3: Portal `CommentThreadsSidebar`'s output into the rail**

Rewrite `src/components/comment-threads-sidebar.tsx`:

```tsx
import { ThreadsSidebar, useThreads } from '@blocknote/react'
import { createPortal } from 'react-dom'

interface CommentThreadsSidebarProps {
  portalTarget: HTMLElement | null
}

export function CommentThreadsSidebar({
  portalTarget
}: CommentThreadsSidebarProps) {
  const threads = useThreads()

  if (threads.size === 0) {
    return null
  }

  const content = (
    <div data-testid="comment-threads-sidebar" className="flex flex-col gap-3">
      <ThreadsSidebar filter="all" sort="position" />
    </div>
  )

  return portalTarget ? createPortal(content, portalTarget) : content
}
```

Keep the doc comment explaining _why_ this exists (BlockNote's #1701, the `filter="all"` quirk, why it must stay inside `<BlockNoteView>`) — update it to describe the rail placement instead of the old in-flow placement, and add the context/out-of-scope reasoning from this task above. Drop the "Comments" `<h2>` heading and the `border-t`/`mt-10` divider treatment from the old in-flow version — those made sense as a section break below the document body; they don't fit a rail that already reads as its own distinct column. If you think an empty-state affordance is still worth keeping, that's your call to make and justify in your report, not a requirement.

- [ ] **Step 4: Clean up the now-obsolete CSS workarounds in `globals.css`**

Read the existing block around `.bn-threads-sidebar` (currently documented as being for the old in-flow placement). Two things change now that cards render in an actual ~300px rail instead of a full-width in-flow section:

1. `.bn-threads-sidebar .bn-thread { width: 100% !important; }` was added to stretch BlockNote's hardcoded `w-[300px]` `Card` to fill the old full-width section. Now that the rail itself is ~300px wide, `Card`'s native `w-[300px]` is already correct — this override is very likely redundant (verify live; remove it if the cards render correctly without it).
2. `.bn-threads-sidebar .bn-thread.selected { ... }` was a workaround for `@blocknote/shadcn`'s `Card.tsx` applying its selected-state styling via **bare, unprefixed** Tailwind utility classes (`bg-accent`, `text-accent-foreground` — see `node_modules/@blocknote/shadcn/src/comments/Card.tsx`), which this app's Tailwind v4 JIT scanner never compiles, since every other occurrence of those class names anywhere in `src/` is variant-prefixed (`hover:bg-accent`, etc.), and the scanner only generates classes it finds literally in scanned source files. That workaround is _also_ dead — `Card.tsx` never actually sets a class literally named `selected` on the DOM (that `.bn-thread.selected` CSS selector target comes from BlockNote's _base_, non-shadcn `@blocknote/react/style.css`, for a different component variant this app doesn't use), so the override never matched anything either.

   Fix the real problem at its root instead: add a Tailwind v4 safelist directive near the top of `globals.css`, next to the existing `@import` statements —

   ```css
   @source inline("bg-accent text-accent-foreground");
   ```

   This forces Tailwind to actually generate those two utility classes, so `Card.tsx`'s own `selected ? "bg-accent text-accent-foreground" : ""` starts working correctly with zero custom CSS needed. Delete the old `.bn-threads-sidebar .bn-thread.selected { ... }` rule entirely, and rewrite the doc comment above this section to describe the rail placement and the `@source inline` fix instead of the old in-flow reasoning. Verify live (both themes) that selecting a thread now tints it with the app's actual `--accent` token rather than going more transparent.

- [ ] **Step 5: Add a regression test for the rail wiring**

`document-page.test.tsx` already mocks `Editor` (jsdom can't render real BlockNote/ProseMirror). Extend that mock to also read `commentsPortalTarget` so a test can assert `document-page.tsx` actually creates and forwards a real DOM node:

```tsx
vi.mock('#components/editor', () => ({
  Editor: ({
    docId,
    initialBlocks,
    onBlocksChange,
    commentsPortalTarget
  }: {
    docId: string
    initialBlocks: unknown[]
    onBlocksChange: (blocks: unknown[]) => void
    commentsPortalTarget: HTMLElement | null
  }) => (
    <button
      data-testid="mock-editor"
      data-doc-id={docId}
      data-block-count={initialBlocks.length}
      data-has-rail-target={commentsPortalTarget !== null}
      onClick={() => onBlocksChange([{ type: 'paragraph', content: 'edited' }])}
    >
      mock editor
    </button>
  )
}))
```

Add a test:

```tsx
test('provides the editor with a real rail DOM node to portal comments into', async () => {
  const doc = await backend.createDocument(null, 'Has rail')
  renderPage(doc.id)
  expect(await screen.findByTestId('page-rail')).toBeInTheDocument()
  await waitFor(() =>
    expect(screen.getByTestId('mock-editor')).toHaveAttribute(
      'data-has-rail-target',
      'true'
    )
  )
})
```

(The `waitFor` accounts for the one-render lag between initial mount, when the callback ref hasn't fired yet and `pageRailNode` is still `null`, and the following render once it has.)

- [ ] **Step 6: Run tests to verify they pass**

Run: `pnpm test && pnpm exec tsc --noEmit`
Expected: all pass, clean.

- [ ] **Step 7: Live-verify the actual comment placement**

jsdom can't render real BlockNote, so the portal itself is only exercised live. With the dev server running (`pnpm dev`, mocked IPC — same setup Task 9/10 used), open a document, select some text, add a comment via the formatting toolbar's comment button, and confirm: the comment card renders inside the `page-rail` container on the right (not below the document body); it keeps working correctly after adding a second comment (cards stack, don't overlap); selecting a card visually tints it with the app's accent color (Step 4's fix); it looks correct in both light and dark theme (toggle via the theme button). Screenshot to the scratchpad as `ux-fixes-comments-rail.png`.

- [ ] **Step 8: Commit**

```bash
git add src
git commit -m "feat: reposition comments to a right-side rail

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 12: Table of contents via react-fluid-toc

**Depends on Task 11:** Task 11 establishes `document-page.tsx`'s shared right-margin rail (`data-testid="page-rail"`, the `pageRailNode` DOM node) for the comments panel. This task reuses that same rail as a second stacked section — it does not create its own independent right-margin element.

**Files:**

- Create: `src/components/table-of-contents.tsx`, `src/components/table-of-contents.test.tsx`
- Modify: `src/pages/document-page.tsx`, `package.json`

**Interfaces:**

- Produces: `TableOfContents` component `{ blocks: unknown[] }`, rendered as a section inside the shared `page-rail` container Task 11 already renders in `document-page.tsx` (stacked above or below the comments section — check which reads better live; Notion itself places the TOC above comments when both are present), rendering a list of headings that scrolls to and highlights the active heading. Do not give it its own fixed/absolute positioning — it lives in normal flow inside the rail `<div>`, which Task 11 already positions.

**Investigation needed (BlockNote doesn't render semantic heading tags):** BlockNote's `heading` blocks render as plain `div`s styled to look like headings (confirmed via its compiled CSS — `[data-content-type=heading]{--level:3em;...}`, no actual `<h1>`-`<h6>` element), so `react-fluid-toc`'s DOM-scanning `extractHeadings` helper (which looks for real `<h2>`/`<h3>` tags) will find nothing. Instead: derive the heading list directly from `editor.document` (walk the block tree for `type === 'heading'`, reading `props.level` and the block's plain-text content), and inject a real `id` attribute onto each heading's rendered DOM node yourself (BlockNote's DOM uses `data-id` on `.bn-block-outer`, not `id` on the heading element — after each editor change, query `[data-id="${block.id}"] [data-content-type="heading"]` inside the editor's root and set `.id = block.id` on it) so `react-fluid-toc`'s anchor-scrolling and `IntersectionObserver`-based active-heading detection have real elements to find via `document.getElementById`.

- [ ] **Step 1: Install and confirm the API**

```bash
pnpm add react-fluid-toc
```

Read its actual installed type declarations to confirm `FluidToc`'s prop names (`items`, `scrollOffset`, `smoothScroll`, `autoScroll`, `onItemClick`, `className`) and the `TocItem` shape (`{ id, text, depth }`) match what was found during planning research — adjust if the installed version differs.

- [ ] **Step 2: Write the failing test**

Create `src/components/table-of-contents.test.tsx`. Test: given a `blocks` array containing heading blocks (construct plausible BlockNote heading block objects: `{ id: 'h1', type: 'heading', props: { level: 1 }, content: [{ type: 'text', text: 'Intro' }] }`) and a paragraph block (which must be excluded), the component renders the heading text as visible list items and excludes the paragraph. Test that with an empty/no-heading `blocks` array, the component renders nothing (no empty panel taking up space).

- [ ] **Step 3: Run test to verify it fails**

Run: `pnpm test`
Expected: FAIL — module doesn't exist.

- [ ] **Step 4: Implement**

`src/components/table-of-contents.tsx`: a small pure function extracting `TocItem[]` from a BlockNote blocks array (walk recursively including nested `children`, filter `type === 'heading'`, join `content` array's text nodes for the label, map `props.level` to `depth`), then render `<FluidToc items={items} scrollOffset={56} />` (56 ≈ titlebar height) wrapped in a `data-testid="table-of-contents"` container, returning `null` when `items.length === 0`. Render it as a section inside Task 11's shared `page-rail` container in `document-page.tsx` (that container already handles the responsive show/hide behavior — don't duplicate a second breakpoint here).

- [ ] **Step 5: Wire heading id injection**

In `src/pages/document-page.tsx` (or inside `Editor` itself, whichever keeps concerns cleanest — probably `Editor`, since it already owns the BlockNote root), after every `onChange`/on mount, run the DOM-id-injection logic described above inside a `useEffect` keyed on the current blocks, querying within the editor's own root element (not `document` globally, to avoid ever touching unrelated DOM).

- [ ] **Step 6: Run tests, verify, screenshot**

Run: `pnpm test && pnpm exec tsc --noEmit`. Then, with the dev server running, create a document with 2-3 headings and confirm visually that the TOC appears and clicking an entry scrolls to and highlights it; screenshot to the scratchpad as `ux-fixes-toc.png`.

- [ ] **Step 7: Commit**

```bash
git add src package.json pnpm-lock.yaml
git commit -m "feat: table of contents via react-fluid-toc

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 13: Fix the block-type "+" popover getting compressed near the viewport bottom

**Files:**

- Modify: `src/components/editor.tsx` and/or `src/components/app-shell.tsx` (exact target depends on investigation)

**Interfaces:** none new — layout/positioning fix only.

**Investigation required — this is a real bug that needs runtime reproduction, not a guessed fix:**

1. Start the dev server, open a long document (enough blocks to require scrolling), scroll so the cursor/"+" button sits near the bottom of the viewport, click it to open the block-type suggestion menu, and confirm you can reproduce the "compressed" symptom (the menu shrinks to fit remaining space below the click point instead of flipping to open upward).
2. Inspect the popup's actual DOM location: is it rendered inline inside our scrollable `<main>` (`data-testid="page-content"`, `overflow-y-auto`), or portaled to `document.body`? BlockNote typically portals floating UI, but check for real — if it's portaled to `document.body`, the compression is a floating-ui placement/flip configuration issue on BlockNote's side, not a clipping issue on ours. If it's NOT portaled (rendered as a descendant of our `overflow-y-auto` container), that container is what's constraining/clipping it, and the fix is either configuring BlockNote's portal target (check `BlockNoteViewProps`/`PortalTarget` types, already referenced in `BlockNoteView.d.ts`, for a way to specify `document.body` explicitly) or restructuring so the popup escapes our scroll container.
3. Once the root cause is identified, apply the narrowest fix that addresses it (portal target configuration is strongly preferred over restructuring our layout, since our layout is otherwise working correctly).

- [ ] **Step 1: Reproduce and diagnose**

Follow the investigation steps above. Write your findings (root cause identified, DOM structure observed) into your report before writing any fix.

- [ ] **Step 2: Apply the fix**

Implement whatever Step 1's diagnosis points to. If it's a `BlockNoteView` prop (portal target), wire it in `editor.tsx`. If it requires a layout change (unlikely, but possible if some ancestor has an `overflow` that clips even portaled content due to a CSS containment quirk), make the minimal change and explain why in your report.

- [ ] **Step 3: Verify the fix**

Reproduce the original repro steps again and confirm the menu now opens upward (or otherwise remains fully visible) when triggered near the viewport bottom. This is very hard to assert in an automated test (depends on exact scroll position/viewport size) — a Playwright test IS worth attempting if the fix is DOM-observable (e.g., assert the popup's bounding rect stays within the viewport when opened near the bottom), but if it proves too flaky/complex to assert reliably, note that in your report and rely on the manual repro instead — don't force a brittle test into the suite.

- [ ] **Step 4: Run the full check set**

Run: `pnpm test && pnpm exec tsc --noEmit && pnpm e2e`
Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add src
git commit -m "fix: block-type suggestion menu no longer compresses near viewport bottom

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 14: E2e coverage for the new UI

**Files:**

- Modify: `e2e-tests/app.spec.ts`

**Interfaces:**

- Consumes: `theme-toggle`, `table-of-contents`, comment-related testids from Tasks 2, 10, 11.

- [ ] **Step 1: Append tests**

Add e2e tests (real flows, no weakened assertions) for:

- Theme toggle: click `theme-toggle`, confirm `<html>` gains the `dark` class (or whatever next-themes' `attribute="class"` produces) and the icon swaps.
- Comment flow: create a doc, type some text in the editor, select it, trigger the add-comment action, type a comment body, submit, confirm a thread indicator appears in the editor.
- Table of contents: create a doc with at least two headings (typed via the editor, e.g. `# Heading one` markdown shortcut if BlockNote supports it, or via the slash menu), confirm `table-of-contents` testid is visible and lists both headings, click one and confirm the page scrolls to it.
- Code block: create a code block, type recognizable Python (e.g. `def add(a, b):\n    return a + b`), confirm the rendered code block contains styled token spans (not just plain text) — a coarse but reliable signal that highlighting fired.

Use real testids discovered during Tasks 2/8/9's implementation — if any of these flows turn out to be too brittle for reliable e2e assertion (e.g. exact scroll-position checks), scope the assertion to what's reliably observable (element visible, correct text present) rather than skipping the test entirely.

- [ ] **Step 2: Run the suite**

Run: `pnpm e2e`
Expected: all passing, including the pre-existing tests.

- [ ] **Step 3: Run everything**

Run: `pnpm test && cargo test --manifest-path src-tauri/Cargo.toml && pnpm exec tsc --noEmit && pnpm e2e`
Expected: all green.

- [ ] **Step 4: Commit**

```bash
git add e2e-tests
git commit -m "test: e2e coverage for theme toggle, comments, and table of contents

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 15: Fix missing elevation on BlockNote's comment cards (`shadow-sm` never compiles)

**Context (live user report, screenshot-driven):** after Task 11 shipped the right-side comments rail, the user reported the "add comment" composer (the floating card that appears when you select text and click the formatting toolbar's comment button — BlockNote's own `FloatingComposerController`/`FloatingComposer`, auto-rendered once `CommentsExtension` is registered) looks broken: it renders with no visible border/shadow distinguishing it from the page, so it reads as if it's part of the document flow rather than a floating overlay, overlapping surrounding text with nothing to separate the two.

**Root cause, confirmed via a real compiled build (not guesswork):** `FloatingComposer` and `ThreadsSidebar`'s `Thread` component both render through the same `Components.Comments.Card` → `ShadCNComponents.Card.Card`, which (since this app never overrides `shadCNComponents.Card` in `editor.tsx`) falls back to `@blocknote/shadcn`'s own bundled default (`node_modules/@blocknote/shadcn/src/components/ui/card.tsx`):

```tsx
className={cn(
  "bg-card text-card-foreground flex flex-col gap-6 rounded-xl border py-6 shadow-sm",
  className,
)}
```

Running `pnpm exec vite build --mode development --outDir /tmp/hikki-css-check` and grepping the compiled `assets/*.css` confirms `.border{border-style:...;border-width:1px}` and `.bg-card{background-color:var(--card)}` both compile correctly (their tokens are used bare elsewhere in this app's own `src/components/ui/card.tsx`), but **no `.shadow-sm{...}` rule exists anywhere in the compiled output** — only `.shadow-lg`, `.shadow-md`, `.shadow-xl`, `.shadow-none` compile, because those are the only shadow utilities this app's own source ever uses literally, unprefixed. Tailwind v4's JIT scanner only generates a utility class if its exact literal token appears somewhere in scanned source — `shadow-sm` never does, anywhere in this codebase — so every comment card (both the floating composer and every posted-thread card in the rail) silently loses its entire `box-shadow`, leaving only a 1px border to read as "elevated," which is not enough contrast against this app's soft, low-contrast palette.

This is the exact same category of bug Task 11 already found and fixed once for `bg-accent`/`text-accent-foreground` (BlockNote's `Card.tsx` selected-state styling) via a `@source inline(...)` Tailwind v4 safelist directive already present in `globals.css`:

```css
@source inline("bg-accent text-accent-foreground");
```

**Files:**

- Modify: `src/assets/globals.css`

- [ ] **Step 1: Extend the existing safelist**

Add `shadow-sm` to the existing `@source inline(...)` directive near the top of `globals.css` (do not add a second, separate directive — one list is clearer):

```css
@source inline("bg-accent text-accent-foreground shadow-sm");
```

- [ ] **Step 2: Verify the fix compiles, via a real build (not just visual inspection)**

```bash
pnpm exec vite build --mode development --outDir /tmp/hikki-css-check-verify
grep -oE '\.shadow-sm\{[^}]*\}' /tmp/hikki-css-check-verify/assets/*.css
rm -rf /tmp/hikki-css-check-verify
```

Expected: the grep now prints a real `.shadow-sm{...}` rule (previously printed nothing — confirm this yourself before/after if you want to see the delta).

- [ ] **Step 3: Live-verify in both themes**

With the dev server running (`pnpm dev`), open a document, select some text, click the formatting toolbar's comment button, and confirm the composer now renders with a visible shadow clearly separating it from the page — no longer looking like inline content. Add a comment and confirm the resulting card in the right rail (`page-rail`) also now shows the same shadow. Check both light and dark theme (the shadow's actual visibility differs between themes — `--tw-shadow-color` defaults to a black-based alpha value; if it reads as too subtle or too harsh in dark mode, that's your judgment call to adjust, but don't silently skip checking dark mode). Screenshot to the scratchpad as `ux-fixes-comment-card-shadow.png` (one screenshot per theme is fine).

- [ ] **Step 4: Run the full test suite**

Run: `pnpm test && pnpm exec tsc --noEmit`
Expected: all pass, clean (this is a CSS-only change; no test file should need updating, but confirm nothing broke).

- [ ] **Step 5: Commit**

```bash
git add src/assets/globals.css
git commit -m "fix: restore missing shadow on BlockNote comment cards

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 16: Fix BlockNote toolbar buttons rendering as nested `<button>` elements (Tooltip `asChild`/`render` mismatch)

**Context (surfaced during Task 14's e2e work, confirmed by two independent reviewers):** every button in BlockNote's toolbar UI that uses a `mainTooltip` (side menu buttons, formatting toolbar buttons, the comment composer's "Save" button, badges) renders wrapped in an _extra_ real `<button>` element — producing a live React console error (`<button> cannot contain a nested <button>`) and a duplicate element in the accessibility tree for every single one of them (confirmed live: `getByRole('button', {name: 'Add comment'})` and similar locators strict-mode-match two elements, worked around with `.last()` in Task 14's e2e tests — that workaround stays in place after this task, since it's still valid, just no longer strictly necessary).

**Root cause, already confirmed (no further investigation needed — implement directly):** `@blocknote/shadcn`'s bundled toolbar components (`node_modules/@blocknote/shadcn/src/toolbar/Toolbar.tsx:110` and `node_modules/@blocknote/shadcn/src/badge/Badge.tsx:50`) call `<ShadCNComponents.Tooltip.TooltipTrigger asChild>{someButton}</ShadCNComponents.Tooltip.TooltipTrigger>` — the Radix convention, where `asChild` makes the trigger merge its behavior onto its single child instead of rendering its own wrapping element. This app's own `TooltipTrigger` (`src/components/ui/tooltip.tsx:24`) wraps `@base-ui/react/tooltip`'s `Trigger`, which has **no `asChild` concept at all** — Base UI's own type declarations (`node_modules/@base-ui/react/tooltip/trigger/TooltipTrigger.d.ts`) show it "Renders a `<button>` element" unconditionally, with `render` (Base UI's actual polymorphic escape hatch, part of `BaseUIComponentProps`) as the supported way to swap in a custom element. Since our `TooltipTrigger` just spreads `...props` (including the meaningless `asChild` boolean) onto Base UI's `Trigger` and ignores `children` isn't specially handled, `asChild` does nothing — the component always renders its own real `<button>` around whatever child was passed, producing the nested-button bug.

**This codebase already has a working precedent for the correct bridge** — `src/components/ui/sidebar.tsx:522` already does `<TooltipTrigger render={render} />`, passing a React element into Base UI's `render` prop to have the Trigger merge onto that element instead of rendering its own. This task applies the same pattern generically inside `TooltipTrigger` itself, so every caller that passes Radix-style `asChild` (i.e. every BlockNote toolbar component) gets correct behavior automatically, with zero changes needed anywhere else.

**Files:**

- Modify: `src/components/ui/tooltip.tsx`
- Test: `src/components/ui/tooltip.test.tsx` (create if it doesn't already exist — check first)

**Interfaces:** `TooltipTrigger`'s prop type widens to accept an optional `asChild?: boolean` in addition to its existing Base UI `Trigger.Props` — purely an interop shim for Radix-style callers (BlockNote), not part of Base UI's own contract. No change to `TooltipTrigger`'s existing `render`-based call sites (`sidebar.tsx`) — the fix must not disturb that already-working usage.

- [ ] **Step 1: Check for an existing test file first**

```bash
ls src/components/ui/tooltip.test.tsx 2>/dev/null || echo "no existing test file"
```

If component tests for `src/components/ui/*.tsx` primitives don't already exist elsewhere in this codebase as an established pattern (check a couple of sibling files, e.g. `src/components/ui/popover.tsx`/`dropdown-menu.tsx`, for a `.test.tsx` counterpart), a full jsdom+Testing-Library unit test for this one component may not fit this codebase's conventions — in that case, skip straight to a live/manual + Playwright verification instead of inventing a new testing pattern for one file. Use your judgement based on what you find; state your reasoning in your report either way.

- [ ] **Step 2: Fix `TooltipTrigger`**

In `src/components/ui/tooltip.tsx`, change:

```tsx
function TooltipTrigger({ ...props }: TooltipPrimitive.Trigger.Props) {
  return <TooltipPrimitive.Trigger data-slot="tooltip-trigger" {...props} />
}
```

to something equivalent to:

```tsx
function TooltipTrigger({
  asChild,
  children,
  ...props
}: TooltipPrimitive.Trigger.Props & {
  asChild?: boolean
  children?: React.ReactNode
}) {
  return (
    <TooltipPrimitive.Trigger
      data-slot="tooltip-trigger"
      render={asChild ? (children as React.ReactElement) : undefined}
      {...props}
    >
      {asChild ? undefined : children}
    </TooltipPrimitive.Trigger>
  )
}
```

Add the `React` import if this file doesn't already have one in scope (check — it may already, or you may need `import type { ReactElement, ReactNode } from 'react'` instead of the full namespace import, whichever matches this codebase's existing style in sibling `ui/` files). Verify the actual prop name Base UI expects for this (`render`, per its type declarations already cited above) rather than assuming the snippet above is letter-perfect — re-check `TooltipTrigger.d.ts` yourself before finalizing.

- [ ] **Step 3: Verify live**

With the dev server running (`pnpm dev`), open the browser devtools console, open a document, hover over a formatting-toolbar button (or the side-menu "+"/drag-handle buttons, or trigger the comment composer's Save button) and confirm: (a) no `<button> cannot contain a nested <button>` console error appears, (b) the tooltip itself still shows correctly on hover with the same visual styling as before, (c) `getByRole('button', {name: ...})` for one of these buttons now matches exactly one element, not two (spot check this via the Playwright browser tools' accessibility snapshot). Also confirm the _existing_, already-working `render`-based usage (a sidebar item with a tooltip, e.g. collapse the sidebar to icon-only mode if that's what triggers `sidebar.tsx`'s tooltip path — check `sidebar.tsx` around line 522 for the exact condition) still renders and behaves identically to before this change.

- [ ] **Step 4: Remove the now-unnecessary `.last()` workarounds (optional, your judgement)**

Task 14's e2e tests added `.last()` to `getByRole('button', {name: 'Add comment'})` and `getByRole('button', {name: 'Save'})` specifically to work around this bug. Now that it's fixed, `.last()` should still work (there's only one matching element now, so `.last()` is a no-op) — you can leave it as-is (harmless) or simplify it back to a plain `getByRole(...)` call for clarity. Your call; if you simplify it, re-run `pnpm e2e` to confirm nothing broke.

- [ ] **Step 5: Run the full check set**

Run: `pnpm test && pnpm exec tsc --noEmit && pnpm e2e`
Expected: all green (94 or more unit tests depending on whether Step 1 added a new test file; 13 e2e tests).

- [ ] **Step 6: Commit**

```bash
git add src e2e-tests
git commit -m "fix: bridge BlockNote's asChild tooltip triggers onto Base UI's render prop

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 17: Documentation sync (run LAST)

**Files:**

- Modify: `CLAUDE.md`, `README.md`

- [ ] **Step 1: Update `CLAUDE.md`**

Add/update bullets under Architecture reflecting: next-themes wiring (`#components/theme-provider`, native window-chrome sync via `getCurrentWindow().setTheme`), BlockNote re-skinned via `shadCNComponents` + `theme` prop + retargeted `--bn-colors-*` CSS variables plus a deeper per-element chrome pass (selection outline, side menu, slash menu — Task 5) (note: `.bn-editor{padding-inline:0}` override so our own wrapper owns horizontal spacing), shiki-backed code highlighting across ~26 languages with best-effort paste language detection (`#lib/guess-language`), frimousse-based emoji picker, comments via `VaultThreadStore` (`#lib/vault-thread-store`) implementing BlockNote's open-source `ThreadStore`, table of contents via react-fluid-toc with manual heading-id injection (BlockNote doesn't render semantic heading tags), widened trailing click-to-continue zone below editor content. Verify every command/path claim against the actual shipped code before writing it (same accuracy discipline as prior docs-sync tasks — do not describe anything you haven't confirmed exists).

- [ ] **Step 2: Update `README.md`**

Mention comments and table of contents as shipped editor features; note dark mode is now toggleable (not just Phase 4's future Appearance panel).

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md README.md
git commit -m "docs: sync docs with editor UX fixes (theming, comments, TOC, highlighting)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Self-review notes

- **Task 11 added later (post-Task-10 live feedback):** after the comments feature (Task 10) landed and its `ThreadsSidebar` mitigation was reviewed, the user asked (referencing a real Notion screenshot) to reposition the comments panel from its full-width in-flow placement to a right-side rail matching Notion's floating-card treatment, and more broadly to keep studying Notion's design (color/layout/interaction) as an ongoing lens on this work — not a one-off task. Task 11 covers the concrete, scoped part (the rail); the broader "keep referencing Notion" instruction is applied opportunistically across tasks rather than as its own deliverable.
- **Coverage vs. the user's original 15-item list:** (1) window drag/traffic-light → Task 1. (2) cover full-width → Task 8. (3) code-block highlighting → Tasks 5 (user's initial wiring, superseded) + 6 (broadened + auto-detect). (4) emoji library → Task 9. (5) selection popover "add comment" + tooltip diamond → Tasks 10 + 3. (6) last-updated time → Task 8. (7) `.no-scrollbar` on the editor's scroll container → Task 4 (already applied by the user directly to `globals.css`/`.bn-editor`, verify in Task 4). (8) TOC via react-fluid-toc → Task 12. (9) block-to-block spacing → Task 4. (10) `.bn-editor` padding-inline reset → Task 4 (already applied by the user directly). (11) editor background matching app bg → Task 4 (already applied by the user directly via `.bn-editor{background-color:transparent}`). (12) light/dark parity referencing exodus → Tasks 2 + 4 (next-themes wiring + BlockNote `theme` prop + retargeted tokens). (13) overall softness vs. Notion references → Tasks 3 + 4 + 5 (shared shadCNComponents wiring reaches both native UI and BlockNote's toolbar/menu UI; Task 5 goes further into BlockNote's own hardcoded per-element chrome that CSS variables alone don't cover). (14) "+" popover viewport compression → Task 13. (15) overall popover aesthetic upgrade → Task 3.
- **Coverage vs. the mid-execution follow-up feedback (after Tasks 1-3 landed):** ugly/narrow code highlighting + more languages + auto-detect on paste → Task 6. Editor UX (trailing click-to-continue space) → Task 7. Deeper BlockNote component reskin referencing Notion → Task 5. Testing methodology (Playwright drives the web page, not the actual Tauri client) → addressed as a standalone research finding relayed to the user (`tauri-driver` has no macOS support; `@wdio/tauri-service`'s embedded provider does, but is a separate toolchain decision) rather than a plan task — introducing a new E2E runner mid-batch is a scope decision for the user, not something to fold in silently.
- **Task ordering matters:** Task 2 (next-themes) must land before Task 4 (BlockNote `theme` prop needs `useTheme`) and before Task 3 can be visually verified in dark mode. Task 3 (soften our own components) must land before Task 4 wires `shadCNComponents` at those same components, so BlockNote inherits the softened look immediately rather than needing a second pass. Task 5 (deeper chrome reskin) depends on Task 4 having landed first (it builds on top of the CSS-variable layer, going further into hardcoded per-element overrides). Task 6 (shiki broadening) replaces Task 5-era... — no: Task 6 replaces the user's _pre-Task-1_ manual shiki wiring already present in `editor.tsx`, not anything from this plan's own Task 5. Task 10 (comments) depends on nothing from 4-9 functionally but is easiest to review after the editor's shape has stabilized.
- **Reconciling in-flight manual changes:** before Task 4 runs, the working tree already contains (a) the user's own `.no-scrollbar` and `.bn-editor` (padding/background) additions to `globals.css` — Task 4's implementer must build on these, not duplicate or revert them; (b) the user's own shiki/`codeBlock` schema wiring in `editor.tsx` (superseded by Task 6) — Task 4's implementer must merge `theme`/`shadCNComponents` into the existing file, not overwrite it; (c) Tasks 1-2's already-committed work. A regression was caught and fixed during planning: an uncommitted `globals.css` edit had reverted the Phase-2 warm design tokens back to stock shadcn gray/blue (likely an unrelated shadcn-CLI regeneration) — restored before Task 4 begins.
- **Type consistency:** `Doc.threads: unknown` (Task 8) mirrors the existing `Doc.blocks: unknown[]` pattern (opaque, BlockNote-owned shape, Rust never interprets it). `VaultThreadStore`'s constructor/`onChange` shape is defined once in Task 8 and consumed by `document-page.tsx` in the same task — no cross-task drift risk since both live in one task.
- **Uncertainty flagged honestly:** Tasks 5 (shiki wiring specifics), 7 (frimousse per-item API), 8 (exact `useCreateBlockNote` comments-config key name and default-toolbar customization point), 9 (heading DOM structure), and 10 (root cause of the viewport-compression bug) all instruct the implementer to verify against the actually-installed package/runtime DOM before finalizing, rather than presenting unverified guesses as settled fact — consistent with how this project has handled uncertain third-party APIs in every prior phase.
