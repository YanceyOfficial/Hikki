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
    sourcemap: true
  },
  test: { environment: 'happy-dom' }
})
