import { createSignal, For } from 'solid-js'

import { row } from './row'
import { Shot } from './shot'

/** What "Ask AI" offers, as the editor's menus list it: on a selection, then on a picture or a PDF. */
const ACTIONS = [
  {
    title: 'Edit',
    items: [
      'Improve writing',
      'Fix spelling & grammar',
      'Make shorter',
      'Make longer',
      'Simplify language'
    ]
  },
  { title: 'Change tone', items: ['Professional', 'Casual', 'Friendly', 'Confident'] },
  { title: 'Ask', items: ['Explain', 'Summarize'] },
  { title: 'On a picture or a PDF', items: ['Describe', 'Extract text', 'Explain', 'Summarize'] }
]

/**
 * The chat's built-in tools, as HikkiAI gives them to the model: page changes (`AIPageEdits`), the provider's web
 * search, `make_picture` (`AIPictures`), attachments and @ pages, the workspace file tools (`WorkspaceFiles`, off
 * until Settings → AI turns them on) and a drawing's Text to diagram.
 */
const TOOLS = [
  {
    title: 'Edit the page',
    text: 'Rewrites, adds, moves or deletes blocks. Each change waits as a card: approve it, skip it or edit it first.'
  },
  {
    title: 'Search the web',
    text: 'Answers with their sources linked, and pictures it finds can go straight into the page. One switch turns it off.'
  },
  {
    title: 'Make pictures',
    text: 'Illustrations, covers and infographics from a sentence, or a change to a picture you attach. Needs an OpenAI key.'
  },
  {
    title: 'Read what you give it',
    text: 'The open page, the passage you selected, other pages added with @, and pictures and PDFs you attach.'
  },
  {
    title: 'Look through your workspace',
    text: 'With file use on, it lists, reads and searches the files in your workspace, your pages among them, and writes one only once you approve. Off until you turn it on.'
  },
  {
    title: 'Draw diagrams',
    text: 'In a drawing, describe a flowchart or a sequence and it is drawn as shapes you can move.'
  }
]

/** The two ways an edit can be reviewed (Settings → AI), shown on the same sentence in the whole window. */
const REVIEW_STYLES = [
  {
    id: 'inline',
    label: 'In the page',
    text: 'Removed words struck through, new ones beside them; Accept, Discard or ask again.',
    alt: 'Hikki on the Mac: an edit by AI in the page, the old words struck through and the new ones marked, with Accept and Discard under them.'
  },
  {
    id: 'diff',
    label: 'As a diff',
    text: 'The old and the new line, one above the other, the page untouched until you accept.',
    alt: 'Hikki on the Mac: an edit by AI as two lines, minus and plus, with the changed words marked.'
  }
]

/** AI: the panel beside the page, the reviewed edit of a selection and the chat's built-in tools. */
export function AskAI() {
  return (
    <section id="ai" class={`${row} grid-cols-1 lg:grid-cols-12`}>
      <div class="cell bg-red p-8 md:p-12 lg:col-span-12">
        <h2 class="expanded max-w-[48rem] text-[clamp(1.875rem,3.4vw,3rem)] leading-[1.05] font-[850] tracking-[-0.02em]">
          AI that works on your page, not around it.
        </h2>
        <p class="mt-6 max-w-[40rem] text-lg leading-relaxed">
          Ask about what you are reading, select a passage and have it rewritten, or have the chat
          change the page and approve each change. It runs on your own OpenAI or Anthropic key, and
          nothing is sent until you ask.
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
            The AI panel reads the page you have open and the passage you selected. Each page keeps
            its own conversation, on every device. Ask it to change the page and each change waits
            for your approval.
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
      <ReviewStyles />
      <div class="cell flex flex-col justify-end gap-4 p-8 md:p-10 lg:col-span-4">
        <h3 class="expanded text-2xl leading-tight font-[800]">Approve each change.</h3>
        <p class="leading-relaxed text-muted">
          Ask the chat to rework the page and every change it proposes waits as a card beside it.
          Tap one to see it in the page, then approve it, skip it or edit it first. Approve all when
          you trust the lot.
        </p>
      </div>
      <figure class="cell bg-yellow m-0 p-6 md:p-10 lg:col-span-8">
        <Shot
          name="ai-changes"
          alt="Hikki on the Mac: the AI panel beside a page, its proposed changes as cards waiting for approval, the first one shown in the page as tracked changes."
          width={2200}
          height={1369}
          class="w-full rounded-[12px]"
        />
      </figure>
      <div class={`${row} grid-cols-1 sm:grid-cols-2 lg:col-span-12 lg:grid-cols-4`}>
        <div class="cell bg-yellow p-6 sm:col-span-2 md:p-8 lg:col-span-1 lg:row-span-2">
          <h3 class="expanded text-2xl leading-tight font-[800]">Built-in tools.</h3>
          <p class="mt-4 leading-relaxed text-muted">
            The chat doesn’t only answer. It reaches for these when a question calls for them, and
            nothing it changes stays until you say so.
          </p>
        </div>
        <For each={TOOLS}>
          {(tool) => (
            <article class="cell p-6 md:p-8">
              <h4 class="expanded text-xl font-[800]">{tool.title}</h4>
              <p class="mt-3 leading-relaxed text-muted">{tool.text}</p>
            </article>
          )}
        </For>
      </div>
    </section>
  )
}

/** One edit, two ways to review it: a switch between the two windows. */
function ReviewStyles() {
  const [style, setStyle] = createSignal(REVIEW_STYLES[0].id)
  const current = () => REVIEW_STYLES.find((item) => item.id === style()) ?? REVIEW_STYLES[0]
  return (
    <figure class="cell m-0 flex flex-col gap-5 p-6 md:p-10 lg:col-span-8">
      <div class="segmented self-start" role="group" aria-label="How an edit is reviewed">
        <For each={REVIEW_STYLES}>
          {(item) => (
            <button
              type="button"
              aria-pressed={style() === item.id}
              onClick={() => setStyle(item.id)}
            >
              {item.label}
            </button>
          )}
        </For>
      </div>
      <For each={REVIEW_STYLES}>
        {(item) => (
          <div hidden={style() !== item.id}>
            <Shot
              name={`review-${item.id}`}
              alt={item.alt}
              width={2200}
              height={1369}
              class="w-full rounded-[12px]"
            />
          </div>
        )}
      </For>
      <figcaption class="text-caption text-muted">
        <strong class="text-ink">{current().label}.</strong> {current().text} Settings → AI picks
        the style.
      </figcaption>
    </figure>
  )
}
