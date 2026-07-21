#!/usr/bin/env node
// Copies the English-locale emojibase-data files that frimousse's
// `EmojiPicker.Root` fetches at runtime (`{emojibaseUrl}/en/data.json` and
// `{emojibaseUrl}/en/messages.json`, see node_modules/frimousse/dist/index.js)
// from node_modules into public/, so Vite serves them same-origin instead of
// EmojiPicker.Root defaulting to fetching from cdn.jsdelivr.net at runtime -
// Hikki is local-first/offline-first and must never depend on a CDN for a
// first-open UI feature.
//
// Runs ahead of `vite`/`vite build` (see package.json's `dev`/`build`
// scripts) rather than being committed to the repo: emojibase-data's raw
// data.json is ~750KB, already tracked as a pinned dependency in
// package.json/pnpm-lock.yaml, and regenerating it here keeps that ~750KB
// out of git history instead of duplicating it.
import { copyFileSync, mkdirSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const rootDir = join(dirname(fileURLToPath(import.meta.url)), '..')
const srcDir = join(rootDir, 'node_modules/emojibase-data/en')
const destDir = join(rootDir, 'public/emojibase-data/en')

mkdirSync(destDir, { recursive: true })
for (const file of ['data.json', 'messages.json']) {
  copyFileSync(join(srcDir, file), join(destDir, file))
}

console.log(`copy-emojibase-data: synced en/{data,messages}.json -> ${destDir}`)
