import { For } from 'solid-js'

import { row } from './row'
import { Shot } from './shot'

/** What "Ask AI" on a selection offers, as the editor's menu lists it. */
const ACTIONS = [
  {
    title: 'Edit',
    items: ['Improve writing', 'Fix spelling & grammar', 'Make shorter', 'Make longer', 'Simplify']
  },
  { title: 'Change tone', items: ['Professional', 'Casual', 'Friendly', 'Confident'] },
  { title: 'Translate', items: ['English', '中文', '日本語'] },
  { title: 'Ask', items: ['Explain', 'Summarize'] }
]

/** The three ways an edit can be reviewed (Settings → AI), shown on the same sentence, each cropped to its panel. */
const REVIEW_STYLES = [
  {
    id: 'inline',
    title: 'In the page.',
    text: 'Removed words struck through, new ones beside them; Accept, Discard or ask again.',
    alt: 'An edit by AI in the page: the old words struck through and the new ones marked, with Accept and Discard.',
    width: 1080,
    height: 340
  },
  {
    id: 'diff',
    title: 'As a diff.',
    text: 'The old and the new line, one above the other, the page untouched until you accept.',
    alt: 'An edit by AI as two lines, minus and plus, with the changed words marked.',
    width: 1100,
    height: 260
  },
  {
    id: 'bubble',
    title: 'With reasons.',
    text: 'Each change on its own line, and why the model made it.',
    alt: 'An edit by AI as a list of changes, each with its reason, and a button to replace the selection.',
    width: 1100,
    height: 350
  }
]

/** AI: the panel beside the page and the reviewed edit of a selection. */
export function AskAI() {
  return (
    <section id="ai" class={`${row} grid-cols-1 lg:grid-cols-12`}>
      <div class="cell bg-red p-8 md:p-12 lg:col-span-12">
        <h2 class="expanded max-w-[48rem] text-[clamp(1.875rem,3.4vw,3rem)] leading-[1.05] font-[850] tracking-[-0.02em]">
          AI that works on your page, not around it.
        </h2>
        <p class="mt-6 max-w-[40rem] text-lg leading-relaxed">
          Ask about what you are reading, or select a passage and have it rewritten. It runs on your
          own OpenAI or Anthropic key, and nothing is sent until you ask.
        </p>
      </div>
      <figure class="cell m-0 flex flex-col gap-5 p-6 md:p-10 lg:col-span-8">
        <Shot
          name="ipad-ai-chat"
          alt="The AI panel beside a product launch page, answering what is left before the launch."
          width={2752}
          height={2064}
          class="w-full rounded-[18px]"
        />
      </figure>
      <div class="cell bg-yellow flex flex-col gap-8 p-6 md:p-10 lg:col-span-4">
        <Shot
          name="ipad-ai-panel"
          alt="Close up of the AI panel: the question and its answer, with the page attached as context."
          width={712}
          height={985}
          class="mx-auto w-full max-w-[360px] rounded-[14px]"
        />
        <div class="mt-auto">
          <h3 class="expanded text-2xl leading-tight font-[800]">Ask beside the page.</h3>
          <p class="mt-4 leading-relaxed">
            The AI panel reads the page you have open and the passage you selected. Add other pages
            with @, attach a picture or a PDF, and let it search the web, with its sources linked.
          </p>
        </div>
      </div>
      <div class="cell bg-blue flex flex-col justify-between gap-10 p-8 md:p-10 lg:col-span-4">
        <dl class="m-0 space-y-5">
          <For each={ACTIONS}>
            {(group) => (
              <div>
                <dt class="text-sm font-semibold opacity-75">{group.title}</dt>
                <dd class="m-0 mt-2 flex flex-wrap gap-2">
                  <For each={group.items}>{(item) => <span class="ai-chip">{item}</span>}</For>
                </dd>
              </div>
            )}
          </For>
        </dl>
        <div>
          <h3 class="expanded text-2xl leading-tight font-[800]">Select, ask, review.</h3>
          <p class="mt-4 leading-relaxed">
            Pick an action or say what you want. The change shows in the page, struck through and
            added, and nothing is replaced until you accept it.
          </p>
        </div>
      </div>
      <div class="cell flex flex-col justify-center gap-6 p-6 md:p-10 lg:col-span-8">
        <For each={REVIEW_STYLES}>
          {(style) => (
            <figure class="m-0">
              <Shot
                name={`review-${style.id}`}
                alt={style.alt}
                width={style.width}
                height={style.height}
                class="w-full"
              />
              <figcaption class="text-caption mt-2 text-muted">
                <strong class="text-ink">{style.title}</strong> {style.text}
              </figcaption>
            </figure>
          )}
        </For>
      </div>
    </section>
  )
}
