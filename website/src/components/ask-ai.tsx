import { row } from './row'

/** AI: the panel beside the page and the reviewed edit of a selection. */
export function AskAI() {
  return (
    <section id="ai" class={`${row} grid-cols-1 lg:grid-cols-12`}>
      <div class="cell bg-red text-paper p-8 md:p-12 lg:col-span-12">
        <h2 class="expanded max-w-[48rem] text-[clamp(2.2rem,5vw,4.2rem)] leading-[1.02] font-[850] tracking-[-0.02em]">
          AI that works on your page, not around it.
        </h2>
        <p class="mt-6 max-w-[40rem] text-lg leading-relaxed">
          Ask about what you are reading, or select a passage and have it rewritten. It runs on your
          own OpenAI or Anthropic key, and nothing is sent until you ask.
        </p>
      </div>
      <figure class="cell m-0 flex flex-col gap-5 p-6 md:p-10 lg:col-span-8">
        <img
          src="/shots/ipad-ai-chat.png"
          alt="The AI panel beside a product launch page, answering what is left before the launch."
          width="2000"
          height="1500"
          class="shot w-full rounded-[18px]"
        />
      </figure>
      <div class="cell flex flex-col justify-end p-8 md:p-10 lg:col-span-4">
        <h3 class="expanded text-2xl leading-tight font-[800]">Ask beside the page.</h3>
        <p class="mt-4 leading-relaxed text-muted">
          The AI panel reads the page you have open and the passage you selected. Add other pages
          with @, attach a picture or a PDF, and let it search the web, with its sources linked.
        </p>
      </div>
      <div class="cell bg-blue text-paper flex flex-col justify-end p-8 md:p-10 lg:col-span-4">
        <h3 class="expanded text-2xl leading-tight font-[800]">Select, ask, review.</h3>
        <p class="mt-4 leading-relaxed">
          Improve the writing, make it shorter, change its tone or translate it. The change shows in
          the page, struck through and added, and nothing is replaced until you accept it.
        </p>
      </div>
      <figure class="cell m-0 flex flex-col gap-5 p-6 md:p-10 lg:col-span-8">
        <img
          src="/shots/ipad-ai-review.png"
          alt="An edit by AI shown in the page: the old words struck through, the new ones beside them, with Accept and Discard."
          width="1800"
          height="1117"
          class="shot w-full"
        />
      </figure>
    </section>
  )
}
