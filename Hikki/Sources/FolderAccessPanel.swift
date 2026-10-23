#if os(macOS)
    import AppKit
    import Foundation

    /// The Mac's way to give a sandboxed app a folder again: an open panel at that folder, which the user confirms.
    /// What they pick (the same folder, or another) is what the sandbox lets the app open from now on.
    enum FolderAccessPanel {
        static func choose(startingAt folder: URL, _ picked: @escaping (URL) -> Void) {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = false
            panel.allowsMultipleSelection = false
            panel.directoryURL = folder
            panel.prompt = String(localized: "app:workspace.grantAccess")
            panel.message = String(localized: "app:workspace.grantAccessMessage")
            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                picked(url)
            }
        }
    }
#endif
