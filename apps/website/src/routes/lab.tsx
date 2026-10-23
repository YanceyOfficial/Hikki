import '@fontsource-variable/newsreader/opsz.css'
import { createFileRoute } from '@tanstack/solid-router'
import type { JSX } from 'solid-js'
import { createSignal, For, Index, onCleanup, onMount } from 'solid-js'

import { type Photo, photos, photoSrc } from '../lab-photos'
import { APP_STORE_URL } from '../site'

/**
 * An experiment: the page as one composed screen, Skand's way — photographs and the app filling a grid edge to
 * edge, two quiet colour fields, a serif. Four chapters turn on their own; each picture wipes in over the last.
 */
export const Route = createFileRoute('/lab')({
  head: () => ({ meta: [{ title: 'Hikki · Lab' }, { name: 'robots', content: 'noindex' }] }),
  component: Lab
})

type Shot = { src: string; alt: string; position?: string; fit?: 'cover' | 'contain' }

type Chapter = {
  label: string
  title: string
  text: string
  details: string[]
  big: Photo
  side: Photo
  corner: Photo
  shot: Shot
}

const chapters: Chapter[] = [
  {
    label: 'Local-first',
    title: 'Notes that stay on your devices.',
    text: 'Every page is kept on your device first. No account, and nothing waits on a server.',
    details: ['Works offline', 'Syncs through your iCloud', 'Nothing two devices write is lost'],
    big: photos.notebook,
    side: photos.leaves,
    corner: photos.pen,
    shot: {
      src: '/shots/iphone-home.webp',
      alt: 'Hikki on iPhone: the home screen.',
      position: 'top'
    }
  },
  {
    label: 'Split view',
    title: 'Two pages side by side.',
    text: 'Drag a page to the edge of the window and it opens beside the one you are writing in.',
    details: ['On Mac and iPad', 'Each side its own editor', 'A PDF from the page opens there too'],
    big: photos.reading,
    side: photos.temple,
    corner: photos.leaves,
    shot: { src: '/shots/mac-split.webp', alt: 'Split view on Mac.', position: '58% top' }
  },
  {
    label: 'Ask AI',
    title: 'Ask beside the page.',
    text: 'The AI panel reads the page you have open. Select a passage to have it rewritten, and review the change first.',
    details: [
      'Your own OpenAI or Anthropic key',
      'Web search with sources',
      'Nothing is sent until you ask'
    ],
    big: photos.pen,
    side: photos.notebook,
    corner: photos.temple,
    shot: {
      src: '/shots/ipad-ai-panel.webp',
      alt: 'The AI panel answering about a page.',
      position: 'top'
    }
  },
  {
    label: 'Furigana',
    title: 'Readings above the kanji.',
    text: 'Select a word and Hikki suggests its reading, then sets it above the text, the way a textbook does.',
    details: ['毎日 → まいにち', 'One reading per kanji run', 'Or one over the whole word'],
    big: photos.brush,
    side: photos.neon,
    corner: photos.reading,
    shot: {
      src: '/shots/iphone-page.webp',
      alt: 'A Japanese lesson with furigana on iPhone.',
      position: 'center 78%'
    }
  }
]

/** How long a chapter stays, in ms. */
const DWELL = 6000

