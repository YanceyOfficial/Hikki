/** What an attachment is, by its name's extension — picks the attachment card's icon and tint. */
export type FileType =
  | 'pdf'
  | 'document'
  | 'spreadsheet'
  | 'csv'
  | 'presentation'
  | 'archive'
  | 'code'
  | 'text'
  | 'image'
  | 'audio'
  | 'video'
  | 'other'

const EXTENSIONS: Record<Exclude<FileType, 'other'>, string[]> = {
  pdf: ['pdf'],
  document: ['doc', 'docx', 'pages', 'rtf', 'odt'],
  spreadsheet: ['xls', 'xlsx', 'numbers', 'ods'],
  csv: ['csv', 'tsv'],
  presentation: ['ppt', 'pptx', 'key', 'odp'],
  archive: ['zip', 'rar', '7z', 'tar', 'gz', 'tgz', 'bz2', 'xz'],
  code: [
    'json',
    'js',
    'mjs',
    'ts',
    'tsx',
    'jsx',
    'swift',
    'py',
    'rb',
    'go',
    'rs',
    'java',
    'kt',
    'c',
    'h',
    'cpp',
    'm',
    'css',
    'html',
    'htm',
    'xml',
    'yaml',
    'yml',
    'toml',
    'sh',
    'sql'
  ],
  text: ['txt', 'md', 'markdown', 'log'],
  image: ['png', 'jpg', 'jpeg', 'gif', 'webp', 'heic', 'svg', 'avif', 'bmp', 'tif', 'tiff'],
  audio: ['mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg', 'aif', 'aiff', 'mid'],
  video: ['mp4', 'mov', 'm4v', 'webm', 'mkv', 'avi']
}

const BY_EXTENSION = new Map<string, FileType>(
  Object.entries(EXTENSIONS).flatMap(([type, extensions]) =>
    extensions.map((ext) => [ext, type as FileType] as const)
  )
)

export function fileTypeOf(name: string | null | undefined): FileType {
  if (!name?.includes('.')) return 'other'
  return BY_EXTENSION.get(name.split('.').pop()!.toLowerCase()) ?? 'other'
}
