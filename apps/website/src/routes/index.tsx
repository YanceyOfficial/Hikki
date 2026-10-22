import { createFileRoute } from '@tanstack/solid-router'
import type { JSX } from 'solid-js'
import { For } from 'solid-js'

import { AskAI } from '../components/ask-ai'
import { Closing } from '../components/closing'
import { Footer } from '../components/footer'
import { Header } from '../components/header'
import { row } from '../components/row'
import { Shot } from '../components/shot'
import { SplitView } from '../components/split-view'

export const Route = createFileRoute('/')({ component: Home })

function Home() {
  return (
    <main class="canvas">
      <Header />
      <Hero />
      <LocalFirst />
      <Devices />
      <SplitView />
      <AskAI />
      <Features />
      <Closing />
      <Footer />
    </main>
  )
}

/** The first screen's short list: what Hikki is, one line each. */
const HERO_FACTS = [
  { title: 'Local-first', text: 'Pages are files in a folder you choose.' },
  { title: 'No telemetry', text: 'Nothing about how you use it leaves the device.' },
  { title: 'Native', text: 'Made for iPhone, iPad and Mac, each in its own way.' },
  { title: 'AI, your key', text: 'Your own OpenAI or Anthropic key, used only when you ask.' }
]

/**
 * The first screen: the headline leads, with the word Hikki comes from as its mark — large on a wide screen, small
 * beside the headline on a phone, its meaning right under it either way — and the screenshot beside; the four
 * facts under the screenshot, where they have room at every width.
 */
function Hero() {
  return (
    <section class={`${row} grid-cols-1 lg:grid-cols-12 lg:grid-rows-[1fr_auto]`}>
      <div class="cell flex flex-col gap-8 p-8 md:p-10 lg:col-span-4 lg:row-span-2 lg:gap-10">
        <div>
          <ruby lang="ja" class="furigana text-[3rem] lg:text-[clamp(5rem,10vw,9rem)]">
            筆記<rt>ひっき</rt>
          </ruby>
          <p class="text-caption m-0 mt-3 max-w-[30rem] text-muted">
            <span lang="ja">筆記</span> (hikki) is Japanese for taking notes. Hikki sets readings
            like that above the kanji in your own pages.
          </p>
        </div>
        <div class="max-w-[34rem]">
          <h1 class="expanded text-[clamp(2.5rem,4.2vw,4.25rem)] leading-[1.02] font-[850] tracking-[-0.02em]">
            Notes that stay on your devices.
          </h1>
          <p class="mt-6 text-lg leading-relaxed text-muted">
            Hikki is a block editor for iPhone, iPad and Mac. Every page is a file in a folder you
            choose, so your writing never waits on an account or a server.
          </p>
        </div>
      </div>
      <div class="cell bg-red flex items-center justify-center p-5 md:p-8 lg:col-span-8">
        <Shot
          name="mac-hero"
          alt="Hikki on Mac: a launch plan with a cover photo, a callout, a checklist, a status list and a budget in three columns, a schedule table, furigana and an outline of the page beside it."
          width={2846}
          height={1802}
          class="w-full rounded-[12px]"
          eager
        />
      </div>
      <dl class="hero-facts m-0 grid grid-cols-2 lg:col-span-8 lg:grid-cols-4">
        <For each={HERO_FACTS}>
          {(fact) => (
            <div class="p-4 md:p-5">
              <dt class="expanded text-caption font-[800]">{fact.title}</dt>
              <dd class="m-0 mt-1 text-sm leading-snug text-muted">{fact.text}</dd>
            </div>
          )}
        </For>
      </dl>
    </section>
  )
}

function LocalFirst() {
  const facts = [
    { title: 'No account', text: 'Open the app and write. There is nothing to sign up for.' },
    { title: 'Works offline', text: 'Everything is on the device first; the network is optional.' },
    {
      title: 'Syncs through iCloud Drive',
      text: 'Put the folder there and your other devices pick up changes.'
    },
    {
      title: 'Nothing is overwritten',
      text: 'Two devices editing one page keep both versions, side by side.'
    },
    {
      title: 'Thirty days of history',
      text: 'Go back to how any page read last week, and restore it.'
    }
  ]
  return (
    <section id="local-first" class={`${row} grid-cols-1 lg:grid-cols-12`}>
      <div class="cell p-8 md:p-12 lg:col-span-5">
        <h2 class="expanded text-[clamp(1.875rem,3.4vw,3rem)] leading-[1.05] font-[850] tracking-[-0.02em]">
          Your notes are files.
        </h2>
        <p class="mt-6 max-w-[32rem] text-lg leading-relaxed text-muted">
          Each page is one small file in a folder you pick: on the device, or in iCloud Drive to
          reach every device you own. Copy it, back it up, read it with any tool. Hikki keeps a
          search index beside it and can always rebuild it from the files.
        </p>
        <pre class="border-ink bg-paper mt-8 overflow-x-auto border-4 p-5 font-mono text-sm leading-7">
          {`Notes/
  pages/
    product-launch.json
    kyoto-in-spring.json
  history/
  assets/`}
        </pre>
      </div>
      <ul class={`${row} m-0 list-none grid-cols-1 p-0 sm:grid-cols-2 lg:col-span-7`}>
        <For each={facts}>
          {(fact, index) => (
            <li
              class={`cell p-6 md:p-8 ${index() === 0 ? 'bg-yellow' : ''} ${index() === 3 ? 'bg-blue' : ''}`}
            >
              <h3 class="expanded text-xl font-[800]">{fact.title}</h3>
              <p class="mt-3 leading-relaxed text-muted">{fact.text}</p>
            </li>
          )}
        </For>
        <li class="cell bg-red hidden sm:block" aria-hidden="true" />
      </ul>
    </section>
  )
}

