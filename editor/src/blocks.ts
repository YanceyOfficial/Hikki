import {
  CheckSquare,
  Code,
  type Icon,
  ListBullets,
  ListNumbers,
  Minus,
  Quotes,
  TextHFour,
  TextHOne,
  TextHThree,
  TextHTwo,
  TextT
} from '@phosphor-icons/react'
import type { ChainedCommands, Editor } from '@tiptap/core'

import { t } from './i18n'

/** Sections of the "/" menu, in display order. */
export const BLOCK_GROUPS = ['basic', 'lists', 'other'] as const
export type BlockGroup = (typeof BLOCK_GROUPS)[number]

/**
 * Catalog of insertable block types: the single source for the "/" menu, "Turn into" and (later) the
 * block "+" button and native menus. Aliases include Chinese, full pinyin and pinyin initials, so "/标题",
 * "/biaoti" and "/bt" all work.
 */
export type BlockType = {
  id: string
  title: string
  hint: string
  icon: Icon
  group: BlockGroup
  /** The Markdown shortcut that creates it as you type, shown at the row's end. */
  shortcut?: string
  aliases: string[]
  /** Localized display name / hint (title + aliases stay English/pinyin/Chinese for search). */
  label: () => string
  description: () => string
  /** Inserts it at the (empty) current block — the "/" menu. */
  apply: (chain: ChainedCommands) => ChainedCommands
  /**
   * Converts the current block, keeping its text ("Turn into"); absent for blocks without text (divider).
   * Lists and quotes are lifted first, so any text block can become any other.
   */
  turnInto?: (chain: ChainedCommands) => ChainedCommands
  /** Whether the selection is in this kind of block (the current item in "Turn into"). */
  isActive?: (editor: Editor) => boolean
}

