import { type Icon } from '@phosphor-icons/react'
import type { ChainedCommands, Editor } from '@tiptap/core'
import type { ComponentType } from 'react'

import {
  AirtableLogo,
  CalendlyLogo,
  CodeSandboxLogo,
  DrawioLogo,
  ExcalidrawLogo,
  FigmaLogo,
  GitHubLogo,
  GoogleDriveLogo,
  LoomLogo,
  MiroLogo,
  type LogoProps
} from '../components/brand-logos'
import { lastCodeLanguage } from '../extensions/code-languages'
import { openEmbedPanel } from '../extensions/embed'
import { openMathEditor } from '../extensions/math'
import { pickFiles, type MediaHost } from '../extensions/media'
import { openToggleAtSelection } from '../extensions/toggle'
import {
  BrowserIcon,
  CaretCircleRightIcon,
  CheckSquareIcon,
  CodeBlockIcon,
  CodeIcon,
  ColumnsIcon,
  FilmStripIcon,
  FunctionIcon,
  ImageSquareIcon,
  InfoIcon,
  ListBulletsIcon,
  ListMagnifyingGlassIcon,
  ListNumbersIcon,
  MinusIcon,
  MusicNotesIcon,
  PaperclipIcon,
  ScribbleIcon,
  QuotesIcon,
  SigmaIcon,
  TableIcon,
  TextHFourIcon,
  TextHOneIcon,
  TextHThreeIcon,
  TextHTwoIcon,
  TextTIcon
} from '../generated/icons'
import { drawingsReadOnly } from '../lib/drawing-mode'
import { t } from './i18n'

/** Sections of the "/" menu, in display order. */
export const BLOCK_GROUPS = ['basic', 'lists', 'media', 'embeds', 'other', 'advanced'] as const
export type BlockGroup = (typeof BLOCK_GROUPS)[number]

/**
 * Catalog of insertable block types: the single source for the "/" menu, "Turn into" and (later) the
 * block "+" button and native menus. Aliases include Chinese, full pinyin and pinyin initials, so "/标题",
 * "/biaoti" and "/bt" all work.
 */
/** A Phosphor icon, or a service's logo (the Embeds group). */
export type BlockIcon = Icon | ComponentType<LogoProps>

export type BlockType = {
  id: string
  title: string
  hint: string
  icon: BlockIcon
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
  /** Runs after `apply` (e.g. open the formula editor on the new equation). */
  after?: (editor: Editor) => void
  /** Whether it can be added on this device now (absent: always) — a drawing isn't, on a phone. */
  available?: () => boolean
}

/** The blocks that can be added here (the "/" menu, the touch "+" panel). */
export const isAvailable = (type: BlockType): boolean => type.available?.() ?? true

/** Set by the editor for "/" media items (the file picker needs the bridge). */
let mediaHost: MediaHost | null = null
export function setMediaHost(host: MediaHost | null): void {
  mediaHost = host
}

