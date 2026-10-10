import { defineConfig } from 'vitest/config'

export default defineConfig({
  // Relative URLs: the bundle is served from the app's custom scheme (hikki-editor://app/).
  base: './',
  build: {
    outDir: '../Hikki/Resources/Editor',
    emptyOutDir: true,
    target: 'safari18',
    sourcemap: true,
  },
  test: { environment: 'happy-dom' },
})
