import HikkiCore
import HikkiSearch
import SwiftUI

@main
struct HikkiApp: App {
    @State private var model: AppModel
    #if os(macOS)
        // Closing the last window hides it; the Dock brings it back (see WindowLifecycle).
        @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #else
        /// Which way the window may turn, per screen (`DeviceRules.orientation`).
        @UIApplicationDelegateAdaptor(OrientationDelegate.self) private var orientation
    #endif

    init() {
        let paths: AppPaths
        do {
            paths = try AppPaths.standard()
            try Log.bootstrap(directory: paths.logs)
        } catch {
            fatalError("Cannot prepare app directories: \(error)")
        }
        let crashReporter = CrashReporter(directory: paths.diagnostics)
        crashReporter.start()
        // Version, build, OS, device, language and the bridge protocol: what every report needs (the session id is on
        // every line).
        Log.info("launch", context: AppInfo.current().context)
        // The trial and the unlock: read now, followed from here on.
        Purchases.shared.start()
        do {
            let store = try DocumentStore.onDisk(at: paths.database)
            #if DEBUG
                DemoPages.seed(store)
            #endif
            _model = State(
                initialValue: AppModel(
                    store: store, searchIndex: HikkiApp.searchIndex(paths), assets: AssetStore(directory: paths.assets),
                    crashReporter: crashReporter, workspaceStore: HikkiApp.workspaceStore(paths)))
        } catch {
            Toasts.report(.databaseOpenFailed, error, category: "store")
            fatalError("Cannot open database: \(error)")
        }
    }

    /// The search index file; an unopenable one (corrupt) is replaced by an in-memory index for this run — the
    /// indexer fills it from the database either way.
    private static func searchIndex(_ paths: AppPaths) -> SearchIndex {
        do {
            return try SearchIndex(url: paths.searchIndex)
        } catch {
            Toasts.report(.searchIndexFailed, error, category: "search")
            // The index is rebuildable: the file goes whole, with its write-ahead log (WAL mode) beside it.
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: URL(filePath: paths.searchIndex.path + suffix))
            }
            if let fresh = try? SearchIndex(url: paths.searchIndex) { return fresh }
            return try! SearchIndex.inMemory()  // swiftlint:disable:this force_try
        }
    }

    /// DEBUG/test hook: HIKKI_WORKSPACE=<name> creates a device workspace up front (skips onboarding).
    private static func workspaceStore(_ paths: AppPaths) -> WorkspaceStore {
        let store = WorkspaceStore(url: paths.workspace)
        #if DEBUG
            if let name = ProcessInfo.processInfo.environment["HIKKI_WORKSPACE"], (try? store.load()) == nil {
                try? store.save(Workspace(name: name, location: .device))
            }
        #endif
        return store
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
                if ComponentGalleryLaunch.isEnabled {
                    ComponentGalleryView()
                } else {
                    RootView().environment(model)
                }
            #else
                RootView().environment(model)
            #endif
        }
        .defaultSize(width: 1180, height: 780)
        #if os(macOS)
            // EXPERIMENT: the standard window title bar + unified toolbar.
            .windowToolbarStyle(.unified)
        #endif
        .commands { AppCommands() }
        #if os(macOS)
            // "Open in new window": a window that starts on that page.
            WindowGroup(id: "page", for: String.self) { $pageID in
                RootView(initialPageID: pageID).environment(model)
            }
            .defaultSize(width: 1180, height: 780)
            .windowToolbarStyle(.unified)
            // The status item (Settings → General → Menu bar); see MenuBarExtra.swift.
            MenuBarScene()
        #endif
    }
}

#if os(iOS)
    /// Upright on a phone-sized screen (every iPhone, an iPhone Duo folded), on its side on a tablet-sized one (iPads,
    /// the Duo unfolded) — `DeviceRules.orientation`; asked again when the window moves to the other screen (`RootView`).
    final class OrientationDelegate: NSObject, UIApplicationDelegate {
        /// iCloud's pushes (another device saved): `CKSyncEngine` takes them once the app is registered.
        func application(
            _ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
        ) -> Bool {
            application.registerForRemoteNotifications()
            return true
        }

        func application(
            _ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?
        ) -> UIInterfaceOrientationMask {
            guard let screen = window?.windowScene?.screen else { return .allButUpsideDown }
            switch DeviceRules.orientation(screen: screen.bounds.size) {
            case .portrait: return .portrait
            case .landscape: return .landscape
            }
        }
    }
#endif
