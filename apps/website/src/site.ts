/** Where the site lives once its DNS record exists (canonical links, social cards). */
export const SITE_URL = 'https://hikki.yancey.app'

/**
 * The App Store listing. Until Hikki is published there is none: the page says "Coming to the App Store" and offers
 * the ways to hear about it (`StoreActions`). Set the listing's URL here and every store action becomes a download
 * link.
 */
export const APP_STORE_URL: string | null = null

/**
 * Whether Hikki Community's public list is open. Closed for v1, as in the app (`PublishOptions.listingOpen`): the list has
 * no reporting or moderation yet, so nothing is listed and /community says so instead of asking CloudKit for a list.
 * Pages shared by link read at /p as ever.
 */
// ISSUE-284 opens it, together with the app's list.
export const SHARED_LIST_OPEN = false

/** Where a visitor writes to be told when Hikki ships, and for anything else. */
export const CONTACT_EMAIL = 'developer@yanceyleo.com'

/** What the app needs: the deployment targets in Project.swift. */
export const REQUIREMENTS = 'iOS 26, iPadOS 26 and macOS 26 or later'

/** The address to write to, with the subject filled in. */
export const notifyLink = (subject: string) =>
  `mailto:${CONTACT_EMAIL}?subject=${encodeURIComponent(subject)}`

/** The privacy policy: what the app stores, what leaves the device and when. The App Store listing links it too. */
export const PRIVACY_PATH = '/privacy'

/**
 * The price, decided 2026-10-23: one purchase for iPhone, iPad and Mac together; free to download with everything
 * open for 14 days, then an in-app unlock; a lower price in the first weeks after launch.
 */
export const PRICE = '$19.99'
export const LAUNCH_PRICE = '$14.99'
export const TRIAL_DAYS = 14
