import { For } from 'solid-js'

import { LAUNCH_PRICE, PRICE, PRIVACY_PATH, REQUIREMENTS, TRIAL_DAYS } from '../site'
import { row } from './row'
import { StoreActions } from './store'

/** What the visitor should know before downloading, beside the one thing they can do today. */
const DOWNLOAD_FACTS = [
  { id: 'requirements', title: 'Runs on', text: `iPhone, iPad and Mac: ${REQUIREMENTS}.` },
  { id: 'account', title: 'Account', text: 'None. Open the app and write.' },
  {
    id: 'price',
    title: 'Price',
    text: `Free to download, with everything open for ${TRIAL_DAYS} days. Then ${PRICE}, once, for iPhone, iPad and Mac together; ${LAUNCH_PRICE} in its first weeks.`
  },
  {
    id: 'privacy',
    title: 'Privacy',
    text: 'No telemetry. Your pages are files in your folder, and AI runs on your own key, only when you ask.',
    link: { href: PRIVACY_PATH, label: 'The privacy policy' }
  },
  { id: 'roadmap', title: 'On the way', text: 'Editing a page together, on the same files.' }
] as { id: string; title: string; text: string; link?: { href: string; label: string } }[]

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
              <dd class="m-0 mt-1 max-w-[28rem] leading-relaxed text-muted">
                {fact.text}
                {fact.link && (
                  <>
                    {' '}
                    <a
                      href={fact.link.href}
                      class="text-ink font-semibold underline underline-offset-4"
                    >
                      {fact.link.label}
                    </a>
                    .
                  </>
                )}
              </dd>
            </div>
          )}
        </For>
      </dl>
    </section>
  )
}
