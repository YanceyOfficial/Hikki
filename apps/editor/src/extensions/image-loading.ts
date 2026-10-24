import { Extension } from '@tiptap/core'
import { Plugin, PluginKey } from '@tiptap/pm/state'
import type { EditorView } from '@tiptap/pm/view'

import { imageLoadedBefore, markImageLoaded } from '../lib/loaded-images'

/**
 * Body images load like every network image (`components/lazy-load-image.tsx`, exodus's rule): a skeleton while
 * loading, a fade in, a muted box when it fails. The image view is Tiptap's own DOM, so this marks each `<img>` with
 * `data-load` (loading → entering → loaded, or failed) and `style.css` draws the states. An image already loaded in
 * this run (`lib/loaded-images.ts`) is `loaded` at once — a tab switched back to rebuilds its page, and its pictures
 * must not flash through their skeletons again.
 */
export const ImageLoading = Extension.create({
  name: 'imageLoading',

  addProseMirrorPlugins() {
    return [
      new Plugin({
        key: new PluginKey('imageLoading'),
        view: (view) => {
          track(view)
          return { update: (next) => track(next) }
        }
      })
    ]
  }
})

function track(view: EditorView) {
  for (const img of view.dom.querySelectorAll<HTMLImageElement>('img.hk-image')) {
    if (img.dataset.load) continue
    if ((img.complete && img.naturalWidth > 0) || imageLoadedBefore(img.src)) {
      markImageLoaded(img.src)
      img.dataset.load = 'loaded'
      continue
    }
    img.dataset.load = 'loading'
    img.loading = 'lazy'
    img.decoding = 'async'
    img.addEventListener(
      'load',
      () => {
        markImageLoaded(img.src)
        // One frame transparent, then the shared fade (`.tiptap img[data-load]` transition).
        img.dataset.load = 'entering'
        requestAnimationFrame(() => {
          img.dataset.load = 'loaded'
        })
      },
      { once: true }
    )
    img.addEventListener(
      'error',
      () => {
        img.dataset.load = 'failed'
      },
      { once: true }
    )
  }
}
