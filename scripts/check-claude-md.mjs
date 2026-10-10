#!/usr/bin/env bun
// Fails when CLAUDE.md references a repository path that does not exist (docs drift).
import { existsSync, readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const text = readFileSync(join(root, 'CLAUDE.md'), 'utf8')
const candidates = new Set()
// `inline code` and the first column of the structure block.
for (const [, code] of text.matchAll(/`([^`\s]+)`/gu)) candidates.add(code)
for (const [, path] of text.matchAll(
  /^([A-Za-z.][\w./-]*\/[\w./-]*|[\w-]+\.(?:swift|json|mjs|sh|md))\s/gmu
))
  candidates.add(path)

const looksLikePath = (s) =>
  /^[\w.-]+(\/[\w.-]+)+\/?$/u.test(s) ||
  /^[\w-]+\.(swift|json|mjs|sh|md|ts|tsx|css|xcconfig)$/u.test(s)
const missing = [...candidates].filter(
  (p) => looksLikePath(p) && !p.startsWith('http') && !existsSync(join(root, p))
)
if (missing.length > 0) {
  console.error(`CLAUDE.md references missing paths:\n${missing.map((p) => `  - ${p}`).join('\n')}`)
  process.exit(1)
}
console.log(`CLAUDE.md paths: ok (${[...candidates].filter(looksLikePath).length} checked)`)
