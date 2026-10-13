import { fileURLToPath } from 'node:url'

import tailwindcss from '@tailwindcss/vite'
import react from '@vitejs/plugin-react'
import { defineConfig } from 'vitest/config'

export default defineConfig({
  // Relative URLs: the bundle is served from the app's custom scheme (hikki-editor://app/).
  base: './',
  plugins: [react(), tailwindcss()],
  resolve: { alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) } },
  build: {
    outDir: '../Hikki/Resources/Editor',
    emptyOutDir: true,
    target: 'safari18',
    sourcemap: true,
    // One bundle on purpose: it loads from the app bundle (custom scheme, no network) once per window, and
    // measured cold start is ~310ms WebView-to-ready of which ~95ms is our JS. Splitting Tiptap/React buys little.
    chunkSizeWarningLimit: 1500
  },
  test: {
    environment: 'happy-dom',
    setupFiles: ['./test/setup.ts'],
    // An <iframe src> (embeds) would make happy-dom fetch the page: no network in tests.
    environmentOptions: { happyDOM: { settings: { disableIframePageLoading: true } } }
  }
})
