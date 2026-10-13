# App icon

The mark is **Hi✦**: a geometric lowercase h with the AI sparkle where the dot of an "i" would sit, so h + ✦
reads as "hi" (and ひ, the first syllable of hikki). Brand colour **Kurenai** (紅, `#D7003A`). The wordmark and
lockups live in `design/logo/`.

`design/icon/hi-star/` holds the layers the way Icon Composer wants them: one flat SVG per layer on a
1024 × 1024 canvas, numbered in Z order. Drop them in together and Liquid Glass (specular, shadow, translucency) is
applied per layer and across the stack; the background is set in Icon Composer, never in a layer.

| Layer                    | Fill                | What it is                                                                 |
| ------------------------ | ------------------- | -------------------------------------------------------------------------- |
| `00-background.svg`      | `#FF6478 → #D7003A` | the full-canvas background gradient (the only layer with a gradient)       |
| `00-background-dark.svg` | `#C2324A → #86001F` | the same for the Dark appearance (hide one per appearance, as exodus does) |
| `01-stem.svg`            | `#FFFFFF`           | the stem, a 140 pt round-capped stroke at x 312, y 250 → 790               |
| `02-arch.svg`            | `#FFD6DB`           | the arch and right leg, laid over the stem (pale so the overlap shows)     |
| `03-star.svg`            | `#FFFFFF`           | the sparkles: R 116 at (764, 300) and R 44 at (866, 432)                   |

`preview.svg` is the flat composite with a rounded mask (for looking, not for import); `menubar.svg` is the
18 × 18 pt template glyph for the macOS menu bar.

`light.icon` and `dark.icon` are the Icon Composer documents built from these layers (one per background), and
`Icon-iOS-{Default,Dark}-1024@1x.png` their 1024 pt renders. The app uses the merged document
`Hikki/Resources/AppIcon.icon` (one group, both backgrounds, each hidden in the other appearance — the exodus
pattern), referenced from `Project.swift` with `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`. After changing
the layers: regenerate, re-import in Icon Composer, then copy `Assets/` and merge `icon.json` again.

`node design/icon/generate.mjs` rewrites `hi-star/` from the geometry in `generate.mjs` (the `sparkle()` helper is
shared with the logo). The directions explored on the way (Ensō✦, Note✦, a white-ground Hi✦, the abstract and the
figurative sets) stay in the script's `alternatives`; `--all` writes their folders too, and
`node design/icon/build-concepts-page.mjs <out.html>` builds a comparison page (chosen mark, Dock sizes on light and
dark, layers in drop order, menu bar mock, background alternatives, the alternatives collapsed).

## Icon Composer

1. File → New, keep iOS/iPadOS/macOS (squares); the canvas is 1024.
2. Select `00-background.svg`, `01-stem.svg`, `02-arch.svg`, `03-star.svg` and drop them on the canvas together —
   the numbering keeps the order (00 at the back). Each lands as its own layer in one group. Add
   `00-background-dark.svg` next to the light one and hide each per appearance (Light hides the dark file, Dark
   hides the light one), the way exodus does.
3. Alternatively leave the background files out and set Background → Fill → Gradient `#FF6478 → #D7003A` in the
   inspector.
4. Group: start from Specular on, Shadow neutral ≈ 0.5, Translucency ≈ 0.3 (what exodus ships). Put the star in its
   own group if it wants more specular than the h.
5. Check Dark, Clear and Tinted. Tinted/Mono derives everything from layer luminance; all three layers are light,
   so the h and the star keep reading as one mark.
6. Save into `design/icon/hi-star/` and merge into `Hikki/Resources/AppIcon.icon` (already wired up in
   `Project.swift`).

Layer rules (Apple): flat fills only — no gradients, shadows, blur or opacity inside a layer; text as outlines;
export at the full canvas size so layers align when dropped in.

## Menu bar

`menubar.svg` is a template image: black shapes, 18 × 18 pt, 1.8 pt strokes (the h) and a filled sparkle. It is
wired up as `Hikki/Resources/Assets.xcassets` → MenuBarIcon (vector, template rendering) and shown by the menu bar
extra (`Hikki/Sources/MenuBarExtra.swift`, Settings → General → Menu bar); the system tints it for light and dark
menu bars. After changing the glyph, copy the SVG into the image set again.
