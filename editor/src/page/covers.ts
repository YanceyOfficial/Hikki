import { t } from '../i18n'

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

/** CSS `background` for a stored cover value, or null if it is unusable. */
export function coverBackground(cover: string | null): string | null {
  if (!cover) return null
  if (cover.startsWith('gradient:')) {
    return GRADIENTS.find((g) => `gradient:${g.id}` === cover)?.css ?? null
  }
  if (/^(hikki-editor|https?|blob|data):/.test(cover))
    return `center / cover no-repeat url("${cover.replace(/"/g, '%22')}")`
  return null
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
