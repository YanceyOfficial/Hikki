import ProjectDescription

let destinations: Destinations = [.iPhone, .iPad, .mac]
let deploymentTargets: DeploymentTargets = .multiplatform(iOS: "26.0", macOS: "26.0")

let baseSettings: SettingsDictionary = [
    "SWIFT_VERSION": "6.0",
    "SWIFT_APPROACHABLE_CONCURRENCY": "YES",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "DEVELOPMENT_TEAM": "A542S7SY83",
]

let project = Project(
    name: "Hikki",
    organizationName: "Yanzhao Liu",
    options: .options(defaultKnownRegions: ["en", "zh-Hans"], developmentRegion: "en"),
    // Version (marketing + build number) comes from one xcconfig — see Configs/Version.xcconfig.
    settings: .settings(
        base: baseSettings,
        configurations: [
            .debug(name: .debug, xcconfig: "Configs/Version.xcconfig"),
            .release(name: .release, xcconfig: "Configs/Version.xcconfig"),
        ]
    ),
    targets: [
        .target(
            name: "Hikki",
            destinations: destinations,
            product: .app,
            bundleId: "app.yancey.hikki",
            deploymentTargets: deploymentTargets,
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "Hikki",
                "NSHumanReadableCopyright": "Copyright © 2026 Yanzhao Liu. All rights reserved.",
                "CFBundleShortVersionString": "$(MARKETING_VERSION)",
                "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
                "UILaunchScreen": [:],
                // The Mac App Store files the app by it (it refuses an upload without one); the same on iOS.
                "LSApplicationCategoryType": "public.app-category.productivity",
                // HTTPS only, no encryption of our own: App Store Connect then asks nothing about export compliance.
                "ITSAppUsesNonExemptEncryption": false,
                // What the window may ever take; `OrientationDelegate` narrows it per screen at run time (phones and a
                // folded iPhone Duo upright, iPads and an unfolded Duo on their side). iPad lists all four, as multitasking
                // requires for App Store validation.
                "UISupportedInterfaceOrientations~iphone": [
                    "UIInterfaceOrientationPortrait", "UIInterfaceOrientationLandscapeLeft",
                    "UIInterfaceOrientationLandscapeRight",
                ],
                "UISupportedInterfaceOrientations~ipad": [
                    "UIInterfaceOrientationPortrait", "UIInterfaceOrientationPortraitUpsideDown",
                    "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight",
                ],
                // hikki://page/<id> — "Copy link" (HikkiCore/Sources/Store/PageLink.swift).
                "CFBundleURLTypes": [["CFBundleURLName": "app.yancey.hikki", "CFBundleURLSchemes": ["hikki"]]],
                "UIApplicationSceneManifest": ["UIApplicationSupportsMultipleScenes": true],
                // Pages picked in Spotlight arrive as this activity (SpotlightIndex.swift).
                "NSUserActivityTypes": ["com.apple.corespotlightitem", "app.yancey.hikki.viewing"],
                // The keyboard bar's photo sheet: Camera and Scan document (InfoPlist.xcstrings has the translations).
                // iCloud's silent pushes wake the app to fetch what another device saved (CloudSync).
                "UIBackgroundModes": ["remote-notification"],
                "NSCameraUsageDescription": "Hikki uses the camera to add photos and scanned documents to your pages.",
            ]),
            sources: ["Hikki/Sources/**"],
            // Built by `make editor` (vite). A folder reference keeps the bundle's relative layout intact.
            resources: [
                .folderReference(path: "Hikki/Resources/Editor"),
                "Hikki/Resources/Localization/**",
                // Icon Composer document (sources: design/icon/hi-star); actool renders every size and appearance.
                "Hikki/Resources/AppIcon.icon",
                // MenuBarIcon (template image for the menu bar extra).
                "Hikki/Resources/Assets.xcassets",
                // container-migration.plist: the first sandboxed launch moves a Mac's data from before the sandbox
                // (~/Library/Application Support/Hikki, the preferences) into the app's container.
                .glob(pattern: "Hikki/Resources/Mac/**", inclusionCondition: .when([.macos])),
            ],
            dependencies: [
                .target(name: "HikkiCore"), .target(name: "HikkiUI"), .target(name: "HikkiSearch"), .target(name: "HikkiAI"),
            ],
            settings: .settings(
                base: [
                    "SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor",
                    // Release links our four frameworks into the app binary (fewer images for dyld to load at launch; GRDB stays
                    // separate, see Tuist/Package.swift); Debug keeps them apart for fast incremental builds. Apple's
                    // "Reducing your app's launch time".
                    "MERGED_BINARY_TYPE": "automatic",
                    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                    // The tone (design/tokens.json → make tokens → AccentColor.colorset): menus and selection follow it.
                    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
                ],
                debug: [
                    // The Mac app is sandboxed (the Mac App Store takes nothing else): network out, folders the user picks,
                    // bookmarks to them; on both platforms iCloud (CloudKit, `CloudSync`) and its pushes, and one iCloud
                    // key-value store for settings (`SettingsSync`; the same identifier on every platform, so the Mac and
                    // iOS share it). Debug may also reach the temporary folders, where UI tests and demo runs keep their
                    // data (`HIKKI_DATA_DIR`).
                    "CODE_SIGN_ENTITLEMENTS[sdk=macosx*]": "Hikki/Hikki-Debug.entitlements",
                    "CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*]": "Hikki/Hikki-iOS.entitlements",
                    "CODE_SIGN_ENTITLEMENTS[sdk=iphonesimulator*]": "Hikki/Hikki-iOS.entitlements",
                ],
                release: [
                    "CODE_SIGN_ENTITLEMENTS[sdk=macosx*]": "Hikki/Hikki.entitlements",
                    "CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*]": "Hikki/Hikki-iOS.entitlements",
                    "CODE_SIGN_ENTITLEMENTS[sdk=iphonesimulator*]": "Hikki/Hikki-iOS.entitlements",
                ])
        ),
        .target(
            name: "HikkiCore",
            destinations: destinations,
            product: .framework,
            bundleId: "app.yancey.hikki.core",
            deploymentTargets: deploymentTargets,
            sources: ["HikkiCore/Sources/**"],
            dependencies: [.external(name: "GRDB")]
        ),
        .target(
            name: "HikkiUI",
            destinations: destinations,
            product: .framework,
            bundleId: "app.yancey.hikki.ui",
            deploymentTargets: deploymentTargets,
            sources: ["HikkiUI/Sources/**"],
            resources: ["HikkiUI/Resources/**"],
            settings: .settings(base: ["SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor"])
        ),
        // The search engine: its own index file, ranking, pinyin — fed by the app, nothing else of the store.
        .target(
            name: "HikkiSearch",
            destinations: destinations,
            product: .framework,
            bundleId: "app.yancey.hikki.search",
            deploymentTargets: deploymentTargets,
            sources: ["HikkiSearch/Sources/**"],
            dependencies: [.external(name: "GRDB")]
        ),
        // AI: one streaming interface over OpenAI (Responses API) and Anthropic (Messages API), with their own web search
        // and citations, and the model catalog. Plain URLSession + SSE: the Swift client packages tried dropped citations.
        .target(
            name: "HikkiAI",
            destinations: destinations,
            product: .framework,
            bundleId: "app.yancey.hikki.ai",
            deploymentTargets: deploymentTargets,
            sources: ["HikkiAI/Sources/**"],
            // Answers render as Markdown (swift-markdown) with highlighted code (HighlightSwift): AIMarkdown, CodeHighlighter.
            dependencies: [.external(name: "Markdown"), .external(name: "HighlightSwift")]
        ),
        .target(
            name: "HikkiAITests",
            destinations: destinations,
            product: .unitTests,
            bundleId: "app.yancey.hikki.ai.tests",
            deploymentTargets: deploymentTargets,
            sources: ["HikkiAI/Tests/**"],
            dependencies: [.target(name: "HikkiAI")]
        ),
        .target(
            name: "HikkiCoreTests",
            destinations: destinations,
            product: .unitTests,
            bundleId: "app.yancey.hikki.core.tests",
            deploymentTargets: deploymentTargets,
            sources: ["HikkiCore/Tests/**"],
            dependencies: [.target(name: "HikkiCore")]
        ),
        .target(
            name: "HikkiSearchTests",
            destinations: destinations,
            product: .unitTests,
            bundleId: "app.yancey.hikki.search.tests",
            deploymentTargets: deploymentTargets,
            sources: ["HikkiSearch/Tests/**"],
            dependencies: [.target(name: "HikkiSearch")]
        ),
        // HikkiUI's plain logic (what a drag decides, what a list shows); the views themselves are seen in the gallery
        // and the UI tests. Not "HikkiUITests": that name is the XCUITest target's.
        .target(
            name: "HikkiUIUnitTests",
            destinations: destinations,
            product: .unitTests,
            bundleId: "app.yancey.hikki.ui.tests",
            deploymentTargets: deploymentTargets,
            sources: ["HikkiUI/Tests/**"],
            dependencies: [.target(name: "HikkiUI")],
            settings: .settings(base: ["SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor"])
        ),
        .target(
            name: "HikkiUITests",
            destinations: destinations,
            product: .uiTests,
            bundleId: "app.yancey.hikki.uitests",
            deploymentTargets: deploymentTargets,
            sources: ["HikkiUITests/**"],
            dependencies: [.target(name: "Hikki")]
        ),
    ],
    schemes: [
        // The app against a local StoreKit configuration (Hikki/Hikki.storekit: the unlock): buy, refund and restore
        // without the App Store. Debug runs ignore the trial unless HIKKI_ACCESS=store says to read it.
        .scheme(
            name: "Hikki-StoreKit",
            buildAction: .buildAction(targets: ["Hikki"]),
            runAction: .runAction(
                configuration: .debug, executable: "Hikki",
                arguments: .arguments(environmentVariables: ["HIKKI_ACCESS": .environmentVariable(value: "store", isEnabled: true)]),
                options: .options(storeKitConfigurationPath: "Hikki/Hikki.storekit"))
        )
    ]
)
