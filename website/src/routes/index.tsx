import { createFileRoute } from '@tanstack/solid-router'
import type { JSX } from 'solid-js'
import { For } from 'solid-js'

import { AppStoreButton } from '../components/app-store-button'
import { AskAI } from '../components/ask-ai'
import { Footer } from '../components/footer'
import { row } from '../components/row'
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
      <Together />
      <Footer />
    </main>
  )
}

function Header() {
  return (
    <header class={`${row} grid-cols-1 md:grid-cols-12`}>
      <a href="/" class="cell flex items-center gap-3 p-5 md:col-span-3" aria-label="Hikki home">
        <img src="/icon.png" alt="" width="44" height="44" class="rounded-[10px]" />
        <img src="/wordmark.svg" alt="Hikki" class="h-11 w-auto" />
      </a>
      <nav class="cell flex flex-wrap items-center gap-x-8 gap-y-2 p-5 text-[15px] font-semibold md:col-span-6">
        <a href="#local-first" class="underline-offset-4 hover:underline">
          Local-first
        </a>
        <a href="#devices" class="underline-offset-4 hover:underline">
          iPhone, iPad, Mac
        </a>
        <a href="#ai" class="underline-offset-4 hover:underline">
          AI
        </a>
        <a href="#features" class="underline-offset-4 hover:underline">
          Features
        </a>
      </nav>
      <div class="cell flex items-center p-5 md:col-span-3 md:justify-end">
        <AppStoreButton />
      </div>
    </header>
  )
}

function Hero() {
  return (
    <section class={`${row} grid-cols-1 lg:grid-cols-12 lg:grid-rows-[1fr_auto]`}>
      <div class="cell flex flex-col justify-between gap-10 p-8 md:p-12 lg:col-span-7 lg:row-span-2">
        <ruby class="furigana self-start text-[clamp(7rem,22vw,17rem)]" aria-label="Hikki (筆記)">
          筆記<rt>ひっき</rt>
        </ruby>
        <div class="max-w-[34rem]">
          <h1 class="expanded text-[clamp(2.4rem,5vw,4.2rem)] leading-[1.02] font-[850] tracking-[-0.02em]">
            Notes that stay on your devices.
          </h1>
          <p class="mt-6 text-lg leading-relaxed text-muted">
            Hikki is a block editor for iPhone, iPad and Mac. Every page is a file in a folder you
            choose, so your writing never waits on an account or a server.
          </p>
        </div>
      </div>
      <div class="cell bg-red flex items-end justify-center overflow-hidden px-8 pt-10 lg:col-span-5">
        <img
          src="/shots/iphone-page.png"
          alt="Hikki on iPhone: a page called Japanese, week 3, with furigana above the kanji."
          width="736"
          height="1600"
          class="shot w-[min(68%,300px)] translate-y-[4px] rounded-t-[36px] border-b-0"
        />
      </div>
      <div class={`${row} grid-cols-[1fr_2fr] lg:col-span-5`}>
        <div class="cell bg-yellow" />
        <p class="cell bg-blue text-paper p-6 text-[15px] leading-relaxed">
          <span lang="ja">筆記</span> (hikki) is Japanese for taking notes. Hikki shows readings
          like that above the kanji in your own pages.
        </p>
      </div>
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
        <h2 class="expanded text-[clamp(2rem,4vw,3.2rem)] leading-[1.05] font-[850] tracking-[-0.02em]">
          Your notes are files.
        </h2>
        <p class="mt-6 max-w-[32rem] text-lg leading-relaxed text-muted">
          Each page is one small file in a folder you pick: on the device, or in iCloud Drive to
          reach every device you own. Copy it, back it up, read it with any tool. Hikki keeps a
          search index beside it and can always rebuild it from the files.
        </p>
        <pre class="border-ink bg-paper mt-8 overflow-x-auto border-4 p-5 font-mono text-[14px] leading-7">
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
              class={`cell p-6 md:p-8 ${index() === 0 ? 'bg-yellow' : ''} ${index() === 3 ? 'bg-blue text-paper' : ''}`}
            >
              <h3 class="expanded text-xl font-[800]">{fact.title}</h3>
              <p class={`mt-3 leading-relaxed ${index() === 3 ? '' : 'text-muted'}`}>{fact.text}</p>
            </li>
          )}
        </For>
        <li class="cell bg-red" aria-hidden="true" />
      </ul>
    </section>
  )
}

