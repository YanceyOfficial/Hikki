import { useComponentsContext } from '@blocknote/react'
import { SparklesIcon } from 'lucide-react'

/**
 * Entry point for the "Writing Tools" popover (its body arrives in a later
 * task - this button only opens it). Rendered as one more item inside the
 * formatting toolbar's own item list (see editor.tsx's
 * `FormattingToolbarController` wiring), so it has to render through the
 * same shared-components mechanism BlockNote's own default toolbar buttons
 * use rather than a plain `<button>` - confirmed against the installed
 * `@blocknote/react@0.51.4` source (not just the docs) before writing this:
 * `BasicTextStyleButton`/`CreateLinkButton`
 * (`node_modules/@blocknote/react/src/components/FormattingToolbar/DefaultButtons/{BasicTextStyleButton,CreateLinkButton}.tsx`)
 * both render via `Components.FormattingToolbar.Button` from
 * `useComponentsContext()` - not `Components.Generic.Toolbar.Button`, which
 * exists (`ComponentsContext.tsx`) but is reserved for toolbars outside the
 * formatting-toolbar/link-toolbar family. `@blocknote/shadcn`'s
 * implementation of that slot (`toolbar/Toolbar.tsx`'s `ToolbarButton`) is
 * the same `bn-button`-classed, tooltip-wrapped shadcn button every other
 * formatting-toolbar button renders as - so this one matches their look and
 * keyboard/focus behavior for free.
 */
export function WritingToolsButton({ onClick }: { onClick: () => void }) {
  const Components = useComponentsContext()!

  return (
    <Components.FormattingToolbar.Button
      mainTooltip="Writing Tools (⌘J)"
      onClick={onClick}
      data-testid="writing-tools-button"
    >
      <SparklesIcon className="size-4" />
    </Components.FormattingToolbar.Button>
  )
}
