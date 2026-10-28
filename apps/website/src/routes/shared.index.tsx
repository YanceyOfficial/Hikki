import { createFileRoute, Link, useNavigate } from '@tanstack/solid-router'
import { createEffect, createSignal, For, Match, on, onCleanup, Show, Switch } from 'solid-js'

import { ClearIcon, SearchIcon, SharedShell } from '../components/shared-shell'
import {
  listRequest,
  listURL,
  parseList,
  PUBLISH_TAGS,
  tagLabel,
  type ListedPage
} from '../publish'
import { SITE_URL } from '../site'

const title = 'Hikki Shared'
const description =
  'Notes, study guides and templates people chose to share from Hikki. Save any of them to your own.'

type Search = { q?: string; tag?: string }

export const Route = createFileRoute('/shared/')({
  validateSearch: (search: Record<string, unknown>): Search => ({
    q: typeof search.q === 'string' && search.q.trim() ? search.q.slice(0, 100) : undefined,
    tag:
      typeof search.tag === 'string' && PUBLISH_TAGS.some((tag) => tag.id === search.tag)
        ? search.tag
        : undefined
  }),
  head: () => ({
    meta: [
      { title },
      { name: 'description', content: description },
      { property: 'og:title', content: title },
      { property: 'og:description', content: description },
      { property: 'og:url', content: `${SITE_URL}/shared` }
    ],
    links: [{ rel: 'canonical', href: `${SITE_URL}/shared` }]
  }),
  component: SharedList
})

type State =
  | { kind: 'loading' }
  | { kind: 'unavailable' }
  | { kind: 'failed' }
  | { kind: 'ready'; pages: ListedPage[]; marker: string | null; more: boolean }

/**
 * The list of listed pages: a search field and the preset tags over the newest pages first, a page of them at a
 * time ("Show more" asks CloudKit for the next with its continuation marker). The search and the tag live in the
 * address (`?q=…&tag=…`), so a filtered list can be shared; typing waits for a pause before it asks.
 */
