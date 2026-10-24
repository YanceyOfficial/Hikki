# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

People deciding whether to download Hikki for their Mac, iPhone or iPad — every individual note-keeper first, the
language learners the app also serves among them (see the root `PRODUCT.md`). Confirmed with the user on 2026-10-23:
the English headline leads the page; 筆記 is its mark, not its audience.

## Product Purpose

The marketing site at hikki.yancey.app: shows the app, says what it is for, and links to the App Store once the
listing exists (`APP_STORE_URL` in `src/site.ts`). Until then the status is a line, never a button, and the foot of the
page offers what a visitor can do today: write to be told when it ships (`CONTACT_EMAIL`, a mailto for now — a
notify-me form through the BFF may replace it). Hikki is closed source: the site never links to or mentions a code
repository.

## Positioning

The root `PRODUCT.md`'s two claims, in the visitor's words: your notes stay on your devices and in your own iCloud
(CloudKit — no folder of files to show any more); AI with your own keys.

## Price

Decided 2026-10-23: one purchase for iPhone, iPad and Mac together, $19.99; free to download with everything open for
14 days, then an in-app unlock (the App Store has no trials of its own); $14.99 in the first weeks after launch.
No subscription: Hikki runs no server for notes (the user's own iCloud syncs through CloudKit, AI runs on the user's keys), so there is no
recurring cost to pass on; editing together, when it comes, may be its own add-on since it will need a server.
`PRICE`, `LAUNCH_PRICE` and `TRIAL_DAYS` in `src/site.ts` are the one place the numbers live; `Price`
(`src/components/store.tsx`) shows them in the hero and at the download, beside the store action.

## Operating Context

TanStack Start + Solid, SSR on Vercel; its own Mondrian palette (not the app's tokens); light / dark / system theme;
screenshots in `public/shots/` as WebP with dark twins, made by `bun run shots`.

## Evidence on Hand

The screenshots above, made from the real app. No testimonials, press, customers or metrics — none may be invented.
