/**
 * Languages the code block offers (all registered with lowlight's `common` grammar set, plus `auto`,
 * which lets lowlight guess). Names are the languages' own names, not translated; `plaintext` and `auto`
 * get their labels from the catalog.
 */
export type CodeLanguage = { id: string; name: string; aliases?: string[] }

export const CODE_LANGUAGES: CodeLanguage[] = [
  { id: 'auto', name: 'Auto-detect', aliases: ['detect'] },
  { id: 'plaintext', name: 'Plain text', aliases: ['text', 'txt'] },
  { id: 'bash', name: 'Bash', aliases: ['sh', 'zsh'] },
  { id: 'c', name: 'C', aliases: ['h'] },
  { id: 'cpp', name: 'C++', aliases: ['c++', 'cc', 'hpp'] },
  { id: 'csharp', name: 'C#', aliases: ['cs', 'c#'] },
  { id: 'css', name: 'CSS' },
  { id: 'diff', name: 'Diff', aliases: ['patch'] },
  { id: 'go', name: 'Go', aliases: ['golang'] },
  { id: 'graphql', name: 'GraphQL', aliases: ['gql'] },
  { id: 'xml', name: 'HTML / XML', aliases: ['html', 'svg', 'xhtml'] },
  { id: 'ini', name: 'INI / TOML', aliases: ['toml'] },
  { id: 'java', name: 'Java' },
  { id: 'javascript', name: 'JavaScript', aliases: ['js', 'jsx', 'mjs'] },
  { id: 'json', name: 'JSON' },
  { id: 'kotlin', name: 'Kotlin', aliases: ['kt'] },
  { id: 'less', name: 'Less' },
  { id: 'lua', name: 'Lua' },
  { id: 'makefile', name: 'Makefile', aliases: ['make'] },
  { id: 'markdown', name: 'Markdown', aliases: ['md'] },
  { id: 'objectivec', name: 'Objective-C', aliases: ['objc', 'm'] },
  { id: 'perl', name: 'Perl' },
  { id: 'php', name: 'PHP' },
  { id: 'python', name: 'Python', aliases: ['py'] },
  { id: 'r', name: 'R' },
  { id: 'ruby', name: 'Ruby', aliases: ['rb'] },
  { id: 'rust', name: 'Rust', aliases: ['rs'] },
  { id: 'scss', name: 'SCSS', aliases: ['sass'] },
  { id: 'shell', name: 'Shell session', aliases: ['console'] },
  { id: 'sql', name: 'SQL' },
  { id: 'swift', name: 'Swift' },
  { id: 'typescript', name: 'TypeScript', aliases: ['ts', 'tsx'] },
  { id: 'wasm', name: 'WebAssembly' },
  { id: 'yaml', name: 'YAML', aliases: ['yml'] }
]

/** The catalog entry for a stored language id or alias (e.g. "ts" from a ```ts fence); null if unknown. */
export function findLanguage(id: string | null | undefined): CodeLanguage | null {
  if (!id) return null
  const key = id.toLowerCase()
  return CODE_LANGUAGES.find((l) => l.id === key || l.aliases?.includes(key)) ?? null
}

export function filterLanguages(query: string): CodeLanguage[] {
  const q = query.trim().toLowerCase()
  if (!q) return CODE_LANGUAGES
  return CODE_LANGUAGES.filter(
    (l) =>
      l.name.toLowerCase().includes(q) ||
      l.id.includes(q) ||
      l.aliases?.some((a) => a.startsWith(q))
  )
}

const LAST_KEY = 'hikki.codeLanguage'

/** New code blocks start in the language last picked (per device; Notion does the same). */
export function lastCodeLanguage(): string {
  try {
    return findLanguage(localStorage.getItem(LAST_KEY))?.id ?? 'plaintext'
  } catch {
    return 'plaintext'
  }
}

export function rememberCodeLanguage(id: string): void {
  try {
    localStorage.setItem(LAST_KEY, id)
  } catch {
    // Storage may be unavailable (private mode); the default stays plain text.
  }
}
