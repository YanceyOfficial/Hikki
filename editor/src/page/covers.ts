/**
 * Page covers are stored as strings: `gradient:<id>` for built-in covers, or an image URL
 * (an uploaded asset, `hikki-editor://assets/…`).
 */
export type GradientCover = { id: string; label: string; css: string }

export const GRADIENTS: GradientCover[] = [
  { id: 'dusk', label: 'Dusk', css: 'linear-gradient(135deg, #f6d5f7 0%, #fbe9d7 100%)' }, // design-lint: allow (cover artwork, not UI chrome)
  { id: 'ocean', label: 'Ocean', css: 'linear-gradient(135deg, #c2e9fb 0%, #a1c4fd 100%)' }, // design-lint: allow (cover artwork, not UI chrome)
  { id: 'meadow', label: 'Meadow', css: 'linear-gradient(135deg, #d4fc79 0%, #96e6a1 100%)' }, // design-lint: allow (cover artwork, not UI chrome)
  { id: 'peach', label: 'Peach', css: 'linear-gradient(135deg, #ffecd2 0%, #fcb69f 100%)' }, // design-lint: allow (cover artwork, not UI chrome)
  { id: 'lavender', label: 'Lavender', css: 'linear-gradient(135deg, #e0c3fc 0%, #8ec5fc 100%)' }, // design-lint: allow (cover artwork, not UI chrome)
  { id: 'sand', label: 'Sand', css: 'linear-gradient(135deg, #fdfbfb 0%, #ebedee 100%)' }, // design-lint: allow (cover artwork, not UI chrome)
  { id: 'night', label: 'Night', css: 'linear-gradient(135deg, #2b5876 0%, #4e4376 100%)' }, // design-lint: allow (cover artwork, not UI chrome)
  { id: 'ember', label: 'Ember', css: 'linear-gradient(135deg, #f093fb 0%, #f5576c 100%)' }, // design-lint: allow (cover artwork, not UI chrome)
  { id: 'forest', label: 'Forest', css: 'linear-gradient(135deg, #134e5e 0%, #71b280 100%)' }, // design-lint: allow (cover artwork, not UI chrome)
  { id: 'slate', label: 'Slate', css: 'linear-gradient(135deg, #485563 0%, #29323c 100%)' }, // design-lint: allow (cover artwork, not UI chrome)
]

export const gradientCover = (id: string) => `gradient:${id}`

/** CSS `background` for a stored cover value, or null if it is unusable. */
export function coverBackground(cover: string | null): string | null {
  if (!cover) return null
  if (cover.startsWith('gradient:')) {
    return GRADIENTS.find((g) => `gradient:${g.id}` === cover)?.css ?? null
  }
  if (/^(hikki-editor|https?|blob|data):/.test(cover)) return `center / cover no-repeat url("${cover.replace(/"/g, '%22')}")`
  return null
}

export function randomGradient(random: () => number = Math.random): string {
  return gradientCover(GRADIENTS[Math.floor(random() * GRADIENTS.length)].id)
}

/** A friendly starter set for "Add icon", like Notion's random pick. */
export const STARTER_ICONS = ['📝', '📌', '💡', '🚀', '🌱', '📚', '🎯', '🧭', '🗂️', '✨', '🌊', '🍀', '🔖', '🧠', '☕️', '🎨']

export function randomIcon(random: () => number = Math.random): string {
  return STARTER_ICONS[Math.floor(random() * STARTER_ICONS.length)]
}
