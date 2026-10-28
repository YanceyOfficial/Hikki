import { Link } from '@tanstack/solid-router'
import { createEffect, createSignal, For, Match, onCleanup, onMount, Show, Switch } from 'solid-js'

import {
  coverView,
  decrypt,
  hasMath,
  isListed,
  hasLinks,
  keyFromFragment,
  lookupRequest,
  lookupURL,
  outline,
  type OutlineItem,
  nameTab,
  recordFiles,
  renderMath,
  sanitize,
  saveToHikkiURL,
  blobType,
  tagLabel,
  type PublishedPayload
} from '../publish'
import { SHARED_LIST_OPEN } from '../site'
import { GridIcon, LinkIcon, SaveIcon } from './shared-shell'

type State =
  | { kind: 'loading' }
  | { kind: 'unavailable' }
  | { kind: 'missingKey' }
  | { kind: 'notFound' }
  | { kind: 'cannotOpen' }
  | { kind: 'failed' }
  | {
      kind: 'ready'
      payload: PublishedPayload
      html: string
      cover: ReturnType<typeof coverView>
      toc: OutlineItem[]
      blobs: string[]
      listed: boolean
      tags: string[]
      key: string | null
    }

type Ready = Extract<State, { kind: 'ready' }>

/** Bytes as text and back to the payload a listed record holds as it is. */
const readPayload = (bytes: ArrayBuffer) =>
  JSON.parse(new TextDecoder().decode(bytes)) as PublishedPayload

/**
 * A published page, read in the browser after the frame is up: the record fetched by its name; a listed page's
 * payload and attachments taken as they are, a page for people with the link opened with the key from the address's
 * fragment (`linked`: the `/p/<record>` reader — on `/shared/<record>` a page that isn't listed is not found); the
 * attachments into blobs; the HTML reduced to the allowlist.
 */
