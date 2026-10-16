import { row } from './row'

/** Split view: two pages side by side, shown on the Mac. */
export function SplitView() {
  return (
    <section id="split-view" class={`${row} grid-cols-1 lg:grid-cols-12`}>
      <div class="cell bg-yellow flex flex-col justify-between gap-10 p-8 md:p-12 lg:col-span-4">
        <h2 class="expanded text-[clamp(2rem,4vw,3.2rem)] leading-[1.05] font-[850] tracking-[-0.02em]">
          Two pages side by side.
        </h2>
        <div class="space-y-4 text-lg leading-relaxed">
          <p>
            Drag a page from the sidebar to the edge of the window and it opens beside the one you
            are writing in. Each side has its own editor.
          </p>
          <p>
            Keep notes on one side and the source on the other, or a PDF from the page. Open the
            same page twice to write in one half and read in the other.
          </p>
        </div>
      </div>
      <figure class="cell m-0 flex flex-col gap-5 p-6 md:p-10 lg:col-span-8">
        <img
          src="/shots/mac-split.webp"
          alt="Hikki on Mac in split view: a page about a trip to Kyoto beside a Japanese lesson with furigana."
          width="2846"
          height="1802"
          class="shot w-full rounded-[12px]"
        />
        <figcaption class="text-[15px] leading-relaxed text-muted">
          <strong class="text-ink">Split view on Mac.</strong> On iPad too.
        </figcaption>
      </figure>
    </section>
  )
}
