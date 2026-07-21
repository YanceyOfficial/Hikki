import {
  sidebarHeaderNeedsInset,
  titleBarNeedsInset
} from '#lib/traffic-light-gate'

const sidebarStates = ['expanded', 'collapsed'] as const
const bools = [false, true]

test('both are false whenever trafficLight is false, regardless of isMobile/state', () => {
  for (const isMobile of bools) {
    for (const state of sidebarStates) {
      expect(titleBarNeedsInset(false, isMobile, state)).toBe(false)
      expect(sidebarHeaderNeedsInset(false, isMobile, state)).toBe(false)
    }
  }
})

test('exactly one of titleBarNeedsInset/sidebarHeaderNeedsInset is true for every isMobile/state combination when trafficLight is true', () => {
  for (const isMobile of bools) {
    for (const state of sidebarStates) {
      const titleBar = titleBarNeedsInset(true, isMobile, state)
      const sidebarHeader = sidebarHeaderNeedsInset(true, isMobile, state)
      expect(titleBar !== sidebarHeader).toBe(true)
    }
  }
})

test('titleBarNeedsInset is true on mobile regardless of sidebar state', () => {
  expect(titleBarNeedsInset(true, true, 'expanded')).toBe(true)
  expect(titleBarNeedsInset(true, true, 'collapsed')).toBe(true)
})

test('titleBarNeedsInset is true on desktop only when the sidebar is collapsed', () => {
  expect(titleBarNeedsInset(true, false, 'collapsed')).toBe(true)
  expect(titleBarNeedsInset(true, false, 'expanded')).toBe(false)
})

test('sidebarHeaderNeedsInset is true only on desktop with the sidebar expanded', () => {
  expect(sidebarHeaderNeedsInset(true, false, 'expanded')).toBe(true)
  expect(sidebarHeaderNeedsInset(true, false, 'collapsed')).toBe(false)
  expect(sidebarHeaderNeedsInset(true, true, 'expanded')).toBe(false)
  expect(sidebarHeaderNeedsInset(true, true, 'collapsed')).toBe(false)
})
