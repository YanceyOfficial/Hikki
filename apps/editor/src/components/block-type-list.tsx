import { TURN_INTO, type BlockType } from '../core/blocks'
import { CheckIcon } from '../generated/icons'
import { MenuRow, MenuTitle } from './menu-row'

/**
 * "Turn into": every kind a block can become, the current one checked. Shared by the selection menu and the
 * block menu, which say what picking one does.
 */
export function BlockTypeList({
  title,
  current,
  onPick
}: {
  title: string
  /** The catalog id of the block's kind now. */
  current: string | null
  onPick: (block: BlockType) => void
}) {
  return (
    <>
      <MenuTitle>{title}</MenuTitle>
      {TURN_INTO.map((block) => (
        <MenuRow
          key={block.id}
          role="menuitemradio"
          aria-checked={block.id === current}
          onClick={() => onPick(block)}
        >
          <block.icon size={18} className="text-subtle-foreground" aria-hidden />
          <span className="flex-1 truncate">{block.label()}</span>
          {block.id === current && <CheckIcon size={14} aria-hidden />}
        </MenuRow>
      ))}
    </>
  )
}
