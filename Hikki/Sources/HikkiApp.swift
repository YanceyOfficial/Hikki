import HikkiCore
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
        Log.info(
            "launch",
            context: [
                "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?",
                "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?",
            ])
        do {
            let store = try DocumentStore.onDisk(at: paths.database)
            _model = State(
                initialValue: AppModel(
                    store: store, assets: AssetStore(directory: paths.assets), crashReporter: crashReporter,
                    workspaceStore: HikkiApp.workspaceStore(paths)))
        } catch {
            Log.error("cannot open database: \(error)", category: "store")
            fatalError("Cannot open database: \(error)")
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
