import HikkiCore
import SwiftUI

@main
struct HikkiApp: App {
    @State private var model: AppModel

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
        Log.info("launch", context: [
            "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?",
            "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?",
        ])
        do {
            let store = try DocumentStore.onDisk(at: paths.database)
            _model = State(initialValue: AppModel(store: store, assets: AssetStore(directory: paths.assets), crashReporter: crashReporter))
        } catch {
            Log.error("cannot open database: \(error)", category: "store")
            fatalError("Cannot open database: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
                if ComponentGalleryLaunch.isEnabled {
                    ComponentGalleryView()
                } else {
                    ContentView().environment(model)
                }
            #else
                ContentView().environment(model)
            #endif
        }
        .defaultSize(width: 1180, height: 780)
        #if os(macOS)
        // The tab bar and sidebar header draw their own title bar (Notion-style); see WindowChrome.
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        #endif
        .commands { AppCommands() }
    }
}
