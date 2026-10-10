import i18n from 'i18next'
import { initReactI18next } from 'react-i18next'

import en from './locales/en.json'
import zhHans from './locales/zh-Hans.json'

/** Languages the editor ships (en is the source catalog; `bun scripts/l10n-audit.mjs` gates parity). */
export const LOCALES = ['en', 'zh-Hans'] as const
export type Locale = (typeof LOCALES)[number]

/** Best supported match for a BCP-47 tag ("zh-Hans-CN", "zh-CN" → zh-Hans; anything else → en). */
export function resolveLocale(tag: string | undefined): Locale {
  const lower = (tag ?? '').toLowerCase()
  if (lower.startsWith('zh') && !/-(hant|tw|hk|mo)\b/u.test(lower)) return 'zh-Hans'
  return 'en'
}

void i18n.use(initReactI18next).init({
  resources: { en: { translation: en }, 'zh-Hans': { translation: zhHans } },
  lng: resolveLocale(globalThis.navigator?.language),
  fallbackLng: 'en',
  interpolation: { escapeValue: false }, // React escapes
  returnNull: false
})

export const t = i18n.t.bind(i18n)

/** Called by the native shell (window.hikki.setLocale) with the app's language. */
export function setLocale(tag: string): Locale {
  const locale = resolveLocale(tag)
  void i18n.changeLanguage(locale)
  document.documentElement.lang = locale
  return locale
}

export default i18n
