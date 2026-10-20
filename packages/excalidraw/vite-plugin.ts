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
 * Two ways Excalidraw itself would load or run what a scene or the clipboard names, closed in its code (the scene
 * checks in `scene.ts` close the rest):
 * - pasted HTML holding pictures by address: Excalidraw fetches each one (`ImageURLToFile`) — the condition for that
 *   becomes false, so the paste goes in as its text;
 * - an `iframe` element (the magic frame's output) runs the HTML in its `customData.generationData` in a frame —
 *   that is no longer read, so such an element can only show Excalidraw's "no generation data" error.
 */
const REMOTE_PATCHES: [RegExp, string][] = [
  [/(\.type\s*===\s*"imageUrl"\)\s*&&)(\s*this\.isToolSupported\("image"\))/gu, '$1 false &&$2'],
  [
    /customData\?\.generationData(\s*\?\?\s*this\.magicGenerations\.get\()/gu,
    'customData?.hikkiBlocked$1'
  ]
]

/** Excalidraw's code with `REMOTE_PATCHES` applied; `patched` counts what each one replaced. */
export function withoutRemoteContent(code: string): { code: string; patched: number[] } {
  const patched: number[] = []
  let out = code
  for (const [pattern, replacement] of REMOTE_PATCHES) {
    patched.push(out.match(pattern)?.length ?? 0)
    out = out.replaceAll(pattern, replacement)
  }
  return { code: out, patched }
}

/**
 * Every font Excalidraw draws with — the hand-drawn CJK one (Xiaolai, ~12 MB) included — copied into the bundle at
 * `excalidraw/fonts/…` (served from there by the dev server), Excalidraw's CDN fallback and
 * its loading of what scenes name (`REMOTE_PATCHES`) taken out of its code.
 */
export function excalidrawAssets(): Plugin {
  const fonts = join(excalidrawDist(), 'fonts')
  return {
    name: 'hikki-excalidraw-assets',
    enforce: 'pre',
    transform(code, id) {
      if (!id.includes('@excalidraw/excalidraw')) return null
      const out = withoutRemoteContent(
        code.includes('esm.sh') ? withoutCDNFallback(code) : code
      ).code
      return out === code ? null : { code: out, map: null }
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
