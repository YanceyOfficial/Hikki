import ProjectDescription

let destinations: Destinations = [.iPhone, .iPad, .mac]
let deploymentTargets: DeploymentTargets = .multiplatform(iOS: "26.0", macOS: "26.0")

let baseSettings: SettingsDictionary = [
    "SWIFT_VERSION": "6.0",
    "SWIFT_APPROACHABLE_CONCURRENCY": "YES",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "DEVELOPMENT_TEAM": "YLF27G9ZMT",
]

let project = Project(
    name: "Hikki",
    organizationName: "Yancey Inc.",
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
                "NSHumanReadableCopyright": "Copyright © 2026 Yancey Inc. All rights reserved.",
                "CFBundleShortVersionString": "$(MARKETING_VERSION)",
                "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
                "UILaunchScreen": [:],
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
            ],
            dependencies: [
                .target(name: "HikkiCore"), .target(name: "HikkiUI"), .target(name: "HikkiSearch"), .target(name: "HikkiAI"),
            ],
            settings: .settings(base: [
                "SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor",
                // Release links our four frameworks into the app binary (fewer images for dyld to load at launch; GRDB stays
                // separate, see Tuist/Package.swift); Debug keeps them apart for fast incremental builds. Apple's
                // "Reducing your app's launch time".
                "MERGED_BINARY_TYPE": "automatic",
                "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                // The tone (design/tokens.json → make tokens → AccentColor.colorset): menus and selection follow it.
                "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
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
        .target(
            name: "HikkiUITests",
            destinations: destinations,
            product: .uiTests,
            bundleId: "app.yancey.hikki.uitests",
            deploymentTargets: deploymentTargets,
            sources: ["HikkiUITests/**"],
            dependencies: [.target(name: "Hikki")]
        ),
    ]
)
