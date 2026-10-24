/**
 * Error text that may go into the native log: logs never contain page content (CLAUDE.md), and error messages
 * often quote it — ProseMirror's `Invalid content for node doc: <paragraph("…")>`, `Position 3 outside of fragment
 * (…)`, a JSON parser's unexpected token. What's kept is the error's name and its message up to the first place
 * that could start a quote of something (`: `, `(`, `<`, quotes), capped; a lone identifier after the colon (a node
 * or mark type: `Unknown node type: futureBlock`) is a schema name, not content, and stays.
 */
export function safeErrorMessage(error: unknown): string {
  if (error instanceof Error) {
    const name = error.name && error.name !== 'Error' ? error.name : ''
    const message = safeMessageText(error.message)
    return name ? (message ? `${name}: ${message}` : name) : message
  }
  return safeMessageText(typeof error === 'string' ? error : String(error))
}

const MAX = 160
const QUOTE_START = /\(|<|\[|\{|"|'|`/u

/** A message string (not an Error) cut as `safeErrorMessage` cuts one: `Uncaught RangeError: …` keeps its name. */
export function safeMessageText(text: string): string {
  let rest = text.trim()
  // `Uncaught TypeError: …` (an ErrorEvent's message) and `RangeError: …` keep the name in front.
  const named = /^((?:Uncaught\s+)?(?:\w*Error|Exception))(?::\s*|$)/u.exec(rest)
  const prefix = named ? named[1] : ''
  if (named) rest = rest.slice(named[0].length)
  const colon = rest.indexOf(': ')
  if (colon >= 0) {
    const after = rest.slice(colon + 2).trim()
    rest = /^[A-Za-z_][\w-]{0,40}$/u.test(after)
      ? `${rest.slice(0, colon)}: ${after}`
      : rest.slice(0, colon)
  }
  // From the second character: a message may start with its own tag (`[tiptap error]`).
  const quote = rest.slice(1).search(QUOTE_START)
  if (quote >= 0) rest = rest.slice(0, quote + 1)
  rest = rest.trim().replace(/[\s,;:.]+$/u, '')
  if (rest.length > MAX) rest = `${rest.slice(0, MAX)}…`
  return prefix ? (rest ? `${prefix}: ${rest}` : prefix) : rest
}

/**
 * A stack trace without its message: V8 puts `Name: message` (quoting whatever the message quotes) on its first
 * lines, WebKit doesn't. Only frame lines (`    at f (file:1:2)`, `f@file:1:2`) are kept.
 */
export function safeStack(stack: unknown): string {
  if (typeof stack !== 'string') return ''
  return stack
    .split('\n')
    .filter((line) => /^\s+at\s/u.test(line) || /^[\w$.<>/\s]*@\S+:\d+:\d+$/u.test(line))
    .join('\n')
}
