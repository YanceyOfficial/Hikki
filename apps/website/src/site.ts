/** Where the site lives once its DNS record exists (canonical links, social cards). */
export const SITE_URL = 'https://hikki.yancey.app'

/**
 * The App Store listing. Until Hikki is published there is none: the page says "Coming to the App Store" and offers
 * the ways to hear about it (`StoreActions`). Set the listing's URL here and every store action becomes a download
 * link.
 */
export const APP_STORE_URL: string | null = null

/** Where a visitor writes to be told when Hikki ships, and for anything else. */
export const CONTACT_EMAIL = 'yanceyofficial@gmail.com'

/** The source, whose releases a visitor can watch. */
export const GITHUB_URL = 'https://github.com/YanceyOfficial/Hikki'

/** What the app needs: the deployment targets in Project.swift. */
export const REQUIREMENTS = 'iOS 26, iPadOS 26 and macOS 26 or later'

/** The address to write to, with the subject filled in. */
export const notifyLink = (subject: string) =>
  `mailto:${CONTACT_EMAIL}?subject=${encodeURIComponent(subject)}`
