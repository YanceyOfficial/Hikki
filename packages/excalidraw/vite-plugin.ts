import { readdirSync, readFileSync, statSync } from 'node:fs'
import { createRequire } from 'node:module'
import { dirname, join, relative, sep } from 'node:path'

import type { Plugin } from 'vite'

/** Where the fonts are served and bundled, under the editor's base (`setDrawingAssetPath` points Excalidraw here). */
export const DRAWING_ASSETS = 'excalidraw/'

/** Excalidraw's own `dist/prod` folder (its fonts live in `fonts/<family>/`). */
function excalidrawDist(): string {
  const require = createRequire(import.meta.url)
  return dirname(require.resolve('@excalidraw/excalidraw'))
}

function filesUnder(folder: string): string[] {
  return readdirSync(folder).flatMap((name) => {
    const path = join(folder, name)
    return statSync(path).isDirectory() ? filesUnder(path) : [path]
  })
}

/**
 * Excalidraw's fallback for fonts it can't find where `EXCALIDRAW_ASSET_PATH` says: a CDN (esm.sh). The app has no
 * network to count on and sends nothing out by itself, so the fallback becomes the bundled copy as well.
 */
const CDN_FALLBACK = /`https:\/\/esm\.sh\/\$\{[^`]*?`[^`]*`[^`]*?\}\/dist\/prod\/`/gu
export const LOCAL_FALLBACK = `new URL("./${DRAWING_ASSETS}", document.baseURI).href`

export function withoutCDNFallback(code: string): string {
  return code.replaceAll(CDN_FALLBACK, LOCAL_FALLBACK)
}

/**
 * Every font Excalidraw draws with — the hand-drawn CJK one (Xiaolai, ~12 MB) included — copied into the bundle at
 * `excalidraw/fonts/…` (served from there by the dev server), and Excalidraw's CDN fallback taken out of its code.
 */
export function excalidrawAssets(): Plugin {
  const fonts = join(excalidrawDist(), 'fonts')
  return {
    name: 'hikki-excalidraw-assets',
    enforce: 'pre',
    transform(code, id) {
      if (!id.includes('@excalidraw') || !code.includes('esm.sh')) return null
      return { code: withoutCDNFallback(code), map: null }
    },
    configureServer(server) {
      server.middlewares.use((request, response, next) => {
        const path = (request.url ?? '').split('?')[0]
        const prefix = `/${DRAWING_ASSETS}fonts/`
        if (!path.startsWith(prefix)) return next()
        const file = join(fonts, decodeURIComponent(path.slice(prefix.length)))
        if (!file.startsWith(fonts + sep)) return next()
        try {
          const data = readFileSync(file)
          response.setHeader('Content-Type', 'font/woff2')
          response.end(data)
        } catch {
          next()
        }
      })
    },
    generateBundle() {
      for (const file of filesUnder(fonts)) {
        const name = relative(fonts, file).split(sep).join('/')
        this.emitFile({
          type: 'asset',
          fileName: `${DRAWING_ASSETS}fonts/${name}`,
          source: readFileSync(file)
        })
      }
    }
  }
}
