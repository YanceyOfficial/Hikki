import { row } from './row'
import { scrollScene } from './scroll-scene'

/**
 * Split view: two pages side by side, shown on the Mac — and how it is opened, as the page scrolls: a page dragged
 * from the sidebar to the window's right edge, the place it will take outlined, its pane sliding in from that edge,
 * then the page beside it settling into its half. Two captures of the same window (`mac-split-solo`, `mac-split`);
 * `--p` from the scroll (`scrollScene`). Still — no script, Reduce Motion — it is the split window.
 */
export function SplitView() {
  scrollScene('#split-view', '#split-view .split-stage')

  return (
    <section id="split-view" class={`${row} split-scene grid-cols-1 lg:grid-cols-12`}>
      <div class="cell bg-yellow split-text lg:col-span-4">
        <div class="split-sticky flex flex-col justify-between gap-10 p-8 md:p-12">
          <h2 class="expanded text-[clamp(1.875rem,3.4vw,3rem)] leading-[1.05] font-[850] tracking-[-0.02em]">
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
      </div>
      <figure class="cell split-figure m-0 lg:col-span-8">
        <div class="split-sticky flex flex-col justify-center gap-5 p-6 md:p-10">
          <div
            class="split-stage"
            data-still
            role="img"
            aria-label="Hikki on Mac: “Japanese, week 3” dragged from the sidebar to the window's right edge opens beside a page about a trip to Kyoto, in split view."
          >
            <Capture name="mac-split-solo" class="split-solo" />
            <span class="split-zone" />
            <div class="split-pane">
              <Capture name="mac-split" />
            </div>
            <div class="split-final">
              <Capture name="mac-split" />
            </div>
            <span class="split-chip">
              <span aria-hidden="true">🗾</span> Japanese, week 3
            </span>
          </div>
          <figcaption class="text-caption text-muted">
            <strong class="text-ink">Split view on Mac.</strong> On iPad too.
          </figcaption>
        </div>
      </figure>
    </section>
  )
}

/** One capture of the window in both appearances; the theme shows one. */
function Capture(props: { name: string; class?: string }) {
  const cls = `split-img ${props.class ?? ''}`
  return (
    <>
      <img
        src={`/shots/${props.name}.webp`}
        alt=""
        width={2906}
        height={1808}
        loading="lazy"
        class={`${cls} only-light`}
      />
      <img
        src={`/shots/${props.name}-dark.webp`}
        alt=""
        width={2906}
        height={1808}
        loading="lazy"
        class={`${cls} only-dark`}
      />
    </>
  )
}
