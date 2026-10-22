---
target: iPhone editing page
total_score: 29
max_score: 40
na_heuristics:
p0_count: 0
p1_count: 2
target_identity: 'file:/Users/yanceyleo/Code/hikki/Hikki/Sources/PageScreen.swift'
target_fingerprint: 'sha256:19e4340c42bf787b4bdd6a8328a1fce5aed209885c6013801dd1750f15d04a68'
target_path: /Users/yanceyleo/Code/hikki/Hikki/Sources/PageScreen.swift
timestamp: 2026-10-22T08-34-19Z
slug: hikki-sources-pagescreen-swift
---

**Method: design review only (detector not applicable, native platform)**
Target: the iPhone editing page — `Hikki/Sources/PageScreen.swift`, with its keyboard bar (`KeyboardToolbar.swift`, HikkiUI `KeyboardPanels` / `FloatingActionBar`) and the web page inside it. Mode: Operate. Evidence: iPhone 17 simulator (iOS 27) light, dark and XXXL Dynamic Type; keyboard bar, panels, outline sheet and ⋯ flows from UI-test attachments; the user's device screenshots (2026-10-22).

## Design Health Score

| #         | Heuristic                       | Score     | Key Issue                                                                                   |
| --------- | ------------------------------- | --------- | ------------------------------------------------------------------------------------------- |
| 1         | Visibility of System Status     | 3         | Saves are silent by design; nothing on the page says where it lives (folder / iCloud state) |
| 2         | Match System / Real World       | 4         | Notion's vocabulary and gestures; plain copy                                                |
| 3         | User Control and Freedom        | 3         | Undo on the bar, swipe-down closes panels; pinch zoom was possible until today              |
| 4         | Consistency and Standards       | 3         | Two icon families on one screen: SF Symbols in the chrome, Phosphor inside the page         |
| 5         | Error Prevention                | 3         | Lock, AI review before anything lands; no confirmation on ⋯ → Delete block (Undo exists)    |
| 6         | Recognition Rather Than Recall  | 3         | Icon-only bar (labelled for VoiceOver); the second half of the bar is behind a scroll       |
| 7         | Flexibility and Efficiency      | 3         | Shortcut registry, "/" and "@", Turn into                                                   |
| 8         | Aesthetic and Minimalist Design | 3         | Quiet after the keyboard-bar pass; the Turn-into grid shows 14 tiles at once                |
| 9         | Error Recovery                  | 3         | Codes + toasts + Copy details                                                               |
| 10        | Help and Documentation          | 1         | No in-app help or hints beyond placeholders                                                 |
| **Total** |                                 | **29/40** | **Good**                                                                                    |

## Design Specificity Verdict

LLM assessment: coherent and native (Liquid Glass chrome, system sheets, the page under the bars, the tone reserved for the primary action and "on" states), but at a glance Notion's iOS page re-skinned: nothing on the surface carries what only Hikki can say — that the page is a file the user owns, or that the AI runs on their key.

Deterministic scan: not applicable (native platform).

## Overall Impression

A quiet, competent editor screen. The biggest opportunity is accessibility: the page ignores the system text size entirely and the bar's controls are below the touch-target floor. Then let the surface say what Hikki is.

## What's Working

- The chrome is iOS 26, not a web port: glass back / star / ⋯ groups, the page bleeding under them, outline and ⋯ as sheets with detents, native composers over the keyboard.
- One tone, used sparingly: the pencil, the active tool, the current Turn-into tile.
- CJK and Latin set well together at every size tested; dark mode is first-class.

## Priority Issues

1. [P1] Dynamic Type is ignored on both halves of the screen. Web: `-webkit-text-size-adjust: 100%`, 16 px base, no scale bridge; native: `Font.hk` = `Font.system(size:)`. Fix: `Font.hk` relative to a text style; a `setTextScale` bridge from `UIContentSizeCategory` (on change too) setting `html { font-size }`, panels in rem. Command: $impeccable adapt.
2. [P1] Touch targets under 44 pt: keyboard bar tools 40 × 36 with no gap, the panel's marks row the same, nav-bar star/⋯ 42 × 36 / 38 × 36. Fix: 44 × 44 hit areas for the `quiet` style, 2 pt between; the nav group's full 44. Command: $impeccable adapt.
3. [P2] Floating bar and keyboard bar overlap with a hardware keyboard (accessory-only keyboard: `keyboardShown` stays false). Fix: hide the floating bar on the accessory bar's presence, not on `keyboardWillShow`. Command: $impeccable harden.
4. [P2] Two icon languages on one screen (SF Symbols in chrome and bar, Phosphor in the page). Fix: one decision — SF-aligned glyphs for page surfaces beside native chrome, or Phosphor's stroke matched to SF regular at 17 pt. Command: $impeccable polish.
5. [P2] The surface doesn't say what Hikki is: no file/sync state, no sign of whose AI key. Fix: sync state and "AI: your key" among the ⋯ sheet's facts; a small folder/cloud state in its header. Command: $impeccable clarify.

## Persona Red Flags

- Sam (VoiceOver / large text): page text never scales; 36 pt-tall bar targets; muted glyphs near the 3:1 icon floor on a busy cover.
- Casey (one-handed): floating bar in the thumb zone ✓; ⋯ (export, move, history) top-right; the bar's second half needs a scroll with only a fade as cue.
- Alex (iPad + hardware keyboard): the overlap in issue 3 every time the accessory bar appears.

## Minor Observations

- Turn-into grid (14 tiles) and the bar (9 + 7 scrolled) are the two decision points over four options; the grid could lead with the five common kinds.
- "Ask about this page" reads as a field but is a button to a sheet (Notion's pattern); the prompt could invite ("Ask about this page…").
- A new page shows "Add icon · Add cover" and no body placeholder hint in the screenshots — verify on an empty page.
- The outline sheet is one text size for all levels; a weight step per level would help scanning.
- Reduce Motion: the shimmer honours it; check the `.move(edge:)` transitions of the floating bar and composers.

## Questions to Consider

- What if the only brand element were the file itself — "in iCloud · synced 2 min ago" that no hosted notebook can truthfully show?
- Sixteen tools on the bar, or eight plus a labelled sheet for the rest?
- If the page followed Dynamic Type, is the 708 px column still right at XXXL?
