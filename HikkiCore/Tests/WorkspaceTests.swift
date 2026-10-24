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

    @Test func workspaceFolderIsLocalForThisDeviceAndTheBookmarkOtherwise() throws {
        let appRoot = FileManager.default.temporaryDirectory.appending(path: "hikki-root-\(UUID().uuidString)")
        let device = Workspace(name: "Local", location: .device)
        #expect(try WorkspaceFolder.url(for: device, appRoot: appRoot).lastPathComponent == "Workspace")

        let picked = FileManager.default.temporaryDirectory.appending(
            path: "hikki-picked-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: picked, withIntermediateDirectories: true)
        let synced = Workspace(name: "Synced", location: .folder(bookmark: try FolderBookmark.make(for: picked), displayName: "Picked"))
        let resolved = try WorkspaceFolder.url(for: synced, appRoot: appRoot)
        #expect(resolved.resolvingSymlinksInPath().path == picked.resolvingSymlinksInPath().path)
        let written = try WorkspaceFolder.withPages(of: synced, appRoot: appRoot) { files in
            try files.write(
                try PageFile(
                    record: DocumentRecord(
                        id: "p", title: "", content: nil, plainText: "", wordCount: 0, createdAt: .now, updatedAt: .now, parentId: nil,
                        icon: nil, cover: nil, favoritedAt: nil, deletedAt: nil, sortKey: 0)))
            return files.exists("p")
        }
        #expect(written)
    }

    @Test func identityTravelsWithTheFolder() throws {
        let root = try makeTempDirectory()
        #expect(try WorkspaceFolder.readIdentity(in: root) == nil)
        var mine = Workspace(name: "Yancey’s Space", location: .device)
        mine.icon = .emoji("🏔️")
        try WorkspaceFolder.writeIdentity(WorkspaceIdentity(mine), in: root)

        let identity = try #require(try WorkspaceFolder.readIdentity(in: root))
        #expect(identity.name == "Yancey’s Space" && identity.icon == .emoji("🏔️") && identity.id == mine.id)
        // Another device opening the folder keeps its own location, takes the identity.
        let theirs = Workspace(name: "My Space", location: .folder(bookmark: Data([1]), displayName: "iCloud Drive › Hikki"))
        let joined = identity.applied(to: theirs)
        #expect(joined.name == "Yancey’s Space" && joined.id == mine.id && joined.icon == .emoji("🏔️"))
        #expect(joined.location == theirs.location)
    }

    @Test func identityFromANewerHikkiIsLeftAlone() throws {
        let root = try makeTempDirectory()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(
            #"{"format":99,"id":"00000000-0000-0000-0000-000000000000","name":"Future","createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z"}"#
                .utf8
        )
        .write(to: WorkspaceFolder.identityURL(in: root))
        #expect(try WorkspaceFolder.readIdentity(in: root) == nil)
    }

    /// A folder this process may not read asks for the folder again; one that reads, or is gone, doesn't.
    @Test func aFolderItMayNotReadIsDenied() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "hikki-access-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
            try? FileManager.default.removeItem(at: root)
        }
        #expect(!WorkspaceFolder.accessDenied(at: root))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: root.path)
        #expect(WorkspaceFolder.accessDenied(at: root))
        #expect(!WorkspaceFolder.accessDenied(at: root.deletingLastPathComponent().appending(path: "hikki-gone-\(UUID().uuidString)")))
    }

    /// A folder workspace moving into the app: every file keeps its place, hidden files stay behind, a newer file
    /// already there isn't replaced — and nothing moves while iCloud Drive still has files of it to download.
    @Test func aFolderWorkspaceCopiesInWhole() throws {
        let source = try makeTempDirectory()
        let destination = try makeTempDirectory()
        func put(_ text: String, _ path: String, in root: URL, at date: Date? = nil) throws {
            let url = root.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
            if let date { try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path) }
        }
        let old = Date(timeIntervalSince1970: 1_800_000_000)
        try put("p", "pages/p.json", in: source)
        try put("v", "history/p/1.json", in: source)
        try put("x", ".DS_Store", in: source)
        try put("folder's", "workspace.json", in: source, at: old)
        try put("newer here", "workspace.json", in: destination, at: old.addingTimeInterval(60))

        #expect(try WorkspaceFolder.copyContents(of: source, into: destination) == 2)
        #expect(try String(contentsOf: destination.appending(path: "history/p/1.json"), encoding: .utf8) == "v")
        #expect(try String(contentsOf: destination.appending(path: "workspace.json"), encoding: .utf8) == "newer here")
        #expect(!FileManager.default.fileExists(atPath: destination.appending(path: ".DS_Store").path))

        try put("", "pages/.q.json.icloud", in: source)
        #expect(throws: WorkspaceFolder.CopyError.stillDownloading(1)) {
            try WorkspaceFolder.copyContents(of: source, into: try makeTempDirectory())
        }
    }

    /// File Provider iCloud Drive (macOS 14 and later): a file not downloaded keeps its name and is a regular file —
    /// only its downloading status says so. Nothing is copied while one is not here yet.
    @Test func aFileNotDownloadedUnderItsOwnNameHoldsTheMoveBack() throws {
        let source = try makeTempDirectory()
        for path in ["pages/p.json", "pages/q.json", "assets/a.png"] {
            let url = source.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("x".utf8).write(to: url)
        }
        let destination = try makeTempDirectory()
        #expect(throws: WorkspaceFolder.CopyError.stillDownloading(1)) {
            try WorkspaceFolder.copyContents(of: source, into: destination, downloaded: { $0.lastPathComponent != "a.png" })
        }
        #expect(!FileManager.default.fileExists(atPath: destination.appending(path: "pages/p.json").path))
        // Downloaded since: it moves.
        #expect(try WorkspaceFolder.copyContents(of: source, into: destination, downloaded: { _ in true }) == 3)
        // A plain folder's files count as here.
        #expect(WorkspaceFolder.isDownloaded(source.appending(path: "pages/p.json")))
    }
}
