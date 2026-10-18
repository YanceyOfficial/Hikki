import '@fontsource-variable/archivo/wdth.css'
import { createRootRoute, HeadContent, Scripts } from '@tanstack/solid-router'
import type { JSX } from 'solid-js'
import { Suspense } from 'solid-js'
import { HydrationScript } from 'solid-js/web'

import { SITE_URL } from '../site'
import { THEME_SCRIPT } from '../theme'

import styles from '../styles.css?url'

const title = 'Hikki: local-first notes for iPhone, iPad and Mac'
const description =
  'A block editor whose pages are files in a folder you choose. No account, works offline, syncs through iCloud Drive.'

export const Route = createRootRoute({
  head: () => ({
    meta: [
      { charSet: 'utf-8' },
      { name: 'viewport', content: 'width=device-width, initial-scale=1' },
      { title },
      { name: 'description', content: description },
      { name: 'theme-color', content: '#000000' },
      { name: 'color-scheme', content: 'light dark' },
      { property: 'og:title', content: title },
      { property: 'og:description', content: description },
      { property: 'og:url', content: SITE_URL },
      { property: 'og:image', content: `${SITE_URL}/shots/mac-hero.webp` },
      { name: 'twitter:card', content: 'summary_large_image' }
    ],
    links: [
      { rel: 'stylesheet', href: styles },
      { rel: 'icon', type: 'image/png', href: '/favicon.png' },
      { rel: 'apple-touch-icon', href: '/apple-touch-icon.png' },
      { rel: 'canonical', href: SITE_URL }
    ]
  }),
  shellComponent: RootDocument
})

function RootDocument(props: { children: JSX.Element }) {
  return (
    <html lang="en">
      <head>
        {/* Before anything paints: the stored light/dark choice, so the page never flashes the other one. */}
        <script innerHTML={THEME_SCRIPT} />
        <HydrationScript />
      </head>
      <body>
        <HeadContent />
        <Suspense>{props.children}</Suspense>
        <Scripts />
      </body>
    </html>
  )
}
