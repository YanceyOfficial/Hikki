/**
 * Best-effort language detection for pasted code.
 *
 * This is a small heuristic — a handful of regex signature checks against
 * common, distinctive syntax (a shebang-like opening tag, a keyword paired
 * with a structural marker, etc.), not a real parser or an ML classifier. It
 * is meant to catch the common, unambiguous cases (a Python `def`, a Rust
 * `fn`, a SQL `SELECT`) so pasting an unfenced snippet into a fresh code
 * block doesn't leave it mislabeled. It will happily miss unusual style,
 * minified code, or snippets too short to carry a distinctive signature —
 * callers should treat `undefined` as "no confident guess", never as "plain
 * text", and should never treat a returned language as a guarantee.
 */
export function guessLanguage(code: string): string | undefined {
  const trimmed = code.trim()
  if (!trimmed) {
    return undefined
  }

  if (/<\?php/.test(trimmed)) {
    return 'php'
  }

  if (/\bpackage\s+\w+/.test(trimmed) && /\bfunc\s+\w+\s*\(/.test(trimmed)) {
    return 'go'
  }

  if (
    /\bfn\s+\w+\s*\(/.test(trimmed) &&
    (/->/.test(trimmed) || /\blet\s+mut\b/.test(trimmed))
  ) {
    return 'rust'
  }

  if (/#include\b/.test(trimmed) && /\bint\s+main\s*\(/.test(trimmed)) {
    const looksLikeCpp =
      /\bstd::/.test(trimmed) ||
      /\biostream\b/.test(trimmed) ||
      /\bcout\b|\bcin\b/.test(trimmed) ||
      /\bclass\s+\w+/.test(trimmed) ||
      /\btemplate\s*</.test(trimmed) ||
      /\bnamespace\s+\w+/.test(trimmed)
    return looksLikeCpp ? 'cpp' : 'c'
  }

  const hasColonEndedLine = trimmed
    .split('\n')
    .some((line) => line.trimEnd().endsWith(':'))
  if (/\bdef\s+\w+\s*\(/.test(trimmed) && hasColonEndedLine) {
    return 'python'
  }

  if (/\bselect\b/i.test(trimmed) && /\bfrom\b/i.test(trimmed)) {
    return 'sql'
  }

  // ES-module vs CommonJS is unreliable to tell apart with regex alone, and
  // neither signal is precise enough to distinguish JavaScript from
  // TypeScript — both just map to the generic "javascript" guess.
  if (
    /\brequire\(/.test(trimmed) ||
    /\bmodule\.exports\b/.test(trimmed) ||
    /^\s*import\s+.+\s+from\s+['"]/m.test(trimmed)
  ) {
    return 'javascript'
  }

  return undefined
}
