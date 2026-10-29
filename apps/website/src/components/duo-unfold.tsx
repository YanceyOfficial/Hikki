import { row } from './row'
import { scrollScene } from './scroll-scene'

/**
 * iPhone Duo opening as the page scrolls, like a book: folded, the outer screen (the iPhone layout); open, the inner
 * screen on its side (the iPad layout), twice the outer screen's size, its right half swinging out on the hinge in the
 * middle — `--p` 0 folded … 1 open, from the scroll (`scrollScene`).
 *
 * Without the script, or with Reduce Motion, nothing moves: the stage shows the open phone with the folded one
 * beside it (`data-still`).
 */
export function DuoUnfold() {
  scrollScene('#duo .duo-track', '#duo .duo-stage')

  return (
    <section id="duo" class={`${row} grid-cols-1`}>
      <div class="cell bg-red">
        <div class="duo-track">
          <div class="duo-sticky grid items-center gap-8 p-8 md:p-12 lg:grid-cols-12 lg:gap-12">
            <div class="lg:col-span-4">
              <h2 class="expanded text-[clamp(1.875rem,3.4vw,3rem)] leading-[1.05] font-[850] tracking-[-0.02em]">
                Ready for iPhone Duo.
              </h2>
              <p class="mt-6 max-w-[30rem] text-lg leading-relaxed">
                Folded, it's the iPhone you know, with your page's tools in the strip beside the
                camera. Open it up, and the sidebar and your page spread out side by side, just like
                on iPad.
              </p>
            </div>
            <div class="duo-stage lg:col-span-8" data-still>
              <div
                class="duo-device"
                role="img"
                aria-label="Hikki on iPhone Duo. Folded: a product launch page in the iPhone layout, with the page's actions in the strip beside the camera. Open: the same page beside the sidebar, as on iPad."
              >
                <div class="duo-half duo-left">
                  <Face name="duo-open" side="left" />
                  <span class="duo-shade" />
                </div>
                <div class="duo-half duo-right">
                  <div class="duo-front">
                    <Face name="duo-open" side="right" />
                    <span class="duo-shade" />
                  </div>
                  <div class="duo-back">
                    <Face name="iphone-duo" />
                  </div>
                </div>
              </div>
              <div class="duo-folded-still" aria-hidden="true">
                <Face name="iphone-duo" />
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  )
}

/** One screen's picture in both appearances; `side` shows only that half of the open screen. */
function Face(props: { name: string; side?: 'left' | 'right' }) {
  const cls = `duo-face ${props.side ? `duo-face-${props.side}` : ''}`
  return (
    <>
      <img src={`/shots/${props.name}.webp`} alt="" loading="lazy" class={`${cls} only-light`} />
      <img
        src={`/shots/${props.name}-dark.webp`}
        alt=""
        loading="lazy"
        class={`${cls} only-dark`}
      />
    </>
  )
}
