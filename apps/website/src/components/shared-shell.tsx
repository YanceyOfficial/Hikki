import { Link } from '@tanstack/solid-router'
import { For, type JSX } from 'solid-js'

import { APP_STORE_URL, CONTACT_EMAIL, PRIVACY_PATH } from '../site'
import { ThemeSwitch } from './theme-switch'
import { Wordmark } from './wordmark'

/** The main site's sections, linked from the bar (`narrow`: kept on a narrow window too). */
const SITE_LINKS = [
  { label: 'Home', href: '/', narrow: true },
  { label: 'Features', href: '/#features', narrow: false },
  { label: 'AI', href: '/#ai', narrow: false },
  { label: 'Devices', href: '/#devices', narrow: false },
  { label: 'Pricing', href: '/#price', narrow: false },
  { label: 'Privacy', href: PRIVACY_PATH, narrow: false }
]

/**
 * Hikki Shared's own frame (`/shared`, `/shared/<record>`, `/p/<record>`) — not the marketing site's canvas: a page
 * someone published reads like a page in Hikki, on the app's paper and ink (`.shared` in styles.css), under a quiet
 * bar — Hikki Shared's mark (the logo labelled Shared, to the list), the main site's sections, Apple's App Store
 * badge, the appearance switch — and a short foot.
 */
export function SharedShell(props: { children: JSX.Element; report?: string }) {
  return (
    <div class="shared">
      <header class="shared-bar">
        <div class="shared-bar-inner">
          {/* Hikki Shared's own mark: the app's logo with a "Shared" label at its top right — home for this frame. */}
          <Link to="/shared" class="shared-brand" aria-label="Hikki Shared">
            <img src="/icon.png" alt="" class="shared-brand-icon" />
            <span class="shared-brand-mark">
              <Wordmark class="shared-brand-word" />
              <span class="shared-brand-label">Shared</span>
            </span>
          </Link>
          {/* Hikki's own site, a section at a time — the way out of this frame. */}
          <nav class="shared-site" aria-label="Hikki">
            <For each={SITE_LINKS}>
              {(link) => (
                <a href={link.href} class={link.narrow ? '' : 'max-lg:hidden'}>
                  {link.label}
                </a>
              )}
            </For>
          </nav>
          <div class="shared-bar-end">
            <a
              href={APP_STORE_URL ?? '/'}
              class="shared-badge"
              aria-label="Download Hikki on the App Store"
            >
              {/* Apple's own badge, black on light paper and white on dark. */}
              <img src="/badges/app-store-black.svg" alt="" class="shared-badge-light" />
              <img src="/badges/app-store-white.svg" alt="" class="shared-badge-dark" />
            </a>
            <ThemeSwitch class="shared-theme" />
          </div>
        </div>
      </header>
      <main class="shared-main">{props.children}</main>
      <footer class="shared-foot">
        <div class="shared-foot-inner">
          <span>Published with Hikki. Pages here are their authors' own.</span>
          <nav class="flex flex-wrap gap-4">
            <a href={PRIVACY_PATH}>Privacy</a>
            <a href={`mailto:${CONTACT_EMAIL}`}>Contact</a>
            {props.report ? <a href={props.report}>Report this page</a> : null}
          </nav>
        </div>
      </footer>
    </div>
  )
}

/** The mail that reports a page, its record named in the subject. */
export const reportLink = (id: string) =>
  `mailto:${CONTACT_EMAIL}?subject=${encodeURIComponent(`Report a published page: ${id}`)}`

export function SearchIcon() {
  return (
    <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" fill="none">
      <circle cx="11" cy="11" r="6.5" stroke="currentColor" stroke-width="2" />
      <path d="m16 16 4.5 4.5" stroke="currentColor" stroke-width="2" stroke-linecap="round" />
    </svg>
  )
}

export function SaveIcon() {
  return (
    <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" fill="none">
      <path
        d="M12 4v10m0 0-4-4m4 4 4-4M5 15v3.5A1.5 1.5 0 0 0 6.5 20h11a1.5 1.5 0 0 0 1.5-1.5V15"
        stroke="currentColor"
        stroke-width="2"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
    </svg>
  )
}

export function LinkIcon() {
  return (
    <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" fill="none">
      <path
        d="M10 14a4 4 0 0 0 5.66 0l3-3a4 4 0 0 0-5.66-5.66l-1 1M14 10a4 4 0 0 0-5.66 0l-3 3a4 4 0 0 0 5.66 5.66l1-1"
        stroke="currentColor"
        stroke-width="2"
        stroke-linecap="round"
      />
    </svg>
  )
}

export function GridIcon() {
  return (
    <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" fill="none">
      <rect x="4" y="4" width="6.5" height="6.5" rx="1.5" stroke="currentColor" stroke-width="2" />
      <rect
        x="13.5"
        y="4"
        width="6.5"
        height="6.5"
        rx="1.5"
        stroke="currentColor"
        stroke-width="2"
      />
      <rect
        x="4"
        y="13.5"
        width="6.5"
        height="6.5"
        rx="1.5"
        stroke="currentColor"
        stroke-width="2"
      />
      <rect
        x="13.5"
        y="13.5"
        width="6.5"
        height="6.5"
        rx="1.5"
        stroke="currentColor"
        stroke-width="2"
      />
    </svg>
  )
}

export function ClearIcon() {
  return (
    <svg viewBox="0 0 24 24" width="16" height="16" aria-hidden="true" fill="none">
      <path
        d="m7 7 10 10M17 7 7 17"
        stroke="currentColor"
        stroke-width="2"
        stroke-linecap="round"
      />
    </svg>
  )
}
