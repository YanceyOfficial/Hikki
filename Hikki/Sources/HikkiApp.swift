import HikkiCore
import HikkiSearch
import SwiftUI

@main
struct HikkiApp: App {
    @State private var model: AppModel
    #if os(macOS)
        // Closing the last window hides it; the Dock brings it back (see WindowLifecycle).
        @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
            try? FileManager.default.removeItem(at: paths.searchIndex)
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
            // The standard Settings window (⌘,), Apple-style tabs.
            Settings {
                SettingsView().environment(model)
            }
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
