import Foundation
import Testing

@testable import HikkiCore

struct DrawingLibraryTests {
    private let items: JSONValue = .array([.object(["id": .string("a"), "elements": .array([])])])

    @Test func noLibraryYetIsEmptyAndASavedOneReadsBack() throws {
        let library = DrawingLibrary(root: try makeTempDirectory())
        #expect(try library.items() == .array([]))
        try library.save(items)
        #expect(try library.items() == items)
        #expect(FileManager.default.fileExists(atPath: library.root.appending(path: "drawings/library.json").path))
    }

    @Test func anUnreadableFileThrowsAndOnlyItemsAreSaved() throws {
        let library = DrawingLibrary(root: try makeTempDirectory())
        try FileManager.default.createDirectory(at: library.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{\"format\":1,\"items\":".utf8).write(to: library.file)
        #expect(throws: (any Error).self) { try library.items() }
        #expect(throws: DrawingLibrary.LibraryError.notItems) { try library.save(.object([:])) }
    }

    @Test func aNewerHikkisLibraryIsNeitherReadNorWrittenOver() throws {
        let library = DrawingLibrary(root: try makeTempDirectory())
        try FileManager.default.createDirectory(at: library.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let newer = Data("{\"format\":2,\"items\":[],\"more\":true}".utf8)
        try newer.write(to: library.file)
        #expect(throws: DrawingLibrary.LibraryError.newerFormat(2)) { try library.items() }
        #expect(throws: DrawingLibrary.LibraryError.newerFormat(2)) { try library.save(items) }
        #expect(try Data(contentsOf: library.file) == newer)
    }
}
