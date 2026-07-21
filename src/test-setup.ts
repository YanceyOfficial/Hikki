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

// jsdom doesn't implement ResizeObserver. frimousse's emoji picker
// (page-header.tsx) constructs one synchronously on mount to measure its
// virtualized list, so any test rendering it without this stub would throw
// `ReferenceError: ResizeObserver is not defined`.
if (typeof window !== 'undefined' && !window.ResizeObserver) {
  window.ResizeObserver = class {
    observe() {}
    unobserve() {}
    disconnect() {}
  }
}
