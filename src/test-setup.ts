import '@testing-library/jest-dom/vitest'

// jsdom doesn't implement matchMedia. shadcn's SidebarProvider (via
// useIsMobile) calls it on mount, so any test rendering SidebarProvider
// needs this stub.
if (typeof window !== 'undefined' && !window.matchMedia) {
  window.matchMedia = (query: string) => ({
    matches: false,
    media: query,
    onchange: null,
    addListener: () => {},
    removeListener: () => {},
    addEventListener: () => {},
    removeEventListener: () => {},
    dispatchEvent: () => false
  })
}
