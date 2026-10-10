#!/usr/bin/env bun
// Localization gate (en is the source language; zh-Hans must be complete).
// Native: keys are symbolic (`app:<area>.<element>`), in Hikki/Resources/Localization/Localizable.xcstrings.
// Web:    keys used via t('…') in editor/src, catalogs in editor/src/locales/<lang>.json.
import { readdirSync, readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const LANGS = ['en', 'zh-Hans']
const errors = []
const rel = (p) => p.replace(`${root}/`, '')

function walk(dir, ext, skip = () => false) {
  return readdirSync(dir, { withFileTypes: true }).flatMap((d) => {
    const p = join(dir, d.name)
    if (skip(p)) return []
    return d.isDirectory() ? walk(p, ext, skip) : ext.test(d.name) ? [p] : []
  })
}

/** "app:x \(a, b(c))" → "app:x %@" (balanced interpolation scan). */
function normalizeInterpolations(literal) {
  let out = ''
  for (let i = 0; i < literal.length; i++) {
    if (literal[i] === '\\' && literal[i + 1] === '(') {
      let depth = 0
      let j = i + 1
      for (; j < literal.length; j++) {
        if (literal[j] === '(') depth++
        else if (literal[j] === ')' && --depth === 0) break
      }
      out += '%@'
      i = j
    } else out += literal[i]
  }
  return out
}

/** String literals in Swift source (handles \( … "nested" … ) interpolations). */
function swiftLiterals(text) {
  const found = []
  for (let i = 0; i < text.length; i++) {
    if (text[i] !== '"' || text.startsWith('"""', i)) continue
    let j = i + 1
    let depth = 0
    for (; j < text.length; j++) {
      if (text[j] === '\\' && text[j + 1] === '(') {
        depth++
        j++
        continue
      }
      if (depth > 0 && text[j] === ')') {
        depth--
        continue
      }
      if (depth === 0 && text[j] === '\\') {
        j++
        continue
      }
      if (depth === 0 && (text[j] === '"' || text[j] === '\n')) break
    }
    found.push(text.slice(i + 1, j))
    i = j
  }
  return found
}

const placeholders = (s) => (s.match(/%(\d+\$)?(@|lld|d|f)/gu) ?? []).length

// ---------- native
const catalogPath = join(root, 'Hikki/Resources/Localization/Localizable.xcstrings')
const catalog = JSON.parse(readFileSync(catalogPath, 'utf8'))
const swiftFiles = walk(join(root, 'Hikki/Sources'), /\.swift$/u).concat(
  walk(join(root, 'HikkiUI/Sources'), /\.swift$/u, (p) => p.includes('/Generated'))
)
const usedNative = new Set()
for (const file of swiftFiles) {
  for (const lit of swiftLiterals(readFileSync(file, 'utf8'))) {
    if (lit.startsWith('app:')) usedNative.add(normalizeInterpolations(lit))
  }
}
for (const key of usedNative)
  if (!catalog.strings[key])
    errors.push(`native: "${key}" is used but missing from ${rel(catalogPath)}`)
for (const [key, entry] of Object.entries(catalog.strings)) {
  if (!usedNative.has(key)) errors.push(`native: "${key}" is in the catalog but not used`)
  for (const lang of LANGS) {
    const unit = entry.localizations?.[lang]?.stringUnit
    if (!unit?.value || unit.state !== 'translated')
      errors.push(`native: "${key}" has no translated ${lang} value`)
    else if (placeholders(unit.value) !== placeholders(key))
      errors.push(`native: "${key}" ${lang} placeholders differ from the key`)
  }
}

// Literal English in UI calls (outside #Preview blocks and the DEBUG gallery).
const UI_CALL =
  /\b(Text|Button|Label|IconLabel|Menu|ShareLink|TextField|SidebarSectionHeader|SidebarIconButton|BarIconButton|SidebarActionPill|SidebarRow|CommandMenu|ToolbarIconButton|ContentUnavailableView|navigationTitle|help|accessibilityLabel|confirmationDialog|barTitle|String\(localized:)\(\s*"(?!app:)[A-Za-z]/u
for (const file of swiftFiles.filter((f) => !f.endsWith('ComponentGallery.swift'))) {
  let inPreview = false
  let depth = 0
  readFileSync(file, 'utf8')
    .split('\n')
    .forEach((line, index) => {
      if (/^\s*#Preview\b/u.test(line)) {
        inPreview = true
        depth = 0
      }
      if (inPreview) {
        depth += (line.match(/\{/gu) ?? []).length - (line.match(/\}/gu) ?? []).length
        if (depth <= 0 && line.includes('}')) inPreview = false
        return
      }
      if (UI_CALL.test(line) && !line.includes('l10n: allow'))
        errors.push(`native: literal UI text at ${rel(file)}:${index + 1} — use an app: key`)
    })
}

// ---------- web
const localesDir = join(root, 'editor/src/locales')
const flatten = (obj, prefix = '') =>
  Object.entries(obj).flatMap(([k, v]) =>
    typeof v === 'object' ? flatten(v, `${prefix}${k}.`) : [[`${prefix}${k}`, v]]
  )
const webCatalogs = Object.fromEntries(
  LANGS.map((lang) => [
    lang,
    new Map(flatten(JSON.parse(readFileSync(join(localesDir, `${lang}.json`), 'utf8'))))
  ])
)
const usedWeb = new Set()
for (const file of walk(join(root, 'editor/src'), /\.(ts|tsx)$/u, (p) => p.includes('/locales'))) {
  for (const [, key] of readFileSync(file, 'utf8').matchAll(/\bt\(\s*'([a-zA-Z0-9_.]+)'/gu))
    usedWeb.add(key)
}
for (const key of usedWeb)
  if (!webCatalogs.en.has(key))
    errors.push(`web: '${key}' is used but missing from locales/en.json`)
for (const [key, value] of webCatalogs.en) {
  if (!usedWeb.has(key)) errors.push(`web: '${key}' is in locales/en.json but not used`)
  for (const lang of LANGS.slice(1)) {
    const translated = webCatalogs[lang].get(key)
    if (!translated) errors.push(`web: '${key}' missing from locales/${lang}.json`)
    else if (
      (translated.match(/\{\{\w+\}\}/gu) ?? []).toSorted().join() !==
      (value.match(/\{\{\w+\}\}/gu) ?? []).toSorted().join()
    ) {
      errors.push(`web: '${key}' ${lang} interpolations differ from en`)
    }
  }
}
for (const lang of LANGS.slice(1))
  for (const key of webCatalogs[lang].keys())
    if (!webCatalogs.en.has(key))
      errors.push(`web: '${key}' in locales/${lang}.json has no en source`)

if (errors.length > 0) {
  console.error(`✗ localization:\n${errors.map((e) => `  - ${e}`).join('\n')}`)
  process.exit(1)
}
console.log(
  `localization: ok (${usedNative.size} native keys, ${usedWeb.size} web keys, ${LANGS.join(' + ')})`
)