function Devices() {
  return (
    <section id="devices" class={`${row} grid-cols-1 lg:grid-cols-12`}>
      <div class="cell p-8 md:p-12 lg:col-span-12">
        <h2 class="expanded text-[clamp(2rem,4vw,3.2rem)] leading-[1.05] font-[850] tracking-[-0.02em]">
          One app for iPhone, iPad and Mac.
        </h2>
        <p class="mt-4 max-w-[40rem] text-lg leading-relaxed text-muted">
          Built natively for each, with the same pages everywhere.
        </p>
      </div>
      <figure class="cell m-0 flex flex-col gap-5 p-6 md:p-10 lg:col-span-8">
        <img
          src="/shots/mac.png"
          alt="Hikki on Mac: the page tree in a sidebar, tabs in the toolbar and a page about a product launch."
          width="1800"
          height="1139"
          class="shot w-full rounded-[12px]"
        />
        <figcaption class="text-[15px] leading-relaxed text-muted">
          <strong class="text-ink">Mac.</strong> Native windows, tabs, menus and keyboard shortcuts.
        </figcaption>
      </figure>
      <figure class="cell bg-yellow m-0 flex flex-col items-center justify-end gap-5 p-6 md:p-10 lg:col-span-4">
        <img
          src="/shots/iphone-home.png"
          alt="Hikki on iPhone: the home screen with recent pages and quick ways to start one."
          width="736"
          height="1600"
          class="shot w-[min(70%,260px)] rounded-[34px]"
        />
        <figcaption class="self-start text-[15px] leading-relaxed">
          <strong>iPhone.</strong> One hand: the page tree in a drawer, actions in a floating bar.
        </figcaption>
      </figure>
      <figure class="cell bg-blue text-paper m-0 flex flex-col gap-5 p-6 md:p-10 lg:col-span-8">
        <img
          src="/shots/ipad.png"
          alt="Hikki on iPad in landscape: a product launch page beside the design notes, in split view."
          width="2000"
          height="1500"
          class="shot w-full rounded-[18px]"
        />
        <figcaption class="text-[15px] leading-relaxed">
          <strong>iPad.</strong> Sidebar, tabs and two pages side by side.
        </figcaption>
      </figure>
      <div class="cell flex flex-col justify-between gap-8 p-8 md:p-10 lg:col-span-4">
        <p class="expanded text-2xl leading-tight font-[800]">The same pages on every device.</p>
        <p class="leading-relaxed text-muted">
          Put the folder in iCloud Drive and what you write on one shows up on the others. Two
          devices editing the same page keep both versions.
        </p>
      </div>
    </section>
  )
}

function Features() {
  return (
    <section id="features" class={`${row} grid-cols-1 md:grid-cols-6 lg:grid-cols-12`}>
      <div class="cell p-8 md:col-span-6 md:p-12 lg:col-span-7 lg:row-span-2">
        <h2 class="expanded text-[clamp(2rem,4vw,3.2rem)] leading-[1.05] font-[850] tracking-[-0.02em]">
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
        <p lang="ja" class="furigana mt-5 text-4xl">
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
        class="bg-red text-paper md:col-span-2 lg:col-span-4"
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
      <div class="cell bg-blue md:col-span-2 lg:col-span-4" aria-hidden="true" />
    </section>
  )
}

function Feature(props: { class?: string; title: string; text: string; children?: JSX.Element }) {
  return (
    <article class={`cell p-6 md:p-8 ${props.class ?? ''}`}>
      <h3 class="expanded text-xl font-[800]">{props.title}</h3>
      <p class="mt-3 max-w-[30rem] leading-relaxed opacity-80">{props.text}</p>
      {props.children}
    </article>
  )
}

function Together() {
  return (
    <section class={`${row} grid-cols-1 lg:grid-cols-12`}>
      <div class="cell bg-yellow lg:col-span-1" aria-hidden="true" />
      <div class="cell bg-blue text-paper p-8 md:p-12 lg:col-span-8">
        <h2 class="expanded text-[clamp(2rem,4vw,3.2rem)] leading-[1.05] font-[850] tracking-[-0.02em]">
          Editing together is on its way.
        </h2>
        <p class="mt-6 max-w-[36rem] text-lg leading-relaxed">
          Share a page and write in it with someone else, at the same time. It is in development
          now, built on the same files, so your notes stay yours.
        </p>
      </div>
      <div class="cell flex items-end p-8 md:p-12 lg:col-span-3">
        <AppStoreButton />
      </div>
    </section>
  )
}