function Devices() {
  return (
    <section id="devices" class={`${row} grid-cols-1 lg:grid-cols-12`}>
      <div class="cell p-8 md:p-12 lg:col-span-12">
        <h2 class="expanded text-[clamp(1.875rem,3.4vw,3rem)] leading-[1.05] font-[850] tracking-[-0.02em]">
          One app for iPhone, iPad and Mac.
        </h2>
        <p class="mt-4 max-w-[40rem] text-lg leading-relaxed text-muted">
          Built natively for each, with the same pages everywhere.
        </p>
      </div>
      <figure class="cell m-0 flex flex-col gap-5 p-6 md:p-10 lg:col-span-8">
        <Shot
          name="mac"
          alt="Hikki on Mac: the page tree in a sidebar, tabs in the toolbar and a page about a product launch."
          width={2846}
          height={1802}
          class="w-full rounded-[12px]"
        />
        <figcaption class="text-caption text-muted">
          <strong class="text-ink">Mac.</strong> Native windows, tabs, menus and keyboard shortcuts.
        </figcaption>
      </figure>
      <figure class="cell bg-yellow m-0 flex flex-col items-center justify-end gap-5 p-6 md:p-10 lg:col-span-4">
        <Shot
          name="iphone-home"
          alt="Hikki on iPhone: the home screen with recent pages and quick ways to start one."
          width={1206}
          height={2622}
          class="w-[min(70%,260px)] rounded-[34px]"
        />
        <figcaption class="text-caption self-start">
          <strong>iPhone.</strong> One hand: the page tree in a drawer, actions in a floating bar.
        </figcaption>
      </figure>
      <figure class="cell bg-blue m-0 flex flex-col gap-5 p-6 md:p-10 lg:col-span-8">
        <Shot
          name="ipad"
          alt="Hikki on iPad in landscape: a product launch page beside the design notes, in split view."
          width={2752}
          height={2064}
          class="w-full rounded-[18px]"
        />
        <figcaption class="text-caption">
          <strong>iPad.</strong> Sidebar, tabs and two pages side by side.
        </figcaption>
      </figure>
      <div class="cell flex flex-col justify-between gap-8 p-8 md:p-10 lg:col-span-4">
        <p class="expanded text-2xl leading-tight font-[800]">The same pages on every device.</p>
        <Shot
          name="iphone-launch"
          alt="The same product launch page on iPhone, with its cover and milestones."
          width={1206}
          height={2622}
          class="mx-auto w-[min(62%,230px)] rounded-[30px]"
        />
        <p class="leading-relaxed text-muted">
          Put the folder in iCloud Drive and what you write on one shows up on the others.
        </p>
      </div>
    </section>
  )
}

function Features() {
  return (
    <section id="features" class={`${row} grid-cols-1 md:grid-cols-6 lg:grid-cols-12`}>
      <div class="cell p-8 md:col-span-6 md:p-12 lg:col-span-7 lg:row-span-2">
        <h2 class="expanded text-[clamp(1.875rem,3.4vw,3rem)] leading-[1.05] font-[850] tracking-[-0.02em]">
          Write in blocks.
        </h2>
        <p class="mt-6 max-w-[34rem] text-lg leading-relaxed text-muted">
          Type <kbd class="border-ink border-2 px-1.5 font-sans font-bold">/</kbd> for headings,
          to-dos, tables, toggles, callouts, code and math. Drag any block by its handle, or drop it
          beside another to make columns.
        </p>
      </div>
      <Feature
        class="bg-yellow md:col-span-3 lg:col-span-5"
        title="Search that reads everything"
        text="Titles, text, PDFs and the words in photos: in English, Chinese and Japanese, even by pinyin."
      />
      <Feature
        class="md:col-span-3 lg:col-span-5"
        title="Readings for kanji"
        text="Select a word and Hikki suggests its furigana, then sets it above the text."
      >
        <p lang="ja" class="furigana mt-6 text-[clamp(3rem,4.5vw,3.75rem)]">
          <ruby>
            毎日<rt>まいにち</rt>
          </ruby>
          <ruby>
            勉強<rt>べんきょう</rt>
          </ruby>
          する
        </p>
      </Feature>
      <Feature
        class="md:col-span-2 lg:col-span-4"
        title="Page history"
        text="Every editing session keeps the version before it. Compare them word by word."
      />
      <Feature
        class="bg-red md:col-span-2 lg:col-span-4"
        title="Comments"
        text="Comment on a passage; the thread travels with the page."
      />
      <Feature
        class="md:col-span-2 lg:col-span-4"
        title="Lock a page"
        text="Lock a finished page and nothing in it changes by accident, on any device."
      />
      <Feature
        class="md:col-span-4 lg:col-span-8"
        title="Markdown in, Markdown out"
        text="Import Markdown, HTML and text files or whole folders. Export a page or everything as Markdown, HTML, PDF or the original files."
      />
      <div class="cell bg-blue hidden md:col-span-2 md:block lg:col-span-4" aria-hidden="true" />
    </section>
  )
}

function Feature(props: { class?: string; title: string; text: string; children?: JSX.Element }) {
  return (
    <article class={`cell p-6 md:p-8 ${props.class ?? ''}`}>
      <h3 class="expanded text-xl font-[800]">{props.title}</h3>
      <p class="mt-3 max-w-[30rem] leading-relaxed text-muted">{props.text}</p>
      {props.children}
    </article>
  )
}
