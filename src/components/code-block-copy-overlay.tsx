import { CheckIcon, CopyIcon } from 'lucide-react'
import {
  type CSSProperties,
  type RefObject,
  useEffect,
  useRef,
  useState
} from 'react'

import { useCopyToClipboard } from '#hooks/use-copy-to-clipboard'
import { cn } from '#lib/utils'

const CODE_BLOCK_SELECTOR = '.bn-block-content[data-content-type="codeBlock"]'

interface TrackedCodeBlock {
  id: number
  element: HTMLElement
}

interface PositionedCodeBlock extends TrackedCodeBlock {
  top: number
  right: number
}

/**
 * Adds a copy-to-clipboard button over every code block rendered inside
 * `containerRef`.
 *
 * BlockNote's `createCodeBlockSpec` (see the comment above the
 * `code-block-copy` CSS rule in globals.css for the full investigation) has
 * no extension point for injecting extra UI into a codeBlock's rendered
 * output - its `render()` returns a fixed, plain-DOM NodeView with no
 * render-prop/slot.
 *
 * An earlier version of this component portaled the button in as a direct
 * DOM child of the codeBlock's own container - reusing the same element the
 * language-picker `<select>` lives in. That reliably crashed the editor:
 * ProseMirror runs its own internal `MutationObserver` over the whole
 * contentEditable tree to detect stray DOM changes it didn't cause, and a
 * foreign node appended inside a NodeView's container (one it doesn't
 * recognize as belonging to that node's `contentDOM`) reads as exactly that
 * - triggering ProseMirror's self-healing re-render, which removed the
 * button, which re-triggered our own portal effect, which re-added it,
 * looping until the tab crashed (empirically confirmed: reverting to the
 * pre-portal baseline and reproducing the same keystrokes did not crash).
 *
 * Instead, this renders a plain absolutely-positioned overlay layer as a
 * *sibling* of `<BlockNoteView>` (see editor.tsx) - entirely outside
 * ProseMirror's contentEditable subtree - and positions one button per
 * tracked code block using `getBoundingClientRect()`, recomputed on
 * scroll/resize/content-size changes. No DOM node is ever inserted inside
 * the editor's own managed tree.
 */
export function CodeBlockCopyOverlay({
  containerRef
}: {
  containerRef: RefObject<HTMLElement | null>
}) {
  const codeBlocks = useCodeBlockElements(containerRef)
  const positioned = useCodeBlockPositions(containerRef, codeBlocks)

  return (
    <div className="pointer-events-none absolute inset-0 z-10">
      {positioned.map(({ id, element, top, right }) => (
        <CodeBlockCopyButton
          key={id}
          element={element}
          style={{ top, right }}
        />
      ))}
    </div>
  )
}

/**
 * Scans `containerRef`'s subtree for codeBlock containers and keeps the list
 * in sync via a read-only `MutationObserver` (this never writes to the DOM
 * itself - see the component doc comment above for why that distinction
 * matters). A stable id (keyed off the element itself) survives block
 * reordering, so a button's transient "copied" state always stays with the
 * block it belongs to.
 *
 * Only calls `setState` when the actual set/order of elements changes -
 * typing inside a code block re-renders shiki's token spans on every
 * keystroke (a `childList` mutation), but never changes the identity of the
 * codeBlock container itself, so this stays a no-op re-render on every
 * keystroke rather than a state update.
 */
function useCodeBlockElements(containerRef: RefObject<HTMLElement | null>) {
  const [codeBlocks, setCodeBlocks] = useState<TrackedCodeBlock[]>([])
  const idsRef = useRef(new WeakMap<HTMLElement, number>())
  const nextIdRef = useRef(0)

  useEffect(() => {
    const root = containerRef.current
    if (!root) return

    const scan = () => {
      const found = Array.from(
        root.querySelectorAll<HTMLElement>(CODE_BLOCK_SELECTOR)
      )

      setCodeBlocks((prev) => {
        const unchanged =
          prev.length === found.length &&
          prev.every((tracked, index) => tracked.element === found[index])
        if (unchanged) return prev

        return found.map((element) => {
          let id = idsRef.current.get(element)
          if (id === undefined) {
            id = nextIdRef.current++
            idsRef.current.set(element, id)
          }
          return { id, element }
        })
      })
    }

    scan()
    const observer = new MutationObserver(scan)
    observer.observe(root, { childList: true, subtree: true })
    return () => observer.disconnect()
  }, [containerRef])

  return codeBlocks
}

/**
 * Computes each tracked code block's on-screen position relative to
 * `containerRef`, recomputing on window resize, scroll of any scrollable
 * ancestor (the `true` capture-phase flag matters here - scroll events don't
 * bubble, but capture-phase listeners on `window` still see them fire on any
 * descendant scroll container), and any size change of the container or an
 * individual code block (a block growing taller as more lines are typed
 * shifts every block below it).
 */
function useCodeBlockPositions(
  containerRef: RefObject<HTMLElement | null>,
  codeBlocks: TrackedCodeBlock[]
) {
  const [positions, setPositions] = useState<PositionedCodeBlock[]>([])

  useEffect(() => {
    const container = containerRef.current
    if (!container) {
      setPositions([])
      return
    }

    const recompute = () => {
      const containerRect = container.getBoundingClientRect()
      setPositions(
        codeBlocks.map(({ id, element }) => {
          const rect = element.getBoundingClientRect()
          return {
            id,
            element,
            top: rect.top - containerRect.top + 8,
            right: containerRect.right - rect.right + 8
          }
        })
      )
    }

    recompute()

    const resizeObserver = new ResizeObserver(recompute)
    resizeObserver.observe(container)
    for (const { element } of codeBlocks) resizeObserver.observe(element)

    window.addEventListener('resize', recompute)
    window.addEventListener('scroll', recompute, true)

    return () => {
      resizeObserver.disconnect()
      window.removeEventListener('resize', recompute)
      window.removeEventListener('scroll', recompute, true)
    }
  }, [containerRef, codeBlocks])

  return positions
}

function CodeBlockCopyButton({
  element,
  style
}: {
  element: HTMLElement
  style: CSSProperties
}) {
  const { copied, copy } = useCopyToClipboard()
  const label = copied ? 'Copied' : 'Copy code'

  return (
    <button
      type="button"
      data-testid="code-block-copy"
      aria-label={label}
      title={label}
      style={style}
      onClick={() => {
        const text = element.querySelector('pre code')?.textContent ?? ''
        void copy(text)
      }}
      className={cn(
        'pointer-events-auto absolute inline-flex size-6 items-center justify-center rounded-md text-[color:var(--code-block-foreground)] opacity-45 outline-none transition-opacity',
        'hover:bg-[color-mix(in_oklch,var(--code-block-foreground),transparent_88%)] hover:opacity-100',
        'focus-visible:opacity-100 focus-visible:ring-2 focus-visible:ring-ring/50'
      )}
    >
      {copied ? (
        <CheckIcon className="size-3.5" />
      ) : (
        <CopyIcon className="size-3.5" />
      )}
    </button>
  )
}
