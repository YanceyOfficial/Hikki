import type { DateMentionAttrs } from './dates'

/** What the native date sheet can change on a chip; null removes it. */
export type DateSheetChange = Pick<DateMentionAttrs, 'date' | 'time' | 'remind' | 'done'> | null

type Opener = (attrs: DateMentionAttrs, onChange: (change: DateSheetChange) => void) => boolean

let opener: Opener | null = null

/** The bridge says who edits a date: a native sheet (a phone, `setNativeDates`), or null for the page's popover. */
export function setDateSheetOpener(next: Opener | null): void {
  opener = next
}

/** Asks for the native date sheet; false means the caller shows its own popover. */
export function openNativeDateSheet(
  attrs: DateMentionAttrs,
  onChange: (change: DateSheetChange) => void
): boolean {
  return opener?.(attrs, onChange) ?? false
}