export const BLOCK_TYPES: BlockType[] = [
  {
    id: 'paragraph',
    title: 'Text',
    hint: 'Plain text',
    label: () => t('blocks.paragraph.title'),
    description: () => t('blocks.paragraph.hint'),
    icon: TextTIcon,
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
    icon: TextHOneIcon,
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
    icon: TextHTwoIcon,
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
    icon: TextHThreeIcon,
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
    icon: TextHFourIcon,
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
    icon: ListBulletsIcon,
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
    icon: ListNumbersIcon,
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
    icon: CheckSquareIcon,
    group: 'lists',
    shortcut: '[]',
    aliases: ['todo', 'task', 'check', '待办', '任务', 'daiban', 'renwu', 'db', 'rw'],
    apply: (c) => c.toggleTaskList(),
    turnInto: (c) => c.clearNodes().toggleTaskList(),
    isActive: (e) => e.isActive('taskList')
  },
  {
    id: 'toggle',
    title: 'Toggle list',
    hint: 'Hide content inside',
    label: () => t('blocks.toggle.title'),
    description: () => t('blocks.toggle.hint'),
    icon: CaretCircleRightIcon,
    group: 'lists',
    shortcut: '>',
    aliases: ['toggle', 'details', 'collapse', '折叠', '折叠列表', 'zhedie', 'zd'],
    apply: (c) => c.setDetails(),
    turnInto: (c) => c.clearNodes().setDetails(),
    isActive: (e) => e.isActive('details'),
    after: (editor) => openToggleAtSelection(editor)
  },
  {
    id: 'image',
    title: 'Image',
    hint: 'Upload an image',
    label: () => t('blocks.image.title'),
    description: () => t('blocks.image.hint'),
    icon: ImageSquareIcon,
    group: 'media',
    aliases: ['image', 'picture', 'photo', 'img', '图片', '图像', 'tupian', 'tp'],
    apply: (c) => c,
    after: (editor) => {
      if (mediaHost) pickFiles(editor, mediaHost, 'image')
    }
  },
  {
    id: 'video',
    title: 'Video',
    hint: 'Upload a video',
    label: () => t('blocks.video.title'),
    description: () => t('blocks.video.hint'),
    icon: FilmStripIcon,
    group: 'media',
    aliases: ['video', 'movie', 'mp4', '视频', 'shipin', 'sp'],
    apply: (c) => c,
    after: (editor) => {
      if (mediaHost) pickFiles(editor, mediaHost, 'video')
    }
  },
  {
    id: 'audio',
    title: 'Audio',
    hint: 'Upload audio',
    label: () => t('blocks.audio.title'),
    description: () => t('blocks.audio.hint'),
    icon: MusicNotesIcon,
    group: 'media',
    aliases: ['audio', 'sound', 'music', 'mp3', '音频', '音乐', 'yinpin', 'yp'],
    apply: (c) => c,
    after: (editor) => {
      if (mediaHost) pickFiles(editor, mediaHost, 'audio')
    }
  },
  {
    id: 'file',
    title: 'File',
    hint: 'Attach a file',
    label: () => t('blocks.file.title'),
    description: () => t('blocks.file.hint'),
    icon: PaperclipIcon,
    group: 'media',
    aliases: [
      'file',
      'attachment',
      'pdf',
      'upload',
      '文件',
      '附件',
      'wenjian',
      'fujian',
      'wj',
      'fj'
    ],
    apply: (c) => c,
    after: (editor) => {
      if (mediaHost) pickFiles(editor, mediaHost, 'file')
    }
  },
  {
    id: 'drawing',
    title: 'Drawing',
    hint: 'Sketch or diagram by hand',
    label: () => t('blocks.drawing.title'),
    description: () => t('blocks.drawing.hint'),
    icon: ScribbleIcon,
    group: 'media',
    aliases: [
      'drawing',
      'draw',
      'sketch',
      'diagram',
      'whiteboard',
      'excalidraw',
      '绘图',
      '画图',
      '手绘',
      '白板',
      'huitu',
      'huatu',
      'shouhui',
      'ht'
    ],
    apply: (c) => c.insertDrawing(),
    // Drawings are read-only on a phone-sized screen (too small to draw on): opened to look at, never added there.
    available: () => !drawingsReadOnly()
  },
  // Embeds (Notion's): each opens the link panel for its service; the block itself is the same frame.
  {
    id: 'embed',
    title: 'Embed',
    hint: 'A link, shown on the page',
    label: () => t('blocks.embed.title'),
    description: () => t('blocks.embed.hint'),
    icon: BrowserIcon,
    group: 'embeds',
    // Services without a row of their own still embed through it: video, maps, posts, players, pens.
    aliases: [
      'embed',
      'iframe',
      'website',
      'youtube',
      'vimeo',
      'codepen',
      'maps',
      'tweet',
      'spotify',
      'typeform',
      '嵌入',
      'qianru',
      'qr'
    ],
    apply: (c) => c,
    after: (editor) => openEmbedPanel(editor, 'generic')
  },
  {
    id: 'html',
    title: 'HTML',
    hint: 'A snippet of HTML, in a sandbox',
    label: () => t('blocks.html.title'),
    description: () => t('blocks.html.hint'),
    icon: CodeBlockIcon,
    group: 'embeds',
    aliases: ['html', 'snippet', '网页', 'wangye', 'wy'],
    apply: (c) => c,
    after: (editor) => openEmbedPanel(editor, 'html')
  },
  {
    id: 'googleDrive',
    title: 'Google Drive',
    hint: 'A Doc, Sheet, Slides or Drive file',
    label: () => t('blocks.googleDrive.title'),
    description: () => t('blocks.googleDrive.hint'),
    icon: GoogleDriveLogo,
    group: 'embeds',
    aliases: [
      'google drive',
      'drive',
      'google docs',
      'docs',
      'sheets',
      'slides',
      '谷歌云盘',
      '谷歌文档',
      '表格',
      '幻灯片',
      'guge',
      'gg'
    ],
    apply: (c) => c,
    after: (editor) => openEmbedPanel(editor, 'googleDrive')
  },
  {
    id: 'figma',
    title: 'Figma',
    hint: 'A Figma design, board or prototype',
    label: () => t('blocks.figma.title'),
    description: () => t('blocks.figma.hint'),
    icon: FigmaLogo,
    group: 'embeds',
    aliases: ['figma', 'figjam', 'design', 'prototype', '设计稿', '原型', 'shejigao', 'sjg'],
    apply: (c) => c,
    after: (editor) => openEmbedPanel(editor, 'figma')
  },
  {
    id: 'miro',
    title: 'Miro',
    hint: 'A Miro board',
    label: () => t('blocks.miro.title'),
    description: () => t('blocks.miro.hint'),
    icon: MiroLogo,
    group: 'embeds',
    aliases: ['miro', 'board', 'whiteboard', '白板', 'baiban', 'bb'],
    apply: (c) => c,
    after: (editor) => openEmbedPanel(editor, 'miro')
  },
  {
    id: 'loom',
    title: 'Loom',
    hint: 'A Loom video',
    label: () => t('blocks.loom.title'),
    description: () => t('blocks.loom.hint'),
    icon: LoomLogo,
    group: 'embeds',
    aliases: ['loom', 'video', 'screen recording', '录屏', 'luping', 'lp'],
    apply: (c) => c,
    after: (editor) => openEmbedPanel(editor, 'loom')
  },
  {
    id: 'airtable',
    title: 'Airtable',
    hint: 'A shared Airtable view',
    label: () => t('blocks.airtable.title'),
    description: () => t('blocks.airtable.hint'),
    icon: AirtableLogo,
    group: 'embeds',
    aliases: ['airtable', 'table', 'base', 'database', '数据表', 'shujubiao', 'sjb'],
    apply: (c) => c,
    after: (editor) => openEmbedPanel(editor, 'airtable')
  },
  {
    id: 'calendly',
    title: 'Calendly',
    hint: 'A booking page to schedule a meeting',
    label: () => t('blocks.calendly.title'),
    description: () => t('blocks.calendly.hint'),
    icon: CalendlyLogo,
    group: 'embeds',
    aliases: [
      'calendly',
      'schedule',
      'meeting',
      'booking',
      '日程',
      '预约',
      '会议',
      'richeng',
      'yuyue',
      'huiyi',
      'rc',
      'yy'
    ],
    apply: (c) => c,
    after: (editor) => openEmbedPanel(editor, 'calendly')
  },
  {
    id: 'gist',
    title: 'GitHub Gist',
    hint: 'A gist, styled like the page',
    label: () => t('blocks.gist.title'),
    description: () => t('blocks.gist.hint'),
    icon: GitHubLogo,
    group: 'embeds',
    aliases: ['gist', 'github', 'snippet', '代码片段', '片段', 'pianduan', 'pd'],
    apply: (c) => c,
    after: (editor) => openEmbedPanel(editor, 'gist')
  },
  {
    id: 'codesandbox',
    title: 'CodeSandbox',
    hint: 'A sandbox, running',
    label: () => t('blocks.codesandbox.title'),
    description: () => t('blocks.codesandbox.hint'),
    icon: CodeSandboxLogo,
    group: 'embeds',
    aliases: ['codesandbox', 'sandbox', 'code', '代码沙盒', 'shahe', 'sh'],
    apply: (c) => c,
    after: (editor) => openEmbedPanel(editor, 'codesandbox')
  },
  {
    id: 'drawio',
    title: 'draw.io',
    hint: 'A diagram from draw.io (diagrams.net)',
    label: () => t('blocks.drawio.title'),
    description: () => t('blocks.drawio.hint'),
    icon: DrawioLogo,
    group: 'embeds',
    aliases: [
      'draw.io',
      'drawio',
      'diagrams',
      'diagram',
      'flowchart',
      '流程图',
      '图表',
      'liuchengtu',
      'lct'
    ],
    apply: (c) => c,
    after: (editor) => openEmbedPanel(editor, 'drawio')
  },
  {
    id: 'excalidraw',
    title: 'Excalidraw',
    hint: 'An Excalidraw drawing',
    label: () => t('blocks.excalidraw.title'),
    description: () => t('blocks.excalidraw.hint'),
    icon: ExcalidrawLogo,
    group: 'embeds',
    aliases: ['excalidraw', 'whiteboard', 'sketch', 'drawing', '手绘', '白板', 'shouhui', 'sh'],
    // A drawing block of our own (Excalidraw in the page, its AI inside its editor), not a link to excalidraw.com;
    // a pasted excalidraw.com link still embeds through Embed.
    apply: (c) => c.insertDrawing(),
    available: () => !drawingsReadOnly()
  },
  {
    id: 'blockquote',
    title: 'Quote',
    hint: 'Capture a quote',
    label: () => t('blocks.blockquote.title'),
    description: () => t('blocks.blockquote.hint'),
    icon: QuotesIcon,
    group: 'other',
    shortcut: '"',
    aliases: ['quote', 'blockquote', '引用', 'yinyong', 'yy'],
    apply: (c) => c.toggleBlockquote(),
    turnInto: (c) => c.clearNodes().toggleBlockquote(),
    isActive: (e) => e.isActive('blockquote')
  },
  {
    id: 'callout',
    title: 'Callout',
    hint: 'Make writing stand out',
    label: () => t('blocks.callout.title'),
    description: () => t('blocks.callout.hint'),
    icon: InfoIcon,
    group: 'other',
    aliases: ['callout', 'note', 'tip', 'info', '标注', '提示', 'biaozhu', 'tishi', 'bz', 'ts'],
    apply: (c) => c.setCallout(),
    turnInto: (c) => c.clearNodes().setCallout(),
    isActive: (e) => e.isActive('callout')
  },
  {
    id: 'codeBlock',
    title: 'Code',
    hint: 'Code block',
    label: () => t('blocks.codeBlock.title'),
    description: () => t('blocks.codeBlock.hint'),
    icon: CodeIcon,
    group: 'other',
    shortcut: '```',
    aliases: ['code', 'pre', '代码', 'daima', 'dm'],
    apply: (c) => c.toggleCodeBlock({ language: lastCodeLanguage() }),
    turnInto: (c) => c.clearNodes().toggleCodeBlock({ language: lastCodeLanguage() }),
    isActive: (e) => e.isActive('codeBlock')
  },
  {
    id: 'divider',
    title: 'Divider',
    hint: 'Visual separator',
    label: () => t('blocks.divider.title'),
    description: () => t('blocks.divider.hint'),
    icon: MinusIcon,
    group: 'other',
    shortcut: '---',
    aliases: ['divider', 'hr', 'line', 'separator', '分割线', '分隔线', 'fengexian', 'fgx'],
    apply: (c) => c.setHorizontalRule()
  },
  {
    id: 'table',
    title: 'Table',
    hint: 'Rows and columns',
    label: () => t('blocks.table.title'),
    description: () => t('blocks.table.hint'),
    icon: TableIcon,
    group: 'advanced',
    aliases: ['table', 'grid', 'spreadsheet', '表格', 'biaoge', 'bg'],
    apply: (c) => c.insertTable({ rows: 3, cols: 3, withHeaderRow: true })
  },
  {
    id: 'columns2',
    title: '2 columns',
    hint: '2 side-by-side columns',
    label: () => t('blocks.columns2.title'),
    description: () => t('blocks.columns2.hint'),
    icon: ColumnsIcon,
    group: 'advanced',
    aliases: ['columns', 'column', 'layout', '2', '2col', '分栏', '两栏', 'fenlan', 'fl'],
    apply: (c) => c.insertColumns(2)
  },
  {
    id: 'columns3',
    title: '3 columns',
    hint: '3 side-by-side columns',
    label: () => t('blocks.columns3.title'),
    description: () => t('blocks.columns3.hint'),
    icon: ColumnsIcon,
    group: 'advanced',
    aliases: ['columns', 'column', 'layout', '3', '3col', '分栏', '三栏', 'fenlan', 'fl'],
    apply: (c) => c.insertColumns(3)
  },
  {
    id: 'columns4',
    title: '4 columns',
    hint: '4 side-by-side columns',
    label: () => t('blocks.columns4.title'),
    description: () => t('blocks.columns4.hint'),
    icon: ColumnsIcon,
    group: 'advanced',
    aliases: ['columns', 'column', 'layout', '4', '4col', '分栏', '四栏', 'fenlan', 'fl'],
    apply: (c) => c.insertColumns(4)
  },
  {
    id: 'tableOfContents',
    title: 'Table of contents',
    hint: 'Links to the headings on this page',
    label: () => t('blocks.tableOfContents.title'),
    description: () => t('blocks.tableOfContents.hint'),
    icon: ListMagnifyingGlassIcon,
    group: 'advanced',
    aliases: ['toc', 'contents', 'outline', '目录', 'mulu', 'ml'],
    apply: (c) => c.insertContent({ type: 'tableOfContents' })
  },
  {
    id: 'blockMath',
    title: 'Block equation',
    hint: 'Display a formula (LaTeX)',
    label: () => t('blocks.blockMath.title'),
    description: () => t('blocks.blockMath.hint'),
    icon: SigmaIcon,
    group: 'advanced',
    shortcut: '$$$',
    aliases: ['math', 'equation', 'latex', 'tex', 'formula', '公式', '数学', 'gongshi', 'gs'],
    apply: (c) => c.insertContent({ type: 'blockMath', attrs: { latex: '' } }),
    after: (editor) => {
      const pos = findNear(editor, 'blockMath')
      if (pos !== null) openMathEditor(editor, pos, 'block')
    }
  },
  {
    id: 'inlineMath',
    title: 'Inline equation',
    hint: 'A formula within text (LaTeX)',
    label: () => t('blocks.inlineMath.title'),
    description: () => t('blocks.inlineMath.hint'),
    icon: FunctionIcon,
    group: 'advanced',
    shortcut: '$$',
    aliases: [
      'math',
      'equation',
      'inline',
      'latex',
      'formula',
      '公式',
      '行内公式',
      'gongshi',
      'gs'
    ],
    apply: (c) => c.insertContent({ type: 'inlineMath', attrs: { latex: '' } }),
    after: (editor) => {
      const pos = findNear(editor, 'inlineMath')
      if (pos !== null) openMathEditor(editor, pos, 'inline')
    }
  }
]

/** The position of the nearest `type` node at or before the caret (the one just inserted). */
function findNear(editor: Editor, type: string): number | null {
  const { from } = editor.state.selection
  let found: number | null = null
  editor.state.doc.nodesBetween(
    Math.max(0, from - 4),
    Math.min(editor.state.doc.content.size, from + 1),
    (node, pos) => {
      if (node.type.name === type) found = pos
    }
  )
  return found
}

/** Ranks exact alias/title match, then prefix, then substring; empty query keeps catalog order. */
export function filterBlockTypes(
  query: string,
  types: BlockType[] = BLOCK_TYPES.filter(isAvailable)
): BlockType[] {
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