function Lab() {
  const [index, setIndex] = createSignal(0)
  const [previous, setPrevious] = createSignal(-1)
  const [paused, setPaused] = createSignal(false)
  const go = (next: number) => {
    const count = chapters.length
    setPrevious(index())
    setIndex(((next % count) + count) % count)
  }
  onMount(() => {
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return
    const timer = window.setInterval(() => {
      if (!paused()) go(index() + 1)
    }, DWELL)
    onCleanup(() => window.clearInterval(timer))
  })
  const chapter = () => chapters[index()]

  return (
    <main class="lab" onMouseEnter={() => setPaused(true)} onMouseLeave={() => setPaused(false)}>
      <div class="lab-grid">
        <Layers class="lab-big" pick={(c) => c.big} index={index} previous={previous} />

        <header class="lab-brand">
          <img src="/icon.png" alt="" width="32" height="32" class="rounded-[8px]" />
          <span class="lab-serif text-xl">Hikki</span>
        </header>
        <nav class="lab-nav" aria-label="Chapters">
          <For each={chapters}>
            {(c, i) => (
              <a
                href={`#${c.label}`}
                aria-current={i() === index() ? 'true' : undefined}
                onClick={(event) => {
                  event.preventDefault()
                  go(i())
                }}
              >
                {c.label}
              </a>
            )}
          </For>
        </nav>

        <section class="lab-navy" aria-live="polite">
          <p class="lab-serif self-end text-3xl tabular-nums">
            {String(index() + 1).padStart(2, '0')}
          </p>
          <Swap index={index}>
            <h1 class="lab-serif text-[clamp(1.8rem,2.6vw,2.6rem)] leading-[1.08]">
              {chapter().title}
            </h1>
            <p class="mt-4 max-w-[26rem] text-[15px] leading-relaxed opacity-80">
              {chapter().text}
            </p>
          </Swap>
        </section>

        <Layers class="lab-side" pick={(c) => c.side} index={index} previous={previous} />

        <aside class="lab-green">
          <a class="lab-credit" href="https://unsplash.com/?utm_source=hikki&utm_medium=referral">
            Photos from Unsplash
          </a>
          <p class="lab-vertical">Local-first notes for iPhone, iPad and Mac</p>
        </aside>

        <div class="lab-shot">
          <Index each={chapters}>
            {(c, i) => (
              <img
                src={c().shot.src}
                alt={c().shot.alt}
                style={{
                  'object-position': c().shot.position ?? 'center',
                  'object-fit': c().shot.fit ?? 'cover'
                }}
                class={layerClass(i, index(), previous())}
                loading="eager"
              />
            )}
          </Index>
        </div>

        <section class="lab-forest">
          <Swap index={index}>
            <p class="lab-serif text-2xl">{chapter().label}</p>
            <ul class="mt-4 space-y-1.5 text-[14px] leading-relaxed opacity-85">
              <For each={chapter().details}>{(line) => <li>{line}</li>}</For>
            </ul>
          </Swap>
          <div class="mt-auto flex items-end justify-between gap-4 pt-8">
            <p class="lab-serif text-lg">Made for Apple devices</p>
            <div class="flex gap-2">
              <button
                type="button"
                class="lab-arrow"
                aria-label="Previous"
                onClick={() => go(index() - 1)}
              >
                ←
              </button>
              <button
                type="button"
                class="lab-arrow"
                aria-label="Next"
                onClick={() => go(index() + 1)}
              >
                →
              </button>
            </div>
          </div>
        </section>

        <a
          class="lab-store"
          href={APP_STORE_URL ?? undefined}
          aria-disabled={APP_STORE_URL ? undefined : 'true'}
        >
          {APP_STORE_URL ? 'Get it on the App Store' : 'Coming to the App Store'}
          <span aria-hidden="true">+</span>
        </a>
        <Layers class="lab-corner" pick={(c) => c.corner} index={index} previous={previous} />
      </div>
      <Credits />
    </main>
  )
}

/** The current layer on top (it wipes in), the one before it beneath, the rest hidden. */
function layerClass(i: number, current: number, previous: number) {
  return `lab-layer ${i === current ? 'is-current' : i === previous ? 'is-previous' : ''}`
}

/** One photo cell: a layer per chapter, so the next picture can wipe in over the last one. */
function Layers(props: {
  class: string
  pick: (c: Chapter) => Photo
  index: () => number
  previous: () => number
}) {
  return (
    <div class={props.class}>
      <Index each={chapters}>
        {(c, i) => (
          <img
            src={photoSrc(props.pick(c()), 1400)}
            srcset={`${photoSrc(props.pick(c()), 700)} 700w, ${photoSrc(props.pick(c()), 1400)} 1400w, ${photoSrc(props.pick(c()), 2200)} 2200w`}
            sizes="(min-width: 1024px) 40vw, 100vw"
            alt={props.pick(c()).alt}
            class={layerClass(i, props.index(), props.previous())}
            loading="eager"
          />
        )}
      </Index>
    </div>
  )
}

/** Text that changes with the chapter: keyed on it, so each chapter's words fade in anew. */
function Swap(props: { index: () => number; children: JSX.Element }) {
  return <For each={[props.index()]}>{() => <div class="lab-swap">{props.children}</div>}</For>
}

function Credits() {
  const unique = [...new Map(Object.values(photos).map((p) => [p.author, p])).values()]
  return (
    <footer class="lab-credits">
      Photos by{' '}
      <For each={unique}>
        {(p, i) => (
          <>
            <a href={p.authorUrl}>{p.author}</a>
            {i() < unique.length - 1 ? ', ' : ''}
          </>
        )}
      </For>{' '}
      on <a href="https://unsplash.com/?utm_source=hikki&utm_medium=referral">Unsplash</a>.{' '}
      <a href="/">Back to the main page</a>
    </footer>
  )
}
