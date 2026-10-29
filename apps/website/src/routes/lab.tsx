import { createFileRoute } from '@tanstack/solid-router'
import { createSignal, For, onCleanup, onMount } from 'solid-js'

import { scrollScene } from '../components/scroll-scene'
import { LAUNCH_PRICE, PRICE, REQUIREMENTS, SITE_URL, TRIAL_DAYS } from '../site'

import labStyles from '../lab.css?url'

const title = 'Hikki · Lab'
const description =
  'An experimental take on the Hikki site: a dark product page, one idea per screen.'

/**
 * /lab — an experiment, not linked from the site and kept out of search: Hikki told as a dark product page, one
 * idea per screen — a centred headline over the window, highlights to swipe through, the facts as figures, a
 * section with tabs. Its styles are its own (src/lab.css, linked only here); the screenshots are the dark ones.
 */
export const Route = createFileRoute('/lab')({
  head: () => ({
    meta: [
      { title },
      { name: 'description', content: description },
      { name: 'robots', content: 'noindex' }
    ],
    links: [
      { rel: 'stylesheet', href: labStyles },
      { rel: 'canonical', href: `${SITE_URL}/lab` }
    ]
  }),
  component: Lab
})

const HIGHLIGHTS = [
  {
    shot: 'blocks',
    width: 1600,
    height: 1220,
    lead: 'Blocks.',
    text: 'Type “/” for headings, lists, tables, toggles, callouts, formulas and embeds.'
  },
  {
    shot: 'drawing',
    width: 1600,
    height: 980,
    lead: 'Drawings.',
    text: 'A whiteboard inside the page, its fonts on the device.'
  },
  {
    shot: 'comments',
    width: 1400,
    height: 910,
    lead: 'Comments.',
    text: 'Threads on a passage, in the margin beside it.'
  },
  {
    shot: 'history',
    width: 1400,
    height: 1291,
    lead: 'Page history.',
    text: 'Every version for thirty days, compared word by word.'
  },
  {
    shot: 'search',
    width: 1400,
    height: 585,
    lead: 'Search.',
    text: 'Titles, text and the words inside pictures and PDFs.'
  },
  {
    shot: 'dates',
    width: 1200,
    height: 680,
    lead: 'Dates.',
    text: 'Type “@tomorrow 3pm” and it rings on every device.'
  }
]

const FIGURES = [
  { value: '0', label: 'accounts to make' },
  { value: '0', label: 'trackers in the app' },
  { value: `${TRIAL_DAYS} days`, label: 'free, everything open' },
  { value: '3', label: 'devices, one purchase' },
  { value: '256-bit', label: 'key for each shared link' },
  { value: 'Offline', label: 'every page opens and edits' }
]

const REVIEWS = [
  {
    id: 'inline',
    name: 'Inline',
    shot: 'review-inline',
    text: 'Removals struck through and additions written into the page, under a bar with Accept and Discard.'
  },
  {
    id: 'diff',
    name: 'Diff',
    shot: 'review-diff',
    text: 'The change as − and + lines in the bar, the page left as it is until you accept.'
  }
] as const

