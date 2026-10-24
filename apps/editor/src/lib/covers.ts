import { t } from '../core/i18n'

/**
 * Page covers are stored as strings: `gradient:<id>` for built-in covers, or an image URL
 * (an uploaded asset, `hikki-editor://assets/…`).
 */
export type GradientCover = { id: string; label: () => string; css: string }

/** The built-in covers, in the picker's order, with their names: their colours are design tokens (`cover` in
 *  design/tokens.json → `--cover-<id>`; the native side's `CoverGradient`). */
const GRADIENT_LABELS = {
  dusk: () => t('cover.gradients.dusk'),
  ocean: () => t('cover.gradients.ocean'),
  meadow: () => t('cover.gradients.meadow'),
  peach: () => t('cover.gradients.peach'),
  lavender: () => t('cover.gradients.lavender'),
  sand: () => t('cover.gradients.sand'),
  night: () => t('cover.gradients.night'),
  ember: () => t('cover.gradients.ember'),
  forest: () => t('cover.gradients.forest'),
  slate: () => t('cover.gradients.slate')
} satisfies Record<string, () => string>

export const GRADIENTS: GradientCover[] = Object.entries(GRADIENT_LABELS).map(([id, label]) => ({
  id,
  label,
  css: `var(--cover-${id})`
}))

export const gradientCover = (id: string) => `gradient:${id}`

const IMAGE_COVER = /^(hikki-editor|https?|blob|data):/u
/** An image cover's vertical position rides along as a fragment: `…#y=35` (0 = top of the image, 100 = bottom). */
const POSITION = /#y=(\d{1,3})$/u

/** A cover that is a picture (uploaded, linked, Unsplash), as opposed to a gradient. */
export const isImageCover = (cover: string | null): cover is string =>
  !!cover && IMAGE_COVER.test(cover)

/** Where the image sits vertically, in percent (50 = centred, the default). */
export function coverPosition(cover: string | null): number {
  const match = cover ? POSITION.exec(cover) : null
  return match ? Math.min(100, Number(match[1])) : 50
}

/** The same cover at another vertical position (gradients have none and come back unchanged). */
export function withCoverPosition(cover: string, y: number): string {
  if (!isImageCover(cover)) return cover
  const base = cover.replace(POSITION, '')
  const rounded = Math.round(Math.min(100, Math.max(0, y)))
  return rounded === 50 ? base : `${base}#y=${rounded}`
}

/** The image to load for a cover (its URL without our position fragment), or null for a gradient. */
export function coverImageURL(cover: string | null): string | null {
  return isImageCover(cover) ? cover.replace(POSITION, '') : null
}

/** An image cover's picture and vertical position (0–100), or null for a gradient or nothing. */
export function coverImage(cover: string | null): { src: string; y: number } | null {
  const src = coverImageURL(cover)
  return src ? { src, y: coverPosition(cover) } : null
}

/** CSS `background` for a stored cover value, or null if it is unusable. */
export function coverBackground(cover: string | null): string | null {
  if (!cover) return null
  if (cover.startsWith('gradient:')) {
    return GRADIENTS.find((g) => `gradient:${g.id}` === cover)?.css ?? null
  }
  if (isImageCover(cover))
    return `50% ${coverPosition(cover)}% / cover no-repeat url("${cover.replaceAll('"', '%22')}")`
  return null
}

/** When neither the image's overflow nor the cover's height is known, this many pixels of drag span the range. */
const FALLBACK_EXTENT = 200

/**
 * The position after dragging the image by `dy` pixels (down is positive, which reveals more of the top):
 * one pixel of drag moves the image one pixel, so the whole range spans the image's overflow beyond the
 * cover — or the cover's height when the overflow isn't known, or a fixed stretch when nothing is.
 */
export function repositionedCover(
  y: number,
  dy: number,
  coverHeight: number,
  imageOverflow: number | null
): number {
  const extent =
    imageOverflow !== null && imageOverflow > 0
      ? imageOverflow
      : Math.max(coverHeight, FALLBACK_EXTENT)
  return Math.min(100, Math.max(0, y - (dy / extent) * 100))
}

export function randomGradient(random: () => number = Math.random): string {
  return gradientCover(GRADIENTS[Math.floor(random() * GRADIENTS.length)].id)
}

/** Blocks of single-code-point pictographs a random icon is drawn from (Notion's "Add icon" picks any emoji). */
const EMOJI_BLOCKS: [number, number][] = [
  [0x1f300, 0x1f64f], // symbols & pictographs, emoticons
  [0x1f680, 0x1f6ff], // transport & map
  [0x1f900, 0x1f9ff], // supplemental symbols & pictographs
  [0x1fa70, 0x1faff] // symbols & pictographs extended-A
]
const EMOJI_SPAN = EMOJI_BLOCKS.reduce((sum, [from, to]) => sum + to - from + 1, 0)
/** Drawn as an emoji on its own: not a skin-tone modifier, not a gap in a block (unassigned in this engine's Unicode). */
const DRAWN_ALONE = /^(?!\p{Emoji_Modifier})\p{Emoji_Presentation}$/u

/**
 * A random emoji for "Add icon": a code point from the emoji blocks, drawn again until it is one the system shows as
 * an emoji on its own (gaps and modifiers skipped) — any emoji, not a fixed list.
 */
export function randomIcon(random: () => number = Math.random): string {
  for (let attempt = 0; attempt < 64; attempt++) {
    let offset = Math.floor(random() * EMOJI_SPAN)
    for (const [from, to] of EMOJI_BLOCKS) {
      const size = to - from + 1
      if (offset < size) {
        const emoji = String.fromCodePoint(from + offset)
        if (DRAWN_ALONE.test(emoji)) return emoji
        break
      }
      offset -= size
    }
  }
  return '📝'
}
