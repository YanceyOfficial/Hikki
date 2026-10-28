import { createFileRoute } from '@tanstack/solid-router'
import { createSignal, Match, onCleanup, onMount, Switch } from 'solid-js'

import { Footer } from '../components/footer'
import { Header } from '../components/header'
import { row } from '../components/row'
import {
  decrypt,
  keyFromFragment,
  lookupRequest,
  lookupURL,
  recordFiles,
  type PublishedPayload
} from '../publish'
import { CONTACT_EMAIL } from '../site'

const title = 'A page shared from Hikki'

export const Route = createFileRoute('/p/$id')({
  head: () => ({
    meta: [
      { title },
      {
        name: 'description',
        content: 'A page someone published from Hikki. Only people with the link can read it.'
      },
      // The content is opened in the browser with the link's key: nothing here for a crawler, and nothing it should keep.
      { name: 'robots', content: 'noindex, nofollow' }
    ]
  }),
  component: Published
})

type State =
  | { kind: 'loading' }
  | { kind: 'unavailable' }
  | { kind: 'missingKey' }
  | { kind: 'notFound' }
  | { kind: 'cannotOpen' }
  | { kind: 'failed' }
  | { kind: 'ready'; payload: PublishedPayload; html: string; blobs: string[] }

/**
 * The reader: the record fetched by the address's id, opened with the key from the fragment, its attachments
 * opened the same way into blobs, the HTML reduced to the allowlist — all in the browser, after the page is up;
 * the server renders only the frame.
 */
function Published() {
  const params = Route.useParams()
  const [state, setState] = createSignal<State>({ kind: 'loading' })
  // The attachments' blobs go with the page.
  onCleanup(() => {
    const current = state()
    if (current.kind === 'ready') for (const url of current.blobs) URL.revokeObjectURL(url)
  })

  onMount(async () => {
    const token = import.meta.env.VITE_CLOUDKIT_TOKEN as string | undefined
    const env = (import.meta.env.VITE_CLOUDKIT_ENV as string | undefined) ?? 'production'
    if (!token) return setState({ kind: 'unavailable' })
    const key = keyFromFragment(window.location.hash)
    if (!key) return setState({ kind: 'missingKey' })
    try {
      const response = await fetch(lookupURL(env, token), lookupRequest(params().id))
      if (!response.ok) return setState({ kind: 'failed' })
      const body = (await response.json()) as { records?: unknown[] }
      const files = recordFiles(body.records?.[0])
      if (files === 'notFound') return setState({ kind: 'notFound' })
      if (!files) return setState({ kind: 'failed' })
      const sealed = await (await fetch(files.payloadURL)).arrayBuffer()
      let payload: PublishedPayload
      try {
        payload = JSON.parse(
          new TextDecoder().decode(await decrypt(sealed, key))
        ) as PublishedPayload
      } catch {
        return setState({ kind: 'cannotOpen' })
      }
      // The attachments, each opened into a blob the page's pictures and files point at.
      const urls = new Map<string, string>()
      const blobs: string[] = []
      await Promise.all(
        payload.assets.map(async (asset, index) => {
          const url = files.fileURLs[index]
          if (!url) return
          try {
            const bytes = await decrypt(await (await fetch(url)).arrayBuffer(), key)
            const blob = URL.createObjectURL(new Blob([bytes], { type: asset.type }))
            blobs.push(blob)
            urls.set(asset.name, blob)
          } catch {
            // A picture that can't be opened is left out; the page still reads.
          }
        })
      )
      const { sanitize } = await import('../publish')
      setState({
        kind: 'ready',
        payload,
        html: sanitize(payload.html, (name) => urls.get(name) ?? null),
        blobs
      })
    } catch {
      setState({ kind: 'failed' })
    }
  })

  const report = () =>
    `mailto:${CONTACT_EMAIL}?subject=${encodeURIComponent(`Report a published page: ${params().id}`)}`

  return (
    <main class="canvas">
      <Header />
      <section class={`${row} grid-cols-1`}>
        <article class="cell p-6 md:p-12">
          <div class="published mx-auto max-w-[72ch]">
            <Switch>
              <Match when={state().kind === 'loading'}>
                <p class="text-muted">Opening the page…</p>
              </Match>
              <Match when={state().kind === 'unavailable'}>
                <Notice title="Published pages are not available here yet">
                  This site is not set up to read published pages yet. Open the link in Hikki
                  instead.
                </Notice>
              </Match>
              <Match when={state().kind === 'missingKey'}>
                <Notice title="This link is missing its key">
                  A published page opens only with the whole link, including the part after the #.
                  Ask for the link again.
                </Notice>
              </Match>
              <Match when={state().kind === 'notFound'}>
                <Notice title="This page is no longer published">
                  Whoever shared it took the link down.
                </Notice>
              </Match>
              <Match when={state().kind === 'cannotOpen'}>
                <Notice title="This link does not open this page">
                  The key in the link does not fit the page. Ask for the link again.
                </Notice>
              </Match>
              <Match when={state().kind === 'failed'}>
                <Notice title="Could not load the page">
                  Check your connection and try again.
                </Notice>
              </Match>
              <Match when={state().kind === 'ready' ? state() : null} keyed>
                {(ready) => <Page ready={ready as Extract<State, { kind: 'ready' }>} />}
              </Match>
            </Switch>
          </div>
        </article>
      </section>
      <section class={`${row} grid-cols-1`}>
        <div class="cell text-caption flex flex-wrap items-center justify-between gap-3 p-5 text-muted">
          <span>Published with Hikki. Only people with the link can read this page.</span>
          <a href={report()} class="font-semibold underline-offset-4 hover:underline">
            Report this page
          </a>
        </div>
      </section>
      <Footer />
    </main>
  )
}

function Notice(props: { title: string; children: string }) {
  return (
    <div>
      <h1 class="expanded text-2xl font-[800]">{props.title}</h1>
      <p class="mt-3 text-muted">{props.children}</p>
    </div>
  )
}

function Page(props: { ready: Extract<State, { kind: 'ready' }> }) {
  const published = () => {
    const date = new Date(props.ready.payload.publishedAt)
    return Number.isNaN(date.getTime())
      ? ''
      : date.toLocaleDateString(undefined, { dateStyle: 'long' })
  }
  return (
    <>
      <header class="mb-8">
        {props.ready.payload.icon ? (
          <div class="text-5xl mb-3 leading-none">{props.ready.payload.icon}</div>
        ) : null}
        <h1 class="expanded text-[clamp(2rem,3.4vw,3rem)] leading-[1.05] font-[850] tracking-[-0.02em]">
          {props.ready.payload.title || 'Untitled'}
        </h1>
        {published() ? <p class="text-caption mt-3 text-muted">Published {published()}</p> : null}
      </header>
      {/* The HTML passed the allowlist in `sanitize`; nothing else reaches this node. */}
      <div class="published-body" innerHTML={props.ready.html} />
    </>
  )
}
