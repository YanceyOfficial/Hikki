import { LAYOUT } from '../generated/layout'

/**
 * The web editor's device rules, in one place (the native ones are `DeviceRules` in HikkiCore). Decided by the
 * pointer and the window, never by the device's name: a touch screen (iPhone, iPad, an iPhone Duo) has no hover, so
 * what hover reveals on a Mac is a sheet or a long press there.
 *
 * | Rule                  | Query                        | Where it applies                                     |
 * |-----------------------|------------------------------|------------------------------------------------------|
 * | TOUCH                 | primary pointer is a finger  | cover / icon pickers as bottom sheets, no hover rows |
 * | ANY_TOUCH             | any pointer is a finger      | no cover Reposition (an iPad with a trackpad too)    |
 * | FINE_POINTER          | a mouse or trackpad          | the block handle (+ / ⋮⋮) beside each block          |
 * | PHONE                 | a finger, narrow or short    | a comment thread as a bottom sheet                   |
 * | UPRIGHT_PHONE         | a finger, narrow             | no comment count badges (the passage's wash is all)  |
 */
export const TOUCH = '(pointer: coarse)'
export const ANY_TOUCH = '(any-pointer: coarse)'
export const FINE_POINTER = '(pointer: fine)'
/** Narrower than the phone breakpoint: CSS's `max-phone:` (design/tokens.json layout.breakpoint) — the same window. */
const NARROW = `(width < ${LAYOUT.breakpoint.phone}px)`
export const PHONE = `(pointer: coarse) and ${NARROW}, (pointer: coarse) and (max-height: 500px)`
export const UPRIGHT_PHONE = `(pointer: coarse) and ${NARROW}`

/** Whether a rule matches now (outside React; components use `useMediaQuery`). */
export const matches = (query: string): boolean => window.matchMedia?.(query).matches ?? false
