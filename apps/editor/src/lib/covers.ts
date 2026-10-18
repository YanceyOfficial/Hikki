import { t } from '../core/i18n'

// design-lint: allow-file — cover artwork (gradients), not UI chrome colors.

/**
 * Page covers are stored as strings: `gradient:<id>` for built-in covers, or an image URL
 * (an uploaded asset, `hikki-editor://assets/…`).
 */
export type GradientCover = { id: string; label: () => string; css: string }

export const GRADIENTS: GradientCover[] = [
  {
    id: 'dusk',
    label: () => t('cover.gradients.dusk'),
    css: 'linear-gradient(135deg, #f6d5f7 0%, #fbe9d7 100%)'
  },
  {
    id: 'ocean',
    label: () => t('cover.gradients.ocean'),
    css: 'linear-gradient(135deg, #c2e9fb 0%, #a1c4fd 100%)'
  },
  {
    id: 'meadow',
    label: () => t('cover.gradients.meadow'),
    css: 'linear-gradient(135deg, #d4fc79 0%, #96e6a1 100%)'
  },
  {
    id: 'peach',
    label: () => t('cover.gradients.peach'),
    css: 'linear-gradient(135deg, #ffecd2 0%, #fcb69f 100%)'
  },
  {
    id: 'lavender',
    label: () => t('cover.gradients.lavender'),
    css: 'linear-gradient(135deg, #e0c3fc 0%, #8ec5fc 100%)'
  },
  {
    id: 'sand',
    label: () => t('cover.gradients.sand'),
    css: 'linear-gradient(135deg, #fdfbfb 0%, #ebedee 100%)'
  },
  {
    id: 'night',
    label: () => t('cover.gradients.night'),
    css: 'linear-gradient(135deg, #2b5876 0%, #4e4376 100%)'
  },
  {
    id: 'ember',
    label: () => t('cover.gradients.ember'),
    css: 'linear-gradient(135deg, #f093fb 0%, #f5576c 100%)'
  },
  {
    id: 'forest',
    label: () => t('cover.gradients.forest'),
    css: 'linear-gradient(135deg, #134e5e 0%, #71b280 100%)'
  },
  {
    id: 'slate',
    label: () => t('cover.gradients.slate'),
    css: 'linear-gradient(135deg, #485563 0%, #29323c 100%)'
  }
]

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

/** A friendly starter set for "Add icon", like Notion's random pick. */
export const STARTER_ICONS = [
  '📝',
  '📌',
  '💡',
  '🚀',
  '🌱',
  '📚',
  '🎯',
  '🧭',
  '🗂️',
  '✨',
  '🌊',
  '🍀',
  '🔖',
  '🧠',
  '☕️',
  '🎨'
]

export function randomIcon(random: () => number = Math.random): string {
  return STARTER_ICONS[Math.floor(random() * STARTER_ICONS.length)]
}
