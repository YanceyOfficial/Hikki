import type { ChainedCommands } from '@tiptap/core'

import { t } from './i18n'

/**
 * Catalog of insertable block types: the single source for the "/" menu (and later "Turn into", the
 * block "+" button and native menus). Aliases include Chinese, full pinyin and pinyin initials, so "/标题", "/biaoti" and "/bt" all work.
 */
export type BlockType = {
  id: string
  title: string
  hint: string
  icon: string
  aliases: string[]
  /** Localized display name / hint (title + aliases stay English/pinyin/Chinese for search). */
  label: () => string
  description: () => string
  apply: (chain: ChainedCommands) => ChainedCommands
}

export const BLOCK_TYPES: BlockType[] = [
  {
    id: 'paragraph',
    title: 'Text',
    hint: 'Plain text',
    label: () => t('blocks.paragraph.title'),
    description: () => t('blocks.paragraph.hint'),
    icon: 'T',
    aliases: ['text', 'paragraph', 'p', '正文', '文本', 'zhengwen', 'wenben', 'zw', 'wb'],
    apply: (c) => c.setParagraph()
  },
  {
    id: 'heading1',
    title: 'Heading 1',
    hint: 'Big section heading',
    label: () => t('blocks.heading1.title'),
    description: () => t('blocks.heading1.hint'),
    icon: 'H1',
    aliases: ['h1', 'heading', 'title', '标题', '一级标题', 'biaoti', 'bt'],
    apply: (c) => c.setHeading({ level: 1 })
  },
  {
    id: 'heading2',
    title: 'Heading 2',
    hint: 'Medium section heading',
    label: () => t('blocks.heading2.title'),
    description: () => t('blocks.heading2.hint'),
    icon: 'H2',
    aliases: ['h2', 'heading', '标题', '二级标题', 'biaoti', 'bt'],
    apply: (c) => c.setHeading({ level: 2 })
  },
  {
    id: 'heading3',
    title: 'Heading 3',
    hint: 'Small section heading',
    label: () => t('blocks.heading3.title'),
    description: () => t('blocks.heading3.hint'),
    icon: 'H3',
    aliases: ['h3', 'heading', '标题', '三级标题', 'biaoti', 'bt'],
    apply: (c) => c.setHeading({ level: 3 })
  },
  {
    id: 'bulletList',
    title: 'Bulleted list',
    hint: 'Simple bulleted list',
    label: () => t('blocks.bulletList.title'),
    description: () => t('blocks.bulletList.hint'),
    icon: '•',
    aliases: ['bullet', 'ul', 'list', '无序列表', '列表', 'liebiao', 'lb'],
    apply: (c) => c.toggleBulletList()
  },
  {
    id: 'orderedList',
    title: 'Numbered list',
    hint: 'List with numbering',
    label: () => t('blocks.orderedList.title'),
    description: () => t('blocks.orderedList.hint'),
    icon: '1.',
    aliases: ['number', 'ol', 'ordered', '有序列表', '编号', 'bianhao', 'bh'],
    apply: (c) => c.toggleOrderedList()
  },
  {
    id: 'taskList',
    title: 'To-do list',
    hint: 'Track tasks with checkboxes',
    label: () => t('blocks.taskList.title'),
    description: () => t('blocks.taskList.hint'),
    icon: '☐',
    aliases: ['todo', 'task', 'check', '待办', '任务', 'daiban', 'renwu', 'db', 'rw'],
    apply: (c) => c.toggleTaskList()
  },
  {
    id: 'blockquote',
    title: 'Quote',
    hint: 'Capture a quote',
    label: () => t('blocks.blockquote.title'),
    description: () => t('blocks.blockquote.hint'),
    icon: '❝',
    aliases: ['quote', 'blockquote', '引用', 'yinyong', 'yy'],
    apply: (c) => c.toggleBlockquote()
  },
  {
    id: 'codeBlock',
    title: 'Code',
    hint: 'Code block',
    label: () => t('blocks.codeBlock.title'),
    description: () => t('blocks.codeBlock.hint'),
    icon: '</>',
    aliases: ['code', 'pre', '代码', 'daima', 'dm'],
    apply: (c) => c.toggleCodeBlock()
  },
  {
    id: 'divider',
    title: 'Divider',
    hint: 'Visual separator',
    label: () => t('blocks.divider.title'),
    description: () => t('blocks.divider.hint'),
    icon: '—',
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
