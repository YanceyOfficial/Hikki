# App Store material

Everything the App Store Connect record (app 6824055991: one record, iOS and macOS — universal purchase, the same
bundle id `app.yancey.hikki`) asks for that isn't the build.

```
metadata/<locale>/        name, subtitle, promotional text, description, keywords, release notes, URLs
                          (fastlane `deliver` layout: one .txt per field; en-US is the primary language)
metadata/*.txt            copyright, categories
demo-workspace.py         the demo workspace every screenshot is taken over (also the website's)
covers.json               its cover photos (Unsplash, hotlinked, with their photographers)
shoot.sh                  one screenshot on a simulator (iPad: --landscape, through HikkiUITests/StoreScreenshot)
mac-frame.mjs             a Mac window capture on the 2880 × 1800 backdrop
```

Limits: name and subtitle 30 characters, promotional text 170, keywords 100 (comma-separated, no spaces needed),
description 4000. Promotional text can change without a new build; everything else rides with a version.

## Screenshots

| Set         | Size (px)   | Simulator             | Notes                                                      |
| ----------- | ----------- | --------------------- | ---------------------------------------------------------- |
| iPhone 6.9" | 1320 × 2868 | iPhone 17 Pro Max     | the one iPhone set required; smaller iPhones scale it down |
| iPad 13"    | 2752 × 2064 | iPad Pro 13-inch (M5) | landscape, as Hikki lays out an iPad (`--landscape`)       |
| Mac         | 2880 × 1800 | the Mac itself        | a window on a backdrop, 16:10                              |

Up to ten per set; the first three show in search results. The same English set serves every locale unless a
localized one is uploaded.

```sh
python3 design/store/demo-workspace.py /tmp/demo        # just the workspace, to look at
design/store/shoot.sh <udid> iphone-1.png HIKKI_DEBUG_NAV=en-f725dda9d6d5
design/store/shoot.sh <udid> ipad-1.png --landscape HIKKI_DEBUG_NAV=en-b2e3a009d7fc
```

The Mac set: launch a Debug build of your own (`DYLD_FRAMEWORK_PATH=<products>/Debug`, `HIKKI_DATA_DIR` = the demo
workspace's data folder, `HIKKI_WORKSPACE=Personal`, `-ApplePersistenceIgnoreState YES -appearance light`) with the
same hooks, capture its window by id (`screencapture -x -l <window id> window.png` — the id from
`CGWindowListCopyWindowInfo`), then `node design/store/mac-frame.mjs window.png mac-1.png`. Never `pkill -f Hikki`.

## App Store Connect, field by field

- **Category**: Productivity, then Education (language study).
- **Age rating**: no objectionable content of our own. Answer yes where it asks about unrestricted web access (embeds
  and links open web pages) and about AI that generates content (Ask AI, pictures); the rating follows from those.
- **App privacy**: Data Not Collected. Pages, history, comments and chats stay on the user's devices and, with iCloud on,
  in their own iCloud private database (CloudKit; page contents in encrypted fields), which we can't read; diagnostics stay
  on the device until the user exports them. What leaves the device goes where the user sends it — AI requests to
  OpenAI / Anthropic on the user's own key, link previews to the linked site, Unsplash searches through the BFF,
  which keeps nothing — none of it is collected by us. Keep this in step with `apps/website/src/routes/privacy.tsx`.
- **Privacy policy URL**: https://hikki.yancey.app/privacy. **Support URL**: https://hikki.yancey.app.
- **Export compliance**: `ITSAppUsesNonExemptEncryption` is false in the Info.plist (HTTPS only), so uploads skip
  the question.
- **Content rights**: the app shows third-party content (Unsplash photos through their API, embedded pages, web
  search results) — answer yes, with the rights to it (Unsplash's API terms: hotlinked, attributed, downloads
  reported).
- **Review notes** (draft):
  > No account is needed: the app opens on a new workspace. AI features need an OpenAI or Anthropic API key, which the
  > user enters in Settings → AI; a key for review is below. Pages are kept on the device and, with iCloud
  > on (the default at setup), sync through the user's own iCloud account (CloudKit private database); "This device
  > only" keeps them local. Drawing is read-only on iPhone by design.

## Before the first submission

- **In-app purchase**: built (`Hikki/Sources/Purchases.swift`; CLAUDE.md, "Trial and unlock"). In App Store
  Connect, create a non-consumable with the product id `app.yancey.hikki.unlock`, priced $19.99 ($14.99 in the
  first weeks — `apps/website/src/site.ts`), Family Sharing on, attached to the first version for review. The trial
  (14 days, then read only) needs nothing in the store. For our own accounts: an offer code on that purchase,
  redeemed once per Apple Account — it is then a purchase like any other, on every device.
- **Mac sandbox**: built (CLAUDE.md, "Mac sandbox"): `Hikki/Hikki.entitlements` — App Sandbox, outgoing network,
  user-selected folders read-write, app-scoped bookmarks; no camera on the Mac. App Review's notes need nothing
  about it.
