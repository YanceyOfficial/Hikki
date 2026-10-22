import { createFileRoute } from '@tanstack/solid-router'
import type { JSX } from 'solid-js'
import { For } from 'solid-js'

import { Footer } from '../components/footer'
import { Header } from '../components/header'
import { row } from '../components/row'
import { CONTACT_EMAIL, PRIVACY_PATH, SITE_URL } from '../site'

const title = 'Privacy policy · Hikki'
const description =
  'Hikki has no account and no telemetry. Your notes stay in a folder you choose; this page says what leaves the device, and when.'

export const Route = createFileRoute('/privacy')({
  head: () => ({
    meta: [
      { title },
      { name: 'description', content: description },
      { property: 'og:title', content: title },
      { property: 'og:description', content: description },
      { property: 'og:url', content: `${SITE_URL}${PRIVACY_PATH}` }
    ],
    links: [{ rel: 'canonical', href: `${SITE_URL}${PRIVACY_PATH}` }]
  }),
  component: Privacy
})

/** The date the text below last changed. */
const EFFECTIVE = '23 October 2026'

/** The short version, in the yellow cell. */
const IN_SHORT = [
  'No account. Nothing to sign up for, so there is no profile of you anywhere.',
  'No telemetry. Hikki sends nothing about how you use it, and runs no analytics.',
  'Your notes are files in a folder you choose, on your device or in your iCloud Drive. Hikki runs no server for them.',
  'Something leaves the device only when you ask for it: syncing through iCloud Drive, asking AI, searching Unsplash, opening something from the web.'
]

/**
 * The privacy policy, written from what the app does: what it stores and where, what leaves the device and when,
 * what the developer receives (nothing, unless you write).
 */
function Privacy() {
  return (
    <main class="canvas">
      <Header />
      <section class={`${row} grid-cols-1 lg:grid-cols-12`}>
        <aside class="cell bg-yellow p-8 md:p-10 lg:col-span-4">
          <h2 class="expanded text-xl font-[800]">In short</h2>
          <ul class="mt-4 list-disc space-y-3 pl-5 leading-relaxed">
            <For each={IN_SHORT}>{(line) => <li>{line}</li>}</For>
          </ul>
        </aside>
        <article class="cell p-8 md:p-12 lg:col-span-8">
          <h1 class="expanded text-[clamp(2rem,3.4vw,3rem)] leading-[1.05] font-[850] tracking-[-0.02em]">
            Privacy policy
          </h1>
          <p class="text-caption mt-3 text-muted">Effective {EFFECTIVE}.</p>
          <div class="mt-8 max-w-[66ch] space-y-10">
            <Part title="Who this is from">
              <p>
                Hikki is made by Yancey Leo. This policy covers the Hikki app for iPhone, iPad and
                Mac, and the website at hikki.yancey.app. It is written from what the app actually
                does; when the app changes in a way that matters here, the date above changes too.
              </p>
            </Part>

            <Part title="What Hikki stores, and where">
              <p>
                Everything you write stays on your devices unless you choose otherwise. Hikki has no
                account and runs no server that holds your notes.
              </p>
              <ul>
                <li>
                  <strong>Your pages</strong> are files in the folder you pick when you set Hikki
                  up: one file per page, with its history, comments, attachments and AI
                  conversations beside it. The folder is yours: copy it, back it up, read it with
                  any tool, delete it and the notes are gone. Export writes everything out as
                  Markdown, HTML, PDF or the original files.
                </li>
                <li>
                  <strong>A search index and a cache</strong> of the same pages live in the app’s
                  own storage on the device, so search is fast; both are rebuilt from your files
                  whenever needed.
                </li>
                <li>
                  <strong>Spotlight.</strong> By default, page titles and text are also given to the
                  device’s own Spotlight index, so system search finds them. This stays on the
                  device. Settings → Search turns it off and empties it.
                </li>
                <li>
                  <strong>Reminders</strong> on dates in your pages are local notifications,
                  scheduled on the device.
                </li>
                <li>
                  <strong>Your AI keys</strong> are kept in the device’s Keychain. Settings are kept
                  in the app’s preferences.
                </li>
              </ul>
            </Part>

            <Part title="What leaves the device, and when">
              <p>
                Only what you ask for, to the service you ask. Hikki itself receives none of it.
              </p>
              <ul>
                <li>
                  <strong>iCloud Drive.</strong> If you put the folder in iCloud Drive, Apple syncs
                  the files between your devices under Apple’s terms. Nothing syncs otherwise.
                </li>
                <li>
                  <strong>AI</strong>, only when you ask: Ask AI on a selection, the chat beside a
                  page, making pictures or a diagram. The request goes from your device straight to
                  the provider you chose, OpenAI or Anthropic (or the address you set for it), with
                  your own key. It carries what the task needs: the selected text and the words
                  around it, or for the chat the open page’s text (long pages are cut), any pages
                  you add with @, any picture or PDF you attach, and your question. The provider may
                  search the web for an answer; in the chat a switch turns that off. The provider’s
                  privacy policy governs what it does with the request. A key is sent only to the
                  address it was entered for.
                </li>
                <li>
                  <strong>Unsplash</strong>, when you search it for a cover: your search words go to
                  Hikki’s small server, which forwards them to Unsplash with Hikki’s key and sends
                  the results back; the photos load from Unsplash. That server logs each request’s
                  method, path, status, duration and an id, not the search words. Choosing a photo
                  is reported to Unsplash as a download, as its guidelines ask.
                </li>
                <li>
                  <strong>Links and embeds.</strong> Pasting a web link makes the device fetch that
                  page once to show its title and description (public addresses only). An embedded
                  page or video loads from its own service when you view the page that holds it; a
                  YouTube video loads through a page on Hikki’s server, so the player works, and
                  that server then sees the video’s id. Adding a picture from a web search fetches
                  it from where it is. Browsing Excalidraw’s libraries opens excalidraw.com in your
                  browser.
                </li>
              </ul>
              <p>
                That is the whole list. No analytics, no advertising, no crash reports sent to
                anyone.
              </p>
            </Part>

            <Part title="Crashes and diagnostics">
              <p>
                If Hikki crashes, the system hands it a crash report, which it keeps on the device.
                Hikki’s own log never contains page content, only ids and counts. Settings → About →
                Diagnostics lets you export the logs and reports yourself, to send along with a
                report if you choose to; nothing goes anywhere on its own.
              </p>
            </Part>

            <Part title="The website">
              <p>
                hikki.yancey.app sets no cookies and runs no analytics. Your light or dark choice is
                kept in your browser’s own storage. The site is served by Vercel, which keeps
                ordinary request logs for a short time, as any host does.
              </p>
            </Part>

            <Part title="Questions">
              <p>
                Write to{' '}
                <a
                  href={`mailto:${CONTACT_EMAIL}`}
                  class="font-semibold underline underline-offset-4"
                >
                  {CONTACT_EMAIL}
                </a>
                . If you do, your message is the only thing about you that Hikki’s maker ever holds,
                and it is kept only as long as the conversation needs.
              </p>
            </Part>
          </div>
        </article>
      </section>
      <Footer />
    </main>
  )
}

function Part(props: { title: string; children: JSX.Element }) {
  return (
    <section class="policy-part">
      <h2 class="expanded text-xl font-[800]">{props.title}</h2>
      {props.children}
    </section>
  )
}