export const BLOCK_TYPES: BlockType[] = [
  {
    id: 'paragraph',
    title: 'Text',
    hint: 'Plain text',
    label: () => t('blocks.paragraph.title'),
    description: () => t('blocks.paragraph.hint'),
    icon: TextT,
    group: 'basic',
    aliases: ['text', 'paragraph', 'p', '正文', '文本', 'zhengwen', 'wenben', 'zw', 'wb'],
    apply: (c) => c.setParagraph(),
    turnInto: (c) => c.clearNodes(),
    isActive: (e) =>
      e.isActive('paragraph') &&
      !e.isActive('bulletList') &&
      !e.isActive('orderedList') &&
      !e.isActive('taskList') &&
      !e.isActive('blockquote')
  },
  {
    id: 'heading1',
    title: 'Heading 1',
    hint: 'Big section heading',
    label: () => t('blocks.heading1.title'),
    description: () => t('blocks.heading1.hint'),
    icon: TextHOne,
    group: 'basic',
    shortcut: '#',
    aliases: ['h1', 'heading', 'title', '标题', '一级标题', 'biaoti', 'bt'],
    apply: (c) => c.setHeading({ level: 1 }),
    turnInto: (c) => c.clearNodes().setHeading({ level: 1 }),
    isActive: (e) => e.isActive('heading', { level: 1 })
  },
  {
    id: 'heading2',
    title: 'Heading 2',
    hint: 'Medium section heading',
    label: () => t('blocks.heading2.title'),
    description: () => t('blocks.heading2.hint'),
    icon: TextHTwo,
    group: 'basic',
    shortcut: '##',
    aliases: ['h2', 'heading', '标题', '二级标题', 'biaoti', 'bt'],
    apply: (c) => c.setHeading({ level: 2 }),
    turnInto: (c) => c.clearNodes().setHeading({ level: 2 }),
    isActive: (e) => e.isActive('heading', { level: 2 })
  },
  {
    id: 'heading3',
    title: 'Heading 3',
    hint: 'Small section heading',
    label: () => t('blocks.heading3.title'),
    description: () => t('blocks.heading3.hint'),
    icon: TextHThree,
    group: 'basic',
    shortcut: '###',
    aliases: ['h3', 'heading', '标题', '三级标题', 'biaoti', 'bt'],
    apply: (c) => c.setHeading({ level: 3 }),
    turnInto: (c) => c.clearNodes().setHeading({ level: 3 }),
    isActive: (e) => e.isActive('heading', { level: 3 })
  },
  {
    id: 'heading4',
    title: 'Heading 4',
    hint: 'Smallest section heading',
    label: () => t('blocks.heading4.title'),
    description: () => t('blocks.heading4.hint'),
    icon: TextHFour,
    group: 'basic',
    shortcut: '####',
    aliases: ['h4', 'heading', '标题', '四级标题', 'biaoti', 'bt'],
    apply: (c) => c.setHeading({ level: 4 }),
    turnInto: (c) => c.clearNodes().setHeading({ level: 4 }),
    isActive: (e) => e.isActive('heading', { level: 4 })
  },
  {
    id: 'bulletList',
    title: 'Bulleted list',
    hint: 'Simple bulleted list',
    label: () => t('blocks.bulletList.title'),
    description: () => t('blocks.bulletList.hint'),
    icon: ListBullets,
    group: 'lists',
    shortcut: '-',
    aliases: ['bullet', 'ul', 'list', '无序列表', '列表', 'liebiao', 'lb'],
    apply: (c) => c.toggleBulletList(),
    turnInto: (c) => c.clearNodes().toggleBulletList(),
    isActive: (e) => e.isActive('bulletList')
  },
  {
    id: 'orderedList',
    title: 'Numbered list',
    hint: 'List with numbering',
    label: () => t('blocks.orderedList.title'),
    description: () => t('blocks.orderedList.hint'),
    icon: ListNumbers,
    group: 'lists',
    shortcut: '1.',
    aliases: ['number', 'ol', 'ordered', '有序列表', '编号', 'bianhao', 'bh'],
    apply: (c) => c.toggleOrderedList(),
    turnInto: (c) => c.clearNodes().toggleOrderedList(),
    isActive: (e) => e.isActive('orderedList')
  },
  {
    id: 'taskList',
    title: 'To-do list',
    hint: 'Track tasks with checkboxes',
    label: () => t('blocks.taskList.title'),
    description: () => t('blocks.taskList.hint'),
    icon: CheckSquare,
    group: 'lists',
    shortcut: '[]',
    aliases: ['todo', 'task', 'check', '待办', '任务', 'daiban', 'renwu', 'db', 'rw'],
    apply: (c) => c.toggleTaskList(),
    turnInto: (c) => c.clearNodes().toggleTaskList(),
    isActive: (e) => e.isActive('taskList')
  },
  {
    id: 'blockquote',
    title: 'Quote',
    hint: 'Capture a quote',
    label: () => t('blocks.blockquote.title'),
    description: () => t('blocks.blockquote.hint'),
    icon: Quotes,
    group: 'other',
    shortcut: '"',
    aliases: ['quote', 'blockquote', '引用', 'yinyong', 'yy'],
    apply: (c) => c.toggleBlockquote(),
    turnInto: (c) => c.clearNodes().toggleBlockquote(),
    isActive: (e) => e.isActive('blockquote')
  },
  {
    id: 'codeBlock',
    title: 'Code',
    hint: 'Code block',
    label: () => t('blocks.codeBlock.title'),
    description: () => t('blocks.codeBlock.hint'),
    icon: Code,
    group: 'other',
    shortcut: '```',
    aliases: ['code', 'pre', '代码', 'daima', 'dm'],
    apply: (c) => c.toggleCodeBlock(),
    turnInto: (c) => c.clearNodes().toggleCodeBlock(),
    isActive: (e) => e.isActive('codeBlock')
  },
  {
    id: 'divider',
    title: 'Divider',
    hint: 'Visual separator',
    label: () => t('blocks.divider.title'),
    description: () => t('blocks.divider.hint'),
    icon: Minus,
    group: 'other',
    shortcut: '---',
    aliases: ['divider', 'hr', 'line', 'separator', '分割线', '分隔线', 'fengexian', 'fgx'],
    apply: (c) => c.setHorizontalRule()
  }
]

/** Ranks exact alias/title match, then prefix, then substring; empty query keeps catalog order. */
export function filterBlockTypes(query: string, types: BlockType[] = BLOCK_TYPES): BlockType[] {
  const q = query.trim().toLowerCase()
  if (!q) return types
  const score = (type: BlockType): number => {
    const keys = [
      type.title.toLowerCase(),
      type.id.toLowerCase(),
      ...type.aliases.map((a) => a.toLowerCase())
    ]
    if (keys.some((k) => k === q)) return 3
    if (keys.some((k) => k.startsWith(q) || k.split(/\s+/).some((w) => w.startsWith(q)))) return 2
    if (keys.some((k) => k.includes(q))) return 1
    return 0
  }
  return types
    .map((type, index) => ({ type, index, s: score(type) }))
    .filter((x) => x.s > 0)
    .toSorted((a, b) => b.s - a.s || a.index - b.index)
    .map((x) => x.type)
}
