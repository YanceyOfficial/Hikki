import Foundation
import ImageIO
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

    @Test func iconRoundTripsAndOldFilesHaveNone() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = WorkspaceStore(url: dir.appending(path: "workspace.json"))
        var workspace = Workspace(name: "Atlas", location: .device)
        #expect(workspace.icon == nil)
        workspace.icon = .emoji("🏠")
        try store.save(workspace)
        #expect(try store.load()?.icon == .emoji("🏠"))
        // A file written before icons existed still loads.
        let old = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Old","location":{"device":{}},"createdAt":"2026-10-01T00:00:00Z"}"#
        try Data(old.utf8).write(to: store.url)
        #expect(try store.load()?.icon == nil)
    }

    @Test func thumbnailShrinksImagesAndRejectsOthers() throws {
        // A 1024×512 PNG drawn with CoreGraphics.
        let context = try #require(
            CGContext(
                data: nil, width: 1024, height: 512, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.8, green: 0.1, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1024, height: 512))
        let big = NSMutableData()
        let dest = try #require(CGImageDestinationCreateWithData(big, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(dest, try #require(context.makeImage()), nil)
        #expect(CGImageDestinationFinalize(dest))

        let thumb = try #require(WorkspaceIcon.thumbnail(of: big as Data))
        let image = try #require(CGImageSourceCreateWithData(thumb as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
        #expect(max(image.width, image.height) == WorkspaceIcon.maxPixels)
        #expect(WorkspaceIcon.thumbnail(of: Data("not an image".utf8)) == nil)
    }
}
