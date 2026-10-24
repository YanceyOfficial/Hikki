import type { Plugin } from 'vite'
/** Where the fonts are served and bundled, under the editor's base (`setDrawingAssetPath` points Excalidraw here). */
export declare const DRAWING_ASSETS = 'excalidraw/'
export declare const LOCAL_FALLBACK = 'new URL("./excalidraw/", document.baseURI).href'
export declare function withoutCDNFallback(code: string): string
/** Excalidraw's code with `REMOTE_PATCHES` applied; `patched` counts what each one replaced. */
export declare function withoutRemoteContent(code: string): {
  code: string
  patched: number[]
}
/**
 * Every font Excalidraw draws with — the hand-drawn CJK one (Xiaolai, ~12 MB) included — copied into the bundle at
 * `excalidraw/fonts/…` (served from there by the dev server), Excalidraw's CDN fallback and
 * its loading of what scenes name (`REMOTE_PATCHES`) taken out of its code.
 */
export declare function excalidrawAssets(): Plugin
