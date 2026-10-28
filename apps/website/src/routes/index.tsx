import { createFileRoute } from '@tanstack/solid-router'
import type { JSX } from 'solid-js'
import { For } from 'solid-js'

import { AskAI } from '../components/ask-ai'
import { Closing } from '../components/closing'
import { DuoUnfold } from '../components/duo-unfold'
import { Footer } from '../components/footer'
import { Header } from '../components/header'
import { row } from '../components/row'
import { Shot } from '../components/shot'
import { SplitView } from '../components/split-view'
import { Price, StoreActions } from '../components/store'

export const Route = createFileRoute('/')({ component: Home })

function Home() {
  return (
    <main class="canvas">
      <Header />
      <Hero />
      <LocalFirst />
      <Devices />
      <DuoUnfold />
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
  { title: 'Local-first', text: 'Pages live on your device first and work offline.' },
  { title: 'No telemetry', text: 'Nothing about how you use it leaves the device.' },
  { title: 'Native', text: 'Made for iPhone, iPad and Mac, each in its own way.' },
  { title: 'AI, your key', text: 'Your own OpenAI or Anthropic key, used only when you ask.' }
]

/**
 * The first screen: the headline leads, with the word Hikki comes from as its mark — large on a wide screen, small
 * beside the headline on a phone, its meaning right under it either way — then the price and the one thing to do
 * today, and the screenshot beside; the four facts under the screenshot, where they have room at every width.
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
            Hikki is a block editor for iPhone, iPad and Mac. Every page is kept on your device and
            syncs through your own iCloud, so your writing never waits on an account or a server.
          </p>
        </div>
        <div class="mt-auto flex max-w-[34rem] flex-col items-start gap-5">
          <Price class="w-full" />
          <StoreActions />
        </div>
      </div>
      <div class="cell bg-red flex items-center justify-center p-5 md:p-8 lg:col-span-8">
        <Shot
          name="mac-hero"
          alt="Hikki on Mac: a launch plan with a cover photo, a callout, a checklist, a status list and a budget in three columns, a schedule table, furigana and an outline of the page beside it."
          width={2906}
          height={1808}
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

/** Where a page is kept, and where it never goes. */
const WHERE_PAGES_ARE = [
  { title: 'On your devices', text: 'Every page, ready offline.' },
  { title: 'In your iCloud', text: 'When you turn it on.' },
  { title: 'Nowhere else', text: 'No Hikki server holds a page.' }
]

function LocalFirst() {
  const facts = [
    { title: 'No account', text: 'Open the app and write. There is nothing to sign up for.' },
    { title: 'Works offline', text: 'Everything is on the device first; the network is optional.' },
    {
      title: 'Syncs through your iCloud',
      text: 'Changes reach your other devices in moments, page text encrypted end to end. Or keep it on this device only.'
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
          Your devices, your iCloud, no one else.
        </h2>
        <p class="mt-6 max-w-[32rem] text-lg leading-relaxed text-muted">
          Pages are kept on the device and open without a network. With iCloud on, they go to the
          private database of your own iCloud account and from there to every device you own. Export
          writes everything out as Markdown, HTML, PDF or JSON whenever you like.
        </p>
        <dl class="border-line bg-line mt-8 grid grid-cols-1 gap-1 border-4 sm:grid-cols-3">
          <For each={WHERE_PAGES_ARE}>
            {(place) => (
              <div class="bg-paper p-4">
                <dt class="expanded text-caption font-[800]">{place.title}</dt>
                <dd class="m-0 mt-1 text-sm leading-snug text-muted">{place.text}</dd>
              </div>
            )}
          </For>
        </dl>
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
          <strong>iPad.</strong> The sidebar and two pages side by side.
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
          With iCloud on, what you write on one shows up on the others.
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
          to-dos, tables, toggles, callouts, code, math, drawings and embeds. Drag any block by its
          handle, or drop it beside another to make columns.
        </p>
        <Shot
          name="blocks"
          alt="A Hikki page with a cover photo: headings, a Swift code block and a formula."
          width={1600}
          height={1220}
          class="border-ink mt-8 w-full rounded-[10px] border-2"
        />
      </div>
      <Feature
        class="bg-yellow md:col-span-3 lg:col-span-5"
        title="Search that reads everything"
        text="Titles, text, PDFs and the words in photos: in English, Chinese and Japanese, even by pinyin."
        shot={{
          name: 'search',
          width: 1400,
          height: 585,
          alt: "Hikki's search palette finding “launch” in two pages, with the matching words in bold and two more matches folded under the first."
        }}
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
        shot={{
          name: 'history',
          width: 1400,
          height: 1291,
          alt: 'Page History: versions listed by date beside the page, with removed words struck through in red and added ones in green.'
        }}
      />
      <Feature
        class="bg-red md:col-span-2 lg:col-span-4"
        title="Comments"
        text="Comment on a passage; the thread travels with the page."
        shot={{
          name: 'comments',
          width: 1400,
          height: 910,
          alt: 'A page with commented passages underlined and their threads in the side panel, one with a reply.'
        }}
      />
      <Feature
        class="md:col-span-2 lg:col-span-4"
        title="Lock a page"
        text="Lock a finished page and nothing in it changes by accident, on any device."
        shot={{
          name: 'lock',
          width: 1400,
          height: 761,
          alt: "A locked recipe page, the lock in the window's toolbar beside the star."
        }}
      />
      <Feature
        class="bg-yellow md:col-span-2 lg:col-span-4"
        title="Draw on the page"
        text="A drawing block opens an Excalidraw whiteboard in the page. Sketch by hand, or describe a flowchart and have AI draw it."
      >
        <Shot
          name="drawing"
          alt="A hand-drawn flowchart in Hikki's drawing editor: freeze build, App Review, launch, and a dashed loop through fix and resubmit."
          width={1600}
          height={980}
          class="border-ink mt-6 w-full rounded-[10px] border-2"
        />
      </Feature>
      <Feature
        class="md:col-span-2 lg:col-span-4"
        title="Markdown in, Markdown out"
        text="Import Markdown, HTML and text files or whole folders. Export a page or everything as Markdown, HTML, PDF or JSON."
        shot={{
          name: 'transfer',
          width: 1400,
          height: 984,
          alt: 'Settings → Import & Export: a drop zone for files, rows for Markdown, Hikki JSON and Notion exports, and Export workspace.'
        }}
      />
      <Feature
        class="bg-blue md:col-span-2 lg:col-span-4"
        title="Dates that remind you"
        text="Type @ and a date, like “next Friday 3pm”, and have it ring on every device."
        shot={{
          name: 'dates',
          width: 1200,
          height: 680,
          alt: 'A weekly review page with date chips such as “Tomorrow 3:00 PM” and “Monday”, each with a bell for its reminder.'
        }}
      />
      <article class="cell p-6 md:col-span-6 md:p-8 lg:col-span-12 lg:grid lg:grid-cols-12 lg:items-center lg:gap-12">
        <div class="lg:col-span-7">
          <h3 class="expanded text-xl font-[800]">Share a page</h3>
          <p class="mt-3 max-w-[34rem] leading-relaxed text-muted">
            Share makes a read-only link to a page. It is encrypted on your device and the key
            travels only in the link, so whoever you send it to reads the page in any browser and
            can save a copy into their own Hikki. Nobody without the link can read it, Apple
            included. Stop Sharing takes it down.
          </p>
          <p class="border-ink mt-6 w-fit max-w-full border-2 px-4 py-3 font-mono text-sm break-all">
            hikki.yancey.app/p/40e7d926…<span class="bg-yellow">#key-only-in-the-link</span>
          </p>
          <p class="mt-3 text-sm text-muted">The highlighted part never reaches a server.</p>
          <a href="/shared" class="mt-6 inline-block font-semibold underline underline-offset-4">
            Hikki Shared →
          </a>
        </div>
        <div class="mt-8 lg:col-span-5 lg:mt-0">
          <Shot
            name="share"
            alt="The Share sheet: “Anyone with the link” chosen, optional tags, the author's name, and what stays private."
            width={854}
            height={1326}
            class="border-ink mx-auto w-full max-w-[22rem] rounded-[10px] border-2"
          />
        </div>
      </article>
    </section>
  )
}

type FeatureShot = { name: string; width: number; height: number; alt: string }

function Feature(props: {
  class?: string
  title: string
  text: string
  shot?: FeatureShot
  children?: JSX.Element
}) {
  return (
    <article class={`cell flex flex-col p-6 md:p-8 ${props.class ?? ''}`}>
      <h3 class="expanded text-xl font-[800]">{props.title}</h3>
      <p class="mt-3 max-w-[30rem] leading-relaxed text-muted">{props.text}</p>
      {props.children}
      {props.shot && (
        <div class="mt-auto pt-6">
          <Shot
            name={props.shot.name}
            alt={props.shot.alt}
            width={props.shot.width}
            height={props.shot.height}
            class="border-ink w-full rounded-[10px] border-2"
          />
        </div>
      )}
    </article>
  )
}