export function SharedReader(props: { id: string; linked: boolean }) {
  const [state, setState] = createSignal<State>({ kind: 'loading' })
  onCleanup(() => {
    const current = state()
    if (current.kind === 'ready') for (const url of current.blobs) URL.revokeObjectURL(url)
  })

  // The tab is named after the page once it opens (the frame is served before the record is read).
  createEffect(() => {
    const current = state()
    if (current.kind === 'ready') nameTab(current.payload.title)
  })

  onMount(async () => {
    const token = import.meta.env.VITE_CLOUDKIT_TOKEN as string | undefined
    const env = (import.meta.env.VITE_CLOUDKIT_ENV as string | undefined) ?? 'production'
    if (!token) return setState({ kind: 'unavailable' })
    const keyText = window.location.hash.replace(/^#/u, '').trim() || null
    try {
      const response = await fetch(lookupURL(env, token), lookupRequest(props.id))
      if (!response.ok) return setState({ kind: 'failed' })
      const body = (await response.json()) as { records?: unknown[] }
      const record = body.records?.[0]
      const files = recordFiles(record)
      if (files === 'notFound') return setState({ kind: 'notFound' })
      if (!files) return setState({ kind: 'failed' })
      const listed = isListed(record)
      const key = listed ? null : keyFromFragment(window.location.hash)
      if (!listed && !props.linked) return setState({ kind: 'notFound' })
      if (!listed && !key) return setState({ kind: 'missingKey' })
      const open = (bytes: ArrayBuffer) => (key ? decrypt(bytes, key) : Promise.resolve(bytes))
      const raw = await (await fetch(files.payloadURL)).arrayBuffer()
      let payload: PublishedPayload
      try {
        payload = readPayload(await open(raw))
      } catch {
        return setState({ kind: 'cannotOpen' })
      }
      const urls = new Map<string, string>()
      const blobs: string[] = []
      await Promise.all(
        payload.assets.map(async (asset, index) => {
          const url = files.fileURLs[index]
          if (!url) return
          try {
            const bytes = await open(await (await fetch(url)).arrayBuffer())
            const blob = URL.createObjectURL(new Blob([bytes], { type: blobType(asset.type) }))
            blobs.push(blob)
            urls.set(asset.name, blob)
          } catch {
            // A picture that can't be opened is left out; the page still reads.
          }
        })
      )
      // Tags and author travel in the payload (sealed with a link's page); a listed record has its tags as fields too.
      const fieldTags = (record as { fields?: { tags?: { value?: unknown } } }).fields?.tags?.value
      const tags = Array.isArray(payload.tags) ? payload.tags : fieldTags
      let html = sanitize(payload.html, (name) => urls.get(name) ?? null, payload.title)
      if (hasMath(html)) {
        // KaTeX and its stylesheet and fonts only for a page with formulas.
        const [katex] = await Promise.all([import('katex'), import('katex/dist/katex.min.css')])
        html = renderMath(html, katex.default)
      }
      const contents = outline(html)
      setState({
        kind: 'ready',
        payload,
        html: contents.html,
        toc: contents.items,
        cover: coverView(payload.cover, (name) => urls.get(name) ?? null),
        blobs,
        listed,
        tags: Array.isArray(tags)
          ? tags.filter((tag): tag is string => typeof tag === 'string')
          : [],
        key: listed ? null : keyText
      })
    } catch {
      setState({ kind: 'failed' })
    }
  })

  return (
    <article class="shared-column">
      <Switch>
        <Match when={state().kind === 'loading'}>
          <div class="shared-skeleton" aria-busy="true" aria-label="Opening the page">
            <span class="h-12 w-12" />
            <span class="mt-6 h-10 w-2/3" />
            <span class="mt-8 h-4 w-full" />
            <span class="mt-3 h-4 w-11/12" />
            <span class="mt-3 h-4 w-4/5" />
          </div>
        </Match>
        <Match when={state().kind === 'unavailable'}>
          <Notice title="Shared pages aren't available here yet">
            This site isn't set up to read published pages yet.
          </Notice>
        </Match>
        <Match when={state().kind === 'missingKey'}>
          <Notice title="This link is missing its key">
            A page shared by link opens only with the whole link, including the part after the #.
            Ask for the link again.
          </Notice>
        </Match>
        <Match when={state().kind === 'notFound'}>
          <Notice title="This page isn't shared any more">
            Whoever shared it took it down, or the link is mistyped.
          </Notice>
        </Match>
        <Match when={state().kind === 'cannotOpen'}>
          <Notice title="This link doesn't open this page">
            The key in the link doesn't fit the page. Ask for the link again.
          </Notice>
        </Match>
        <Match when={state().kind === 'failed'}>
          <Notice title="Couldn't load the page">Check your connection and try again.</Notice>
        </Match>
        <Match when={state().kind === 'ready' ? (state() as Ready) : null} keyed>
          {(ready) => <Page id={props.id} ready={ready} />}
        </Match>
      </Switch>
    </article>
  )
}

function Notice(props: { title: string; children: string }) {
  return (
    <div class="shared-notice">
      <h1>{props.title}</h1>
      <p>{props.children}</p>
      <Show
        when={SHARED_LIST_OPEN}
        fallback={
          <Link to="/" class="shared-button mt-6">
            About Hikki
          </Link>
        }
      >
        <Link to="/shared" class="shared-button mt-6">
          Browse shared pages
        </Link>
      </Show>
    </div>
  )
}

function Page(props: { id: string; ready: Ready }) {
  const [copied, setCopied] = createSignal(false)
  const published = () => {
    const date = new Date(props.ready.payload.publishedAt)
    return Number.isNaN(date.getTime())
      ? ''
      : date.toLocaleDateString(undefined, { dateStyle: 'long' })
  }
  const author = () => props.ready.payload.author?.trim() ?? ''
  const copy = async () => {
    try {
      await navigator.clipboard.writeText(window.location.href)
      setCopied(true)
      setTimeout(() => setCopied(false), 2000)
    } catch {
      // No clipboard (an insecure context): the address bar still has the link.
    }
  }
  const cover = props.ready.cover
  return (
    <>
      <Show when={cover}>
        {(view) => {
          const shown = view()
          return 'gradient' in shown ? (
            <div class="shared-cover" style={{ background: shown.gradient }} />
          ) : (
            <div class="shared-cover">
              <img
                src={shown.image}
                alt=""
                referrerpolicy="no-referrer"
                style={{ 'object-position': `50% ${shown.position}%` }}
              />
            </div>
          )
        }}
      </Show>
      <header class="shared-page-head" classList={{ 'has-cover': Boolean(cover) }}>
        <Show when={props.ready.payload.icon}>
          <div class="shared-page-icon">{props.ready.payload.icon}</div>
        </Show>
        <h1 class="shared-page-title">{props.ready.payload.title || 'Untitled'}</h1>
        <div class="shared-meta">
          <Show when={author()}>
            <span class="shared-author">by {author()}</span>
          </Show>
          <Show when={published()}>
            <span>{published()}</span>
          </Show>
          <Show when={!props.ready.listed}>
            <span>Shared by link</span>
          </Show>
        </div>
        <Show when={props.ready.tags.length}>
          <div class="shared-page-tags">
            <For each={props.ready.tags}>
              {(tag) => (
                <Link to="/shared" search={{ tag }} class="shared-tag">
                  {tagLabel(tag)}
                </Link>
              )}
            </For>
          </div>
        </Show>
      </header>
      <Show when={hasLinks(props.ready.html)}>
        <p class="shared-link-note">
          <LinkIcon />
          <span>
            Some links may not open for you. Links to the author's other pages lead into their own
            Hikki, and some web pages need a sign-in or aren't public.
          </span>
        </p>
      </Show>
      {/* The HTML passed the allowlist in `sanitize`; nothing else reaches this node. */}
      <div class="published-body" innerHTML={props.ready.html} />
      <Show when={props.ready.toc.length > 1}>
        <Contents items={props.ready.toc} />
      </Show>
      {/* The page's actions float at the foot, out of the reading's way. */}
      <nav class="shared-dock" aria-label="Page actions">
        <a class="shared-dock-primary" href={saveToHikkiURL(props.id, props.ready.key)}>
          <SaveIcon />
          Save to Hikki
        </a>
        <button type="button" class="shared-dock-item" onClick={copy}>
          <LinkIcon />
          {copied() ? 'Copied' : 'Copy link'}
        </button>
        <Show when={SHARED_LIST_OPEN}>
          <span class="shared-dock-divider" aria-hidden="true" />
          <Link to="/shared" class="shared-dock-item" aria-label="Browse shared pages">
            <GridIcon />
            <span class="max-sm:hidden">Browse</span>
          </Link>
        </Show>
      </nav>
    </>
  )
}

/**
 * The page's contents beside it on a wide window (as the app's outline rail): its headings, the one being read
 * marked — the last one past the top of the window — and a click scrolls there.
 */
function Contents(props: { items: OutlineItem[] }) {
  const [active, setActive] = createSignal(props.items[0]?.id ?? '')
  // A cover reaches the rail's height; the rail waits until the cover has scrolled up past it.
  const [hidden, setHidden] = createSignal(false)
  const spy = () => {
    let current = props.items[0]?.id ?? ''
    for (const item of props.items) {
      const node = document.getElementById(item.id)
      if (node && node.getBoundingClientRect().top <= 120) current = item.id
    }
    setActive(current)
    const cover = document.querySelector('.shared-cover')
    setHidden(cover ? cover.getBoundingClientRect().bottom > 96 : false)
  }
  onMount(() => {
    spy()
    window.addEventListener('scroll', spy, { passive: true })
    onCleanup(() => window.removeEventListener('scroll', spy))
  })
  const top = Math.min(...props.items.map((item) => item.level))
  return (
    <nav class="shared-toc" aria-label="Contents" data-hidden={hidden() ? '' : undefined}>
      <p class="shared-toc-title">Contents</p>
      <ul>
        <For each={props.items}>
          {(item) => (
            <li style={{ 'padding-left': `${(item.level - top) * 0.75}rem` }}>
              <a
                href={`#${item.id}`}
                aria-current={active() === item.id ? 'location' : undefined}
                onClick={(event) => {
                  event.preventDefault()
                  document
                    .getElementById(item.id)
                    ?.scrollIntoView({ behavior: 'smooth', block: 'start' })
                  setActive(item.id)
                }}
              >
                {item.text}
              </a>
            </li>
          )}
        </For>
      </ul>
    </nav>
  )
}
