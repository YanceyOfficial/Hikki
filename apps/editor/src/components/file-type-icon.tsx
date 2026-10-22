import { type Icon } from '@phosphor-icons/react'
import { cn } from 'cn'
import type { Root } from 'react-dom/client'

import {
  FileAudioIcon,
  FileCodeIcon,
  FileCsvIcon,
  FileDocIcon,
  FileIcon,
  FileImageIcon,
  FilePdfIcon,
  FilePptIcon,
  FileTextIcon,
  FileVideoIcon,
  FileXlsIcon,
  FileZipIcon
} from '../generated/icons'
import { fileTypeOf, type FileType } from '../lib/file-types'
import { IconProvider } from './icons'

/** Each type's icon and tint, in the colours people know them by (PDF red, Word blue, Excel green…). */
const ICONS: Record<FileType, { icon: Icon; tint: string }> = {
  pdf: { icon: FilePdfIcon, tint: 'text-ink-red' },
  document: { icon: FileDocIcon, tint: 'text-ink-blue' },
  spreadsheet: { icon: FileXlsIcon, tint: 'text-ink-green' },
  csv: { icon: FileCsvIcon, tint: 'text-ink-green' },
  presentation: { icon: FilePptIcon, tint: 'text-ink-orange' },
  archive: { icon: FileZipIcon, tint: 'text-ink-brown' },
  code: { icon: FileCodeIcon, tint: 'text-ink-purple' },
  text: { icon: FileTextIcon, tint: 'text-ink-gray' },
  image: { icon: FileImageIcon, tint: 'text-ink-yellow' },
  audio: { icon: FileAudioIcon, tint: 'text-ink-pink' },
  video: { icon: FileVideoIcon, tint: 'text-ink-pink' },
  other: { icon: FileIcon, tint: 'text-muted-foreground' }
}

/** The attachment card's icon: the file's type at a glance, never a text label that can outgrow its box. */
export function FileTypeIcon({ name, className }: { name: string | null; className?: string }) {
  const type = fileTypeOf(name)
  const { icon: TypeIcon, tint } = ICONS[type]
  return <TypeIcon className={cn('size-7', tint, className)} data-file-type={type} aria-hidden />
}

/** Draws the icon into a node view's own React root (extensions/media.ts). */
export function renderFileTypeIcon(root: Root, name: string | null): void {
  root.render(
    <IconProvider>
      <FileTypeIcon name={name} />
    </IconProvider>
  )
}