function Lab() {
  scrollScene('.lab-hero', '.lab-hero-stage')
  revealSections()
  const [review, setReview] = createSignal<(typeof REVIEWS)[number]['id']>('inline')

  return (
    <div class="lab">
      <nav class="lab-nav" aria-label="Hikki">
        <div class="lab-nav-inner">
          <a href="/" class="lab-nav-title">
            Hikki <span>Lab</span>
          </a>
          <div class="lab-nav-links">
            <a href="#highlights">Highlights</a>
            <a href="#ai">AI</a>
            <a href="/community">Community</a>
            <a href="/#price" class="lab-pill lab-pill-small">
              Price
            </a>
          </div>
        </div>
      </nav>

      <header class="lab-hero">
        <div class="lab-hero-sticky">
          <p class="lab-eyebrow">Hikki for iPhone, iPad and Mac</p>
          <h1 class="lab-display">Notes, kept close.</h1>
          <p class="lab-hero-sub">
            {TRIAL_DAYS} days free. Then one purchase, {LAUNCH_PRICE} at launch.
          </p>
          <div class="lab-hero-stage" data-still>
            <img
              src="/shots/mac-hero-dark.webp"
              alt="Hikki on Mac: a page about a trip to Kyoto, the sidebar beside it."
              width={2906}
              height={1808}
              class="lab-hero-img"
            />
          </div>
        </div>
      </header>

      <section id="highlights" class="lab-section">
        <div class="lab-head lab-reveal">
          <h2 class="lab-title">Get the highlights.</h2>
        </div>
        <ul class="lab-rail">
          <For each={HIGHLIGHTS}>
            {(item) => (
              <li class="lab-card">
                <div class="lab-card-shot">
                  <img
                    src={`/shots/${item.shot}-dark.webp`}
                    alt=""
                    width={item.width}
                    height={item.height}
                    loading="lazy"
                  />
                </div>
                <p class="lab-card-text">
                  <strong>{item.lead}</strong> {item.text}
                </p>
              </li>
            )}
          </For>
        </ul>
        <div class="lab-rail-controls">
          <button type="button" class="lab-round" aria-label="Previous" onClick={() => step(-1)}>
            ‹
          </button>
          <button type="button" class="lab-round" aria-label="Next" onClick={() => step(1)}>
            ›
          </button>
        </div>
      </section>

      <section class="lab-section lab-figures-section">
        <div class="lab-head lab-reveal">
          <p class="lab-eyebrow">Local-first</p>
          <h2 class="lab-title">
            Yours before
            <br />
            anyone else's.
          </h2>
          <p class="lab-body">
            Pages live on your devices and travel through your own iCloud, encrypted end to end. No
            sign-up, no server of ours in the middle, nothing counted.
          </p>
        </div>
        <dl class="lab-figures lab-reveal">
          <For each={FIGURES}>
            {(figure) => (
              <div class="lab-figure">
                <dt>{figure.label}</dt>
                <dd>{figure.value}</dd>
              </div>
            )}
          </For>
        </dl>
      </section>

      <section class="lab-section lab-split">
        <div class="lab-split-text lab-reveal">
          <p class="lab-eyebrow">On iPhone</p>
          <h2 class="lab-title">
            Its own layout,
            <br />
            not the Mac's squeezed.
          </h2>
          <p class="lab-body">
            Home with what you were writing, a drawer for the page tree, one floating bar, and a
            keyboard bar with every tool a thumb away.
          </p>
        </div>
        <div class="lab-split-shot lab-reveal">
          <img
            src="/shots/iphone-page-dark.webp"
            alt="Hikki on iPhone: a page with its cover, the floating bar at the foot."
            width={1206}
            height={2622}
            loading="lazy"
          />
        </div>
      </section>

      <section id="ai" class="lab-section">
        <div class="lab-head lab-reveal">
          <p class="lab-eyebrow">Ask AI</p>
          <h2 class="lab-title">Edits you read before you keep.</h2>
          <p class="lab-body">
            Select a passage and ask. The change comes back as a review, never written over your
            words. Bring your own OpenAI or Anthropic key; nothing goes anywhere without one.
          </p>
        </div>
        <div class="lab-tabs" role="tablist" aria-label="Review style">
          <For each={REVIEWS}>
            {(item) => (
              <button
                type="button"
                role="tab"
                class="lab-tab"
                aria-selected={review() === item.id}
                onClick={() => setReview(item.id)}
              >
                {item.name}
              </button>
            )}
          </For>
        </div>
        <div class="lab-frame">
          <For each={REVIEWS}>
            {(item) => (
              <img
                src={`/shots/${item.shot}-dark.webp`}
                alt={`Ask AI's ${item.name} review: ${item.text}`}
                width={2200}
                height={1369}
                loading="lazy"
                class="lab-frame-img"
                data-active={review() === item.id ? '' : undefined}
                aria-hidden={review() !== item.id}
              />
            )}
          </For>
        </div>
        <p class="lab-caption">{REVIEWS.find((item) => item.id === review())?.text}</p>
      </section>

      <section class="lab-section">
        <div class="lab-head lab-reveal">
          <p class="lab-eyebrow">Split view</p>
          <h2 class="lab-title">Two pages, one window.</h2>
          <p class="lab-body">
            Drag a page to the window's edge and it opens beside the one you're in, each side with
            its own editor. On Mac and iPad.
          </p>
        </div>
        <div class="lab-wide lab-reveal">
          <img
            src="/shots/mac-split-dark.webp"
            alt="Hikki on Mac in split view: a page about Kyoto beside “Japanese, week 3”."
            width={2906}
            height={1808}
            loading="lazy"
          />
        </div>
      </section>

      <section class="lab-section lab-end">
        <h2 class="lab-display lab-reveal">Hikki.</h2>
        <p class="lab-end-price lab-reveal">
          <s>{PRICE}</s> {LAUNCH_PRICE} at launch · free for {TRIAL_DAYS} days
        </p>
        <div class="lab-end-actions lab-reveal">
          <a href="/" class="lab-pill">
            Back to the site
          </a>
          <a href="/privacy" class="lab-link">
            Privacy ›
          </a>
        </div>
        <p class="lab-fine">
          Requires {REQUIREMENTS}. AI needs your own provider key and a connection. This page is an
          experiment and may change or disappear.
        </p>
      </section>
    </div>
  )
}

/** Moves the highlights rail by one card. */
function step(direction: 1 | -1) {
  const rail = document.querySelector<HTMLElement>('.lab-rail')
  const card = rail?.querySelector('li')
  if (!rail || !card) return
  rail.scrollBy({ left: direction * (card.clientWidth + 20), behavior: 'smooth' })
}

/** Each `.lab-reveal` rises into place once it comes into view; already there under Reduce Motion. */
function revealSections() {
  onMount(() => {
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return
    const items = document.querySelectorAll<HTMLElement>('.lab-reveal')
    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (!entry.isIntersecting || !(entry.target instanceof HTMLElement)) continue
          entry.target.dataset.shown = ''
          observer.unobserve(entry.target)
        }
      },
      { threshold: 0.25 }
    )
    for (const item of items) {
      // Only what is still below the fold waits for it; what the page opens on is simply there.
      if (item.getBoundingClientRect().top > window.innerHeight) {
        item.dataset.waiting = ''
        observer.observe(item)
      }
    }
    onCleanup(() => observer.disconnect())
  })
}