function SharedList() {
  const search = Route.useSearch()
  const navigate = useNavigate({ from: '/shared/' })
  const [state, setState] = createSignal<State>({ kind: 'loading' })
  const [typed, setTyped] = createSignal(search().q ?? '')
  let request = 0

  const load = async (marker: string | null) => {
    const token = import.meta.env.VITE_CLOUDKIT_TOKEN as string | undefined
    const env = (import.meta.env.VITE_CLOUDKIT_ENV as string | undefined) ?? 'production'
    if (!token) return setState({ kind: 'unavailable' })
    const id = ++request
    const before = state()
    if (marker && before.kind === 'ready') setState({ ...before, more: true })
    else setState({ kind: 'loading' })
    try {
      const response = await fetch(
        listURL(env, token),
        listRequest({ query: search().q, tag: search().tag, marker })
      )
      const list = response.ok ? parseList(await response.json()) : null
      if (id !== request) return
      if (!list) return setState({ kind: 'failed' })
      const earlier = marker && before.kind === 'ready' ? before.pages : []
      setState({
        kind: 'ready',
        pages: [...earlier, ...list.pages],
        marker: list.marker,
        more: false
      })
    } catch {
      if (id === request) setState({ kind: 'failed' })
    }
  }

  // A new search or tag starts the list again (in the browser only: the server renders the frame).
  createEffect(
    on(
      () => [search().q, search().tag],
      () => {
        if (typeof window !== 'undefined') void load(null)
      }
    )
  )

  // Typing searches once it pauses: each keystroke drops the wait the one before it started.
  createEffect(
    on(
      typed,
      (value) => {
        const pause = setTimeout(() => {
          void navigate({
            search: (prev: Search) => ({ ...prev, q: value.trim() || undefined }),
            replace: true
          })
        }, 350)
        onCleanup(() => clearTimeout(pause))
      },
      { defer: true }
    )
  )
  const pickTag = (tag?: string) =>
    void navigate({ search: (prev: Search) => ({ ...prev, tag }), replace: true })

  return (
    <SharedShell>
      <section class="shared-wide">
        <header class="shared-list-head">
          <h1>Hikki Shared</h1>
          <p>
            Pages people chose to share from Hikki: notes, study guides and templates. Save any of
            them to your own.
          </p>
        </header>
        <label class="shared-search">
          <SearchIcon />
          <input
            type="search"
            placeholder="Search shared pages"
            aria-label="Search shared pages"
            value={typed()}
            onInput={(event) => setTyped(event.currentTarget.value)}
          />
          <Show when={typed()}>
            <button
              type="button"
              class="shared-search-clear"
              aria-label="Clear the search"
              onClick={() => setTyped('')}
            >
              <ClearIcon />
            </button>
          </Show>
        </label>
        <div class="shared-tags" role="group" aria-label="Tags">
          <button
            type="button"
            class="shared-chip"
            aria-pressed={!search().tag}
            onClick={() => pickTag()}
          >
            All
          </button>
          <For each={PUBLISH_TAGS}>
            {(tag) => (
              <button
                type="button"
                class="shared-chip"
                aria-pressed={search().tag === tag.id}
                onClick={() => pickTag(search().tag === tag.id ? undefined : tag.id)}
              >
                {tag.label}
              </button>
            )}
          </For>
        </div>
        <Switch>
          <Match when={state().kind === 'loading'}>
            <div class="shared-grid" aria-busy="true" aria-label="Loading shared pages">
              <For each={[0, 1, 2, 3]}>
                {() => <div class="shared-card shared-card-skeleton" />}
              </For>
            </div>
          </Match>
          <Match when={state().kind === 'unavailable'}>
            <p class="shared-empty">Shared pages aren't available here yet.</p>
          </Match>
          <Match when={state().kind === 'failed'}>
            <p class="shared-empty">
              Couldn't load shared pages. Check your connection and{' '}
              <button
                type="button"
                class="underline underline-offset-4"
                onClick={() => void load(null)}
              >
                try again
              </button>
              .
            </p>
          </Match>
          <Match
            when={state().kind === 'ready' ? (state() as Extract<State, { kind: 'ready' }>) : null}
            keyed
          >
            {(ready) => (
              <>
                <Show
                  when={ready.pages.length}
                  fallback={
                    <div class="shared-empty">
                      <p>
                        {search().q || search().tag
                          ? 'No shared pages match. Try other words or another tag.'
                          : 'Nothing has been shared yet.'}
                      </p>
                      <Show when={search().q || search().tag}>
                        <button
                          type="button"
                          class="shared-button mt-4"
                          onClick={() => {
                            setTyped('')
                            void navigate({ search: {}, replace: true })
                          }}
                        >
                          Show every page
                        </button>
                      </Show>
                    </div>
                  }
                >
                  <div class="shared-grid">
                    <For each={ready.pages}>{(page) => <Card page={page} />}</For>
                  </div>
                </Show>
                <Show when={ready.marker}>
                  <div class="mt-10 flex justify-center">
                    <button
                      type="button"
                      class="shared-button"
                      disabled={ready.more}
                      onClick={() => void load(ready.marker)}
                    >
                      {ready.more ? 'Loading…' : 'Show more'}
                    </button>
                  </div>
                </Show>
              </>
            )}
          </Match>
        </Switch>
      </section>
    </SharedShell>
  )
}

function Card(props: { page: ListedPage }) {
  const date = () =>
    props.page.publishedAt
      ? new Date(props.page.publishedAt).toLocaleDateString(undefined, { dateStyle: 'medium' })
      : ''
  return (
    <Link to="/shared/$id" params={{ id: props.page.id }} class="shared-card">
      <div class="shared-card-icon" aria-hidden="true">
        {props.page.icon ?? '📄'}
      </div>
      <h2>{props.page.title || 'Untitled'}</h2>
      <Show when={props.page.excerpt}>
        <p>{props.page.excerpt}</p>
      </Show>
      <Show when={props.page.author}>
        <span class="shared-card-author">by {props.page.author}</span>
      </Show>
      <div class="shared-card-foot">
        <For each={props.page.tags}>{(tag) => <span class="shared-tag">{tagLabel(tag)}</span>}</For>
        <Show when={date()}>
          <span class="ml-auto">{date()}</span>
        </Show>
      </div>
    </Link>
  )
}
