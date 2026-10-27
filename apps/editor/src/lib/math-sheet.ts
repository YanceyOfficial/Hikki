/** A formula as the native sheet is asked to edit it (a phone, `setNativeMath`). */
export type MathSheetRequest = { latex: string; kind: 'inline' | 'block' }

/** What the native sheet does to the formula: its text as typed (a live preview in the page), Done, or Cancel. */
export type MathSheetHandlers = {
  onPreview: (latex: string) => void
  onDone: (latex: string) => void
  onCancel: () => void
}

type Opener = (request: MathSheetRequest, handlers: MathSheetHandlers) => boolean

let opener: Opener | null = null

/** The bridge says who edits a formula: a native sheet (a phone, `setNativeMath`), or null for the page's panel. */
export function setMathSheetOpener(next: Opener | null): void {
  opener = next
}

/** Asks for the native formula sheet; false means the caller shows its own panel. */
export function openNativeMathSheet(
  request: MathSheetRequest,
  handlers: MathSheetHandlers
): boolean {
  return opener?.(request, handlers) ?? false
}
