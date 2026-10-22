import { For } from 'solid-js'

import { REQUIREMENTS } from '../site'
import { row } from './row'
import { StoreActions } from './store'

/** What the visitor should know before downloading, beside the one thing they can do today. */
const DOWNLOAD_FACTS = [
  { id: 'requirements', title: 'Runs on', text: `iPhone, iPad and Mac: ${REQUIREMENTS}.` },
  { id: 'account', title: 'Account', text: 'None. Open the app and write.' },
  {
    id: 'privacy',
    title: 'Privacy',
    text: 'No telemetry. Your pages are files in your folder, and AI runs on your own key, only when you ask.'
  },
  { id: 'roadmap', title: 'On the way', text: 'Editing a page together, on the same files.' }
]

/** The page closes on its first claim, as the reason to download, and on what a visitor can do about it today. */
export function Closing() {
  return (
    <section id="download" class={`${row} grid-cols-1 lg:grid-cols-12`}>
      <div class="cell bg-blue flex flex-col justify-between gap-10 p-8 md:p-12 lg:col-span-7">
        <div>
          <h2 class="expanded text-[clamp(1.875rem,3.4vw,3rem)] leading-[1.05] font-[850] tracking-[-0.02em]">
            Notes that stay yours.
          </h2>
          <p class="mt-6 max-w-[36rem] text-lg leading-relaxed">
            Hikki is coming to the App Store for iPhone, iPad and Mac. Send a note to be told when
            it ships, or watch the releases.
          </p>
        </div>
        <StoreActions />
      </div>
      <dl class="cell m-0 grid grid-cols-1 gap-6 p-8 sm:grid-cols-2 md:p-12 lg:col-span-5 lg:grid-cols-1">
        <For each={DOWNLOAD_FACTS}>
          {(fact) => (
            <div id={fact.id}>
              <dt class="expanded text-caption font-[800]">{fact.title}</dt>
              <dd class="m-0 mt-1 max-w-[28rem] leading-relaxed text-muted">{fact.text}</dd>
            </div>
          )}
        </For>
      </dl>
    </section>
  )
}
