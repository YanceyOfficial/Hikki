import babel from '@rolldown/plugin-babel'
import tailwindcss from '@tailwindcss/vite'
import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// @ts-expect-error process is a nodejs global
const host = process.env.TAURI_DEV_HOST

// https://vite.dev/config/
export default defineConfig(({ mode }) => ({
  plugins: [
    react(),
    // Strip data-testid attributes from production bundles only; dev/test builds keep them.
    // @vitejs/plugin-react transforms JSX via oxc (no babel hook), so the removal runs as a
    // separate, `enforce: 'pre'` babel pass ahead of the oxc JSX transform.
    mode === 'production'
      ? babel({
          plugins: [
            ['react-remove-properties', { properties: ['data-testid'] }]
          ]
        })
      : null,
    tailwindcss()
  ],

  // Vite options tailored for Tauri development and only applied in `tauri dev` or `tauri build`
  //
  // 1. prevent Vite from obscuring rust errors
  clearScreen: false,
  // 2. tauri expects a fixed port, fail if that port is not available
  server: {
    port: 1420,
    strictPort: true,
    host: host || false,
    hmr: host
      ? {
          protocol: 'ws',
          host,
          port: 1421
        }
      : undefined,
    watch: {
      // 3. tell Vite to ignore watching `src-tauri`
      ignored: ['**/src-tauri/**']
    }
  }
}))
