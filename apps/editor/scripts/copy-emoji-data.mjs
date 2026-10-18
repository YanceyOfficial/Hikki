// Copies the emojibase locales the picker uses into public/ so the app never fetches from a CDN.
import { cpSync, mkdirSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
for (const locale of ['en', 'zh']) {
  const out = join(root, 'public/emojibase', locale)
  mkdirSync(out, { recursive: true })
  for (const file of ['data.json', 'messages.json']) {
    cpSync(join(root, 'node_modules/emojibase-data', locale, file), join(out, file))
  }
}
