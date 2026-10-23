import HikkiCore
import SwiftUI

#if os(iOS)
    import UIKit
#endif

/// What typing reaches the store before the app leaves: editors save on a short debounce, so the last moments of
/// typing live only in the page until they are flushed — when a window goes to the background or closes, and when
/// the app quits (⌘Q, `AppDelegate`).
enum SaveOnExit {
    /// Longest the app waits for the editors when quitting: a web view that hangs must not keep it open.
    static let quitTimeout: Duration = .seconds(3)

    /// A window going to the background: its editors, then the workspace folder's queued writes. On iOS under a
    /// background-task assertion, so the system doesn't suspend the app halfway.
    static func flush(_ editors: [EditorController], model: AppModel, reason: String) {
        #if os(iOS)
            let assertion = BackgroundAssertion(name: "save")
        #endif
        Task {
            for editor in editors { await editor.flush(reason: reason) }
            await model.flushWorkspace()
            #if os(iOS)
                assertion.end()
            #endif
        }
    }

    /// The app quitting: every editor in every window, then the workspace folder; `done` runs once, when that
    /// finished or after `quitTimeout`, whichever is first.
    static func flushAll(model: AppModel?, reason: String, done: @escaping @MainActor () -> Void) {
        let once = Once(done)
        Task {
            await EditorController.flushAll(reason: reason)
            await model?.flushWorkspace()
            once.run()
        }
        Task {
            try? await Task.sleep(for: quitTimeout)
            if !once.ran { Log.warn("quit: editors didn't flush in time", category: "lifecycle") }
            once.run()
        }
    }

    private final class Once {
        private let action: @MainActor () -> Void
        private(set) var ran = false

        init(_ action: @escaping @MainActor () -> Void) { self.action = action }

        func run() {
            guard !ran else { return }
            ran = true
            action()
        }
    }

    #if os(iOS)
        /// `beginBackgroundTask` until `end()` or until the system's time runs out.
        private final class BackgroundAssertion {
            private var id = UIBackgroundTaskIdentifier.invalid

            init(name: String) {
                id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in self?.end() }
            }

            func end() {
                guard id != .invalid else { return }
                UIApplication.shared.endBackgroundTask(id)
                id = .invalid
            }
        }
    #endif
}
