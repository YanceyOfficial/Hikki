import { SideMenuExtension, SuggestionMenu } from '@blocknote/core/extensions'
import {
  DragHandleMenu,
  SideMenu,
  useBlockNoteEditor,
  useComponentsContext,
  useDictionary,
  useExtension,
  useExtensionState,
  type SideMenuProps
} from '@blocknote/react'
import { GripVerticalIcon, PlusIcon } from 'lucide-react'
import { type ReactNode, useCallback } from 'react'

/**
 * Swaps BlockNote's own inline SVG icons (the "+" add-block button and the
 * "⠿" drag-handle, both from `react-icons` - `AiOutlinePlus`/
 * `MdDragIndicator` - hardcoded directly inside `@blocknote/react`'s
 * `AddBlockButton`/`DragHandleButton`, with no icon prop of their own) for
 * `lucide-react` equivalents, matching every other icon in this app.
 *
 * There's no icon-override *prop* on those two default button components
 * themselves - but `SideMenuController` (rendered by `BlockNoteView` when its
 * own `sideMenu` prop isn't `false`) does accept a `sideMenu?: FC<SideMenuProps>`
 * override, and the default `SideMenu` component it falls back to accepts
 * `children` to replace its default buttons entirely (see
 * `node_modules/@blocknote/react/src/components/SideMenu/SideMenu.tsx`:
 * `{props.children || (<><AddBlockButton/><DragHandleButton .../></>)}`).
 * `editor.tsx` wires this up by disabling the default controller
 * (`sideMenu={false}` on `BlockNoteView`) and mounting `SideMenuController`
 * itself with `sideMenu={EditorSideMenu}`.
 *
 * `EditorAddBlockButton`/`EditorDragHandleButton` below are otherwise
 * line-for-line copies of BlockNote's own `AddBlockButton.tsx`/
 * `DragHandleButton.tsx` (same hooks, same block-empty/insert-block logic,
 * same drag-start/drag-end wiring) - only the icon import changes. Keeping
 * the rest identical means this stays a pure icon swap, not a functional
 * reimplementation that could drift from upstream behavior (in particular,
 * the drag handle's `draggable`/`onDragStart`/`onDragEnd` wiring - the actual
 * mechanism block reordering depends on - is untouched).
 */
export function EditorSideMenu(props: SideMenuProps) {
  return (
    <SideMenu {...props}>
      <EditorAddBlockButton />
      <EditorDragHandleButton dragHandleMenu={props.dragHandleMenu} />
    </SideMenu>
  )
}

function EditorAddBlockButton() {
  const Components = useComponentsContext()!
  const dict = useDictionary()

  const editor = useBlockNoteEditor<any, any, any>()

  const suggestionMenu = useExtension(SuggestionMenu)
  const block = useExtensionState(SideMenuExtension, {
    editor,
    selector: (state) => state?.block
  })

  const onClick = useCallback(() => {
    if (block === undefined) {
      return
    }

    const blockContent = block.content
    const isBlockEmpty =
      blockContent !== undefined &&
      Array.isArray(blockContent) &&
      blockContent.length === 0

    if (isBlockEmpty) {
      editor.setTextCursorPosition(block)
      suggestionMenu.openSuggestionMenu('/')
    } else {
      const insertedBlock = editor.insertBlocks(
        [{ type: 'paragraph' }],
        block,
        'after'
      )[0]
      editor.setTextCursorPosition(insertedBlock)
      suggestionMenu.openSuggestionMenu('/')
    }
  }, [block, editor, suggestionMenu])

  if (block === undefined) {
    return null
  }

  return (
    <Components.SideMenu.Button
      className="bn-button"
      label={dict.side_menu.add_block_label}
      icon={<PlusIcon size={16} onClick={onClick} data-test="dragHandleAdd" />}
    />
  )
}

function EditorDragHandleButton(
  props: SideMenuProps & {
    children?: ReactNode
  }
) {
  const Components = useComponentsContext()!
  const dict = useDictionary()

  const sideMenu = useExtension(SideMenuExtension)
  const block = useExtensionState(SideMenuExtension, {
    selector: (state) => state?.block
  })

  if (block === undefined) {
    return null
  }

  const Component = props.dragHandleMenu || DragHandleMenu

  return (
    <Components.Generic.Menu.Root
      onOpenChange={(open: boolean) => {
        if (open) {
          sideMenu.freezeMenu()
        } else {
          sideMenu.unfreezeMenu()
        }
      }}
      position="left"
    >
      <Components.Generic.Menu.Trigger>
        <Components.SideMenu.Button
          label={dict.side_menu.drag_handle_label}
          draggable={true}
          onDragStart={(e) => sideMenu.blockDragStart(e, block)}
          onDragEnd={sideMenu.blockDragEnd}
          className="bn-button"
          icon={<GripVerticalIcon size={16} data-test="dragHandle" />}
        />
      </Components.Generic.Menu.Trigger>
      <Component>{props.children}</Component>
    </Components.Generic.Menu.Root>
  )
}
