import { fileURLToPath } from 'node:url'

import tailwindcss from '@tailwindcss/vite'
import react from '@vitejs/plugin-react'
import type { Plugin } from 'vite'
import { defineConfig } from 'vitest/config'

/**
 * KaTeX's stylesheet offers every font as woff2, woff and ttf; WebKit takes woff2, so only those are kept (the other
 * two formats were ~0.5 MB the app shipped and never loaded).
 */
function katexWoff2Only(): Plugin {
  return {
    name: 'katex-woff2-only',
    enforce: 'pre',
    transform(code, id) {
      if (!id.includes('katex') || !id.split('?')[0].endsWith('.css')) return null
      return code.replaceAll(/,url\([^)]+\.(?:woff|ttf)\) format\("(?:woff|truetype)"\)/gu, '')
    }
  }
}

export default defineConfig({
  // Relative URLs: the bundle is served from the app's custom scheme (hikki-editor://app/).
  base: './',
  plugins: [katexWoff2Only(), react(), tailwindcss()],
  resolve: { alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) } },
  build: {
    outDir: '../Hikki/Resources/Editor',
    emptyOutDir: true,
    target: 'safari18',
    // No source map in the app: it was 8 MB of the bundle and nothing reads it (dev builds have their own).
    sourcemap: false,
    // One bundle on purpose: it loads from the app bundle (custom scheme, no network) once per window, and
    // our JS evaluates in ~110 ms (WebKit, 2026-10-17). Splitting Tiptap/React buys little.
    chunkSizeWarningLimit: 1500
  },
  test: {
    environment: 'happy-dom',
    setupFiles: ['./test/setup.ts'],
    // An <iframe src> (embeds) would make happy-dom fetch the page: no network in tests.
    environmentOptions: { happyDOM: { settings: { disableIframePageLoading: true } } }
  }
})
