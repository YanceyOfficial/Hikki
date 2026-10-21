import type { PaletteColor } from '../extensions/colors'

/** What a native icon sheet is opened for: the page's icon, or a callout's (with its background colour). */
export type IconSheetRequest =
  | { kind: 'page'; icon: string | null }
  | { kind: 'callout'; icon: string; color: PaletteColor | null }

/** What the sheet's picks do: a new icon (null: Remove), a callout's colour. */
export type IconSheetHandlers = {
  onIcon: (icon: string | null) => void
  onColor?: (color: PaletteColor | null) => void
}

type Opener = (request: IconSheetRequest, handlers: IconSheetHandlers) => boolean

let opener: Opener | null = null

/** The bridge says who draws icon sheets: a native opener (a phone, `setNativeIcons`), or null for the page's own. */
export function setIconSheetOpener(next: Opener | null): void {
  opener = next
}

/** Asks for the native icon sheet; false means the caller shows its own picker. */
export function openNativeIconSheet(
  request: IconSheetRequest,
  handlers: IconSheetHandlers
): boolean {
  return opener?.(request, handlers) ?? false
}
