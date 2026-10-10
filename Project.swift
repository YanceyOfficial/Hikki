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
    settings: .settings(base: baseSettings),
    targets: [
        .target(
            name: "Hikki",
            destinations: destinations,
            product: .app,
            bundleId: "app.yancey.hikki",
            deploymentTargets: deploymentTargets,
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "Hikki",
                "UILaunchScreen": [:],
                "UIApplicationSceneManifest": ["UIApplicationSupportsMultipleScenes": true],
            ]),
            sources: ["Hikki/Sources/**"],
            // Built by `make editor` (vite). A folder reference keeps the bundle's relative layout intact.
            resources: [.folderReference(path: "Hikki/Resources/Editor")],
            dependencies: [.target(name: "HikkiCore"), .target(name: "HikkiUI")],
            settings: .settings(base: ["SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor"])
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
            settings: .settings(base: ["SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor"])
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
