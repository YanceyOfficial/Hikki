import Foundation
import Testing

@testable import HikkiCore

struct BundleFilesTests {
    private let root = URL(filePath: "/Applications/Hikki.app/Contents/Resources/Editor", directoryHint: .isDirectory)

    @Test func filesOfTheBundleAreServedTheEntryPageForNothing() {
        #expect(BundleFiles.file(for: "", in: root)?.path == root.appending(path: "index.html").path)
        #expect(BundleFiles.file(for: "assets/app.js", in: root)?.path == root.appending(path: "assets/app.js").path)
    }

    /// The bug: a prefix check without the separator let `Editor-evil/` pass for `Editor`.
    @Test func aSiblingFolderNamedLikeTheBundleIsOutside() {
        #expect(BundleFiles.file(for: "../Editor-evil/index.html", in: root) == nil)
        #expect(BundleFiles.file(for: "../Editor.bak/secret.js", in: root) == nil)
        #expect(BundleFiles.file(for: "../../Info.plist", in: root) == nil)
        #expect(BundleFiles.file(for: "assets/../../Editor-evil/x", in: root) == nil)
        // Up and back in stays inside.
        #expect(BundleFiles.file(for: "assets/../index.html", in: root)?.path == root.appending(path: "index.html").path)
    }
}
