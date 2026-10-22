---
target: website homepage
total_score: 20
max_score: 32
na_heuristics: 7,10
p0_count: 2
p1_count: 3
target_identity: 'file:/Users/yanceyleo/Code/hikki/apps/website/src/routes/index.tsx'
target_fingerprint: 'sha256:45a75eafc4c0a3bd28244d5c5847f3925183c13d7fb0e6ebc519d02d880d9378'
target_path: /Users/yanceyleo/Code/hikki/apps/website/src/routes/index.tsx
timestamp: 2026-10-22T17-14-38Z
slug: apps-website-src-routes-index-tsx
closed: true
---

**Method: dual-agent (A: design review · B: detector + browser), run in sequence — one shared browser tab**
Target: the website's homepage — `apps/website/src/routes/index.tsx` with `__root.tsx`, `components/`, `styles.css`. Mode: Persuade. Judged on the site's own Mondrian world (the root DESIGN.md is the app's). Evidence: 1280 × 900 and 390 × 844, light and dark; in-page measurements; detector over `apps/website/src` and its overlay at 1920 px.

## Design Health Score

| #         | Heuristic                       | Score     | Key Issue                                                                                                             |
| --------- | ------------------------------- | --------- | --------------------------------------------------------------------------------------------------------------------- |
| 1         | Visibility of System Status     | 2         | "Coming to the App Store" has no date and no next step; no "you are here"; 12.6 phone screens with no sense of length |
| 2         | Match System / Real World       | 3         | Plain copy, but "native SwiftUI around a Tiptap editor" and "AI on your key" in the first 60 words                    |
| 3         | User Control and Freedom        | 3         | Theme switch, clean anchors; no way back up a 10,644 px phone page; review shots can't be enlarged                    |
| 4         | Consistency and Standards       | 2         | The CTA is an `<a>` with no href, aria-disabled, not focusable, hover cancelled; h1 43.5 px under h2s of 51–64 px     |
| 5         | Error Prevention                | 2         | The only action yields the only error: a click on the CTA does nothing, twice                                         |
| 6         | Recognition Rather Than Recall  | 3         | Claims beside real screenshots; the three review shots render with ~6 px / ~2 px text                                 |
| 7         | Flexibility and Efficiency      | n/a       | One linear read                                                                                                       |
| 8         | Aesthetic and Minimalist Design | 3         | Disciplined grid; sync claimed three times, a 55-word hero paragraph at 37 cpl, five empty cells                      |
| 9         | Error Recovery                  | 2         | The pre-launch state offers no recovery: no date, no notify-me, no requirements, no privacy link                      |
| 10        | Help and Documentation          | n/a       | Pre-launch landing page                                                                                               |
| **Total** |                                 | **20/32** | **Acceptable**                                                                                                        |

## Design Specificity Verdict

LLM assessment: specific where it counts — 筆記 with its ひっき reading as the brand gesture, the folder listing as the storage model, the editor's real AI menu, eleven honest screenshot pairs with dark twins. The Mondrian grid is general-purpose but earned (cells as blocks, Hikki's red). Failures are composition, hierarchy and the download moment, not identity.

Deterministic scan: 18 CLI findings measured against the app's root DESIGN.md (the site has none) — mostly reference mismatches. Survives: a site-local 15 px size used ten times with no name; `text-[14px]` where `text-sm` exists; /lab's 10 px credit and Newsreader face (not the homepage). Both methods agree on: the furigana sample's `rt` at 8.64 px (3.17:1 on dark) and feature copy on red at opacity-80 = 3.7:1. The overlay added five one-word last lines (stragglers) at 1920 px.

## Overall Impression

The page knows what Hikki is and shows it with real material — then gives the visitor nothing to do. Good first viewport on a Mac; on a phone three cells of chrome, an unreadable kanji and a dead button before any sentence. The biggest opportunity is the download moment.

## What's Working

- The hero word: 筆記 in a Mincho with ひっき in red as jukugo ruby, the one motion on the page, glossed at the hero's foot.
- Honest screenshots with real dark twins carrying the PRODUCT.md user's life; the right twin per theme.
- The grid holds: 12 columns to 1 with no broken rules, no overflow at 390 px, primaries passing contrast, a visible focus ring.

## Priority Issues

1. [P0] The primary CTA is a dead end dressed as a button (`AppStoreButton`: `<a class="button" aria-disabled>` with no href, not focusable, hover cancelled, shown twice). Fix: status as a status line, not a button; one real action today (notify-me field via a BFF endpoint, or mailto/RSS/release notes) with platforms + OS versions, price, a privacy link beside it. Command: $impeccable clarify.
2. [P0] The phone's first screen has no headline and no product (header 351 px of chrome; h1 at y = 892, screenshot at y = 1,321 on 844). Fix: one 64–72 px header row below md, theme switch to the footer, hero order ruby → h1 → short paragraph → screenshot → facts, 筆記 ~72 px. Command: $impeccable layout.
3. [P1] Header breaks and hero facts vanish at 1024–1535 px (trailing cell 308 px vs 390 px of controls; `.hero-facts` lg:hidden 2xl:grid). Fix: `lg:grid-cols-[3fr_5fr_4fr]` or a short header CTA; facts at lg with a two-sentence paragraph. Command: $impeccable layout.
4. [P1] Type hierarchy inverted and small type illegible: h1 43.5 < h2 51–64; `rt` 8.64 px; review shots unreadable; opacity-80 on red 3.7:1; stragglers; an unnamed 15 px step. Fix: h1 to the AI h2's clamp, h2s a step below; kanji sample ≥ 56 px (rt ≥ 13 px); crop review shots to the panel, ≥ 90 px on phone; explicit colours on coloured cells; `text-wrap: pretty`, 55–65 cpl; name 15 px or drop it. Command: $impeccable typeset.
5. [P1] The page ends on a promise ("Editing together is on its way") beside the dead CTA, then a footer with no privacy, contact or release-notes link. Fix: close on claim one as the reason to download; roadmap note for collaboration; three footer links. Command: $impeccable distill.

## Persona Red Flags

- Jordan: a kanji he can't read as the first word; developer words; nothing on price or OS; "kanji/pinyin" reads as learners-only.
- Riley: dead CTA, unfocusable; dark mode turns the wordmark's sparkle cyan (filter: invert), frames vanish, lines 1.2:1; header wraps and facts disappear at laptop widths; no privacy policy.
- Casey: no headline on screen one; 12.6 screens; 23 px nav links ("AI" 15 × 23); 14 chips that look like buttons; 99 px review shots; collapsed cells as 20 px black bands; the CTA at y = 10,352.

## Minor Observations

- Dark mode: inverted wordmark, near-invisible cell lines, vanished screenshot frames.
- Hero `<ruby>` lacks `lang="ja"` (the feature sample has it).
- Repetition: sync three times, "both versions" twice, a 24 px line restating its h2.
- The `<pre>` folder listing is the strongest proof of claim one.
- `og:image` is WebP only.
- No `apps/website/DESIGN.md`: tools measure the site against the app's — `$impeccable document` from `apps/website` would fix the reference.

## Questions to Consider

- What should a visitor who can't download today leave with — a URL, an address to be told at, or a feeling?
- Language-study user first (the kanji leads) or every note-keeper (the English headline leads)?
- Why does the page end on the feature that doesn't exist?
