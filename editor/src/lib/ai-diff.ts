/** A run of a text diff: kept, removed (only in the old text) or added (only in the new). */
export type DiffSegment = { type: 'same' | 'del' | 'add'; text: string }

const CJK = /[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Hangul}]/u

/**
 * The units a diff compares: a CJK character on its own (those scripts have no spaces between words), otherwise a word
 * with the spaces after it, or a lone punctuation mark — so "the quick fox" → "the fast fox" changes one word rather
 * than a few letters.
 */
export function diffUnits(text: string): string[] {
  const units: string[] = []
  let word = ''
  for (const char of text) {
    if (CJK.test(char) || /[\p{P}\p{S}]/u.test(char)) {
      if (word) units.push(word)
      word = ''
      units.push(char)
    } else if (/\s/u.test(char)) {
      word += char
      units.push(word)
      word = ''
    } else {
      word += char
    }
  }
  if (word) units.push(word)
  return units
}

/** Above this many units on both sides, the diff gives up on alignment: everything removed, everything added. */
const MAX_CELLS = 4_000_000

/**
 * How `before` became `after`: a longest-common-subsequence diff over `diffUnits`, adjacent runs of a kind merged.
 * Very long texts (quadratic table) fall back to one removal and one addition.
 */
export function diffText(before: string, after: string): DiffSegment[] {
  const a = diffUnits(before)
  const b = diffUnits(after)
  if (a.length * b.length > MAX_CELLS) {
    return [
      ...(before ? [{ type: 'del' as const, text: before }] : []),
      ...(after ? [{ type: 'add' as const, text: after }] : [])
    ]
  }
  const n = a.length
  const m = b.length
  const width = m + 1
  const table = new Uint32Array((n + 1) * width)
  for (let i = n - 1; i >= 0; i--) {
    for (let j = m - 1; j >= 0; j--) {
      table[i * width + j] =
        a[i] === b[j]
          ? table[(i + 1) * width + j + 1] + 1
          : Math.max(table[(i + 1) * width + j], table[i * width + j + 1])
    }
  }
  const out: DiffSegment[] = []
  const push = (type: DiffSegment['type'], text: string) => {
    const last = out.at(-1)
    if (last?.type === type) last.text += text
    else out.push({ type, text })
  }
  let i = 0
  let j = 0
  while (i < n && j < m) {
    if (a[i] === b[j]) {
      push('same', a[i])
      i++
      j++
    } else if (table[(i + 1) * width + j] >= table[i * width + j + 1]) {
      push('del', a[i])
      i++
    } else {
      push('add', b[j])
      j++
    }
  }
  while (i < n) push('del', a[i++])
  while (j < m) push('add', b[j++])
  return out
}

/** How many separate changes a diff holds (a removal right next to an addition counts once). */
export function changeCount(segments: DiffSegment[]): number {
  let count = 0
  let inChange = false
  for (const segment of segments) {
    if (segment.type === 'same') inChange = false
    else if (!inChange) {
      count++
      inChange = true
    }
  }
  return count
}

/** Each change as what it replaced and with what (either side may be empty), in order — `changeCount` of them. */
export function changePairs(segments: DiffSegment[]): { from: string; to: string }[] {
  const pairs: { from: string; to: string }[] = []
  let current: { from: string; to: string } | null = null
  for (const segment of segments) {
    if (segment.type === 'same') {
      current = null
      continue
    }
    if (!current) {
      current = { from: '', to: '' }
      pairs.push(current)
    }
    if (segment.type === 'del') current.from += segment.text
    else current.to += segment.text
  }
  return pairs
}

/** One side of a diff: the old text (`del` and `same`) or the new (`add` and `same`). */
export function diffSide(segments: DiffSegment[], side: 'before' | 'after'): string {
  const skip = side === 'before' ? 'add' : 'del'
  return segments
    .filter((segment) => segment.type !== skip)
    .map((segment) => segment.text)
    .join('')
}
