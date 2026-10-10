import Foundation
import Testing

@testable import HikkiCore

struct WorkspaceTests {
    @Test func firstLaunchHasNoWorkspace() throws {
        let store = WorkspaceStore(url: try makeTempDirectory().appending(path: "workspace.json"))
        #expect(try store.load() == nil)
    }

    @Test func roundTripsBothLocations() throws {
        let store = WorkspaceStore(url: try makeTempDirectory().appending(path: "nested/workspace.json"))
        let device = Workspace(name: "Notes", location: .device, createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        try store.save(device)
        #expect(try store.load() == device)

        let folder = Workspace(
            name: "Team", location: .folder(bookmark: Data([1, 2, 3]), displayName: "iCloud Drive › Hikki"),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        try store.save(folder)
        #expect(try store.load() == folder)
    }

    @Test func normalizesNames() {
        #expect(Workspace.normalizedName("  Yancey’s Space \n") == "Yancey’s Space")
        #expect(Workspace.normalizedName("a\nb") == "a b")
        #expect(Workspace.normalizedName("   ") == nil)
        #expect(Workspace.normalizedName(String(repeating: "x", count: 100))?.count == 60)
    }

    @Test func initialIsTheUppercasedFirstCharacter() {
        #expect(Workspace(name: "notes", location: .device).initial == "N")
        #expect(Workspace(name: "日记", location: .device).initial == "日")
    }
}

struct FolderBookmarkTests {
    @Test func bookmarksRoundTripToTheSameFolder() throws {
        let folder = try makeTempDirectory()
        let resolved = try FolderBookmark.resolve(try FolderBookmark.make(for: folder))
        #expect(resolved.standardizedFileURL.resolvingSymlinksInPath().path == folder.standardizedFileURL.resolvingSymlinksInPath().path)
    }

    @Test func displayNamesICloudDriveFolders() {
        let icloud = URL(filePath: "/Users/me/Library/Mobile Documents/com~apple~CloudDocs/Notes/Hikki")
        #expect(FolderBookmark.displayName(for: icloud) == "iCloud Drive › Notes › Hikki")
        #expect(FolderBookmark.displayName(for: URL(filePath: "/Users/me/Documents/Hikki")) == "Hikki")
    }
}
