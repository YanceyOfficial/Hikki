import Foundation
import Testing

@testable import HikkiAI

struct WorkspaceFilesTests {
    private let folder: URL
    private let files: WorkspaceFiles

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "hikki-files-\(UUID().uuidString)")
        let manager = FileManager.default
        try manager.createDirectory(at: folder.appending(path: "notes/trips"), withIntermediateDirectories: true)
        try manager.createDirectory(at: folder.appending(path: "pages"), withIntermediateDirectories: true)
        try "Kyoto\nNara\nOsaka\n".write(to: folder.appending(path: "notes/trips/japan.md"), atomically: true, encoding: .utf8)
        try "# Plan\nBook the ryokan.\nBook the train.\n".write(
            to: folder.appending(path: "notes/plan.md"), atomically: true, encoding: .utf8)
        try #"{"title":"Book club"}"#.write(to: folder.appending(path: "pages/p1.json"), atomically: true, encoding: .utf8)
        try "secret".write(to: folder.appending(path: ".hidden"), atomically: true, encoding: .utf8)
        try Data([0xFF, 0xFE, 0x00, 0x81]).write(to: folder.appending(path: "notes/blob.bin"))
        files = WorkspaceFiles(root: folder)
    }

    private func run(_ name: String, _ arguments: [String: Any]) throws -> (object: [String: Any], output: AIToolOutput) {
        let data = try JSONSerialization.data(withJSONObject: arguments)
        let output = files.perform(AIToolCall(id: "c", name: name, arguments: String(decoding: data, as: UTF8.self)))
        let object = (try? JSONSerialization.jsonObject(with: Data(output.text.utf8))) as? [String: Any] ?? [:]
        return (object, output)
    }

    private func text(_ path: String) throws -> String { try String(contentsOf: folder.appending(path: path), encoding: .utf8) }

    @Test func listsAFolderWithoutHiddenFiles() throws {
        let top = try run("list_directory", [:]).object
        let entries = try #require(top["entries"] as? [[String: Any]])
        #expect(entries.map { $0["path"] as? String } == ["notes", "pages"])
        let deep = try #require(try run("list_directory", ["path": "notes", "recursive": true]).object["entries"] as? [[String: Any]])
        #expect(
            deep.map { $0["path"] as? String } == ["notes/blob.bin", "notes/plan.md", "notes/trips", "notes/trips/japan.md"])
        #expect(deep[1]["type"] as? String == "file")
        #expect(deep[2]["type"] as? String == "folder")
    }

    @Test func readsAFileOrSomeOfItsLines() throws {
        let whole = try run("read_file", ["path": "notes/plan.md"]).object
        #expect(whole["content"] as? String == "# Plan\nBook the ryokan.\nBook the train.")
        #expect(whole["totalLines"] as? Int == 3)
        let part = try run("read_file", ["path": "notes/plan.md", "offset": 2, "limit": 1]).object
        #expect(part["content"] as? String == "Book the ryokan.")
        #expect(part["fromLine"] as? Int == 2)
        #expect(part["toLine"] as? Int == 2)
        #expect(try run("read_file", ["path": "notes/blob.bin"]).output.isError)
        #expect(try run("read_file", ["path": "notes/missing.md"]).output.isError)
        #expect(try run("read_file", ["path": "notes"]).output.isError)
        // Hikki's data may be read.
        #expect(try run("read_file", ["path": "pages/p1.json"]).object["content"] as? String == #"{"title":"Book club"}"#)
    }

    @Test func staysInsideTheFolder() throws {
        for path in ["../outside.md", "notes/../../outside.md", ".hidden", "notes/.git/config", "/etc/hosts"] {
            #expect(try run("read_file", ["path": path]).output.isError, "\(path)")
        }
        // An absolute path inside the folder is taken as its relative path.
        let inside = folder.appending(path: "notes/plan.md").path
        #expect(try run("read_file", ["path": inside]).object["path"] as? String == "notes/plan.md")
        // No link is followed out.
        try FileManager.default.createSymbolicLink(
            at: folder.appending(path: "notes/out"), withDestinationURL: FileManager.default.temporaryDirectory)
        #expect(try run("list_directory", ["path": "notes/out"]).output.isError)
        let listed = try #require(try run("list_directory", ["path": "notes"]).object["entries"] as? [[String: Any]])
        #expect(!listed.contains { $0["path"] as? String == "notes/out" })
    }

    @Test func findsFilesByNameOutsideHikkisData() throws {
        let found = try run("find_files", ["pattern": "*.MD"]).object
        #expect(found["results"] as? [String] == ["notes/plan.md", "notes/trips/japan.md"])
        #expect(try run("find_files", ["pattern": "*.json"]).object["results"] as? [String] == [])
        #expect(try run("find_files", ["pattern": "*.json", "path": "pages"]).object["results"] as? [String] == ["pages/p1.json"])
        #expect(try run("find_files", ["pattern": "pla?.md"]).object["results"] as? [String] == ["notes/plan.md"])
    }

    @Test func searchesTheTextOfFiles() throws {
        let result = try run("grep", ["pattern": "book the", "case_insensitive": true]).object
        #expect(result["matches"] as? Int == 2)
        let file = try #require((result["results"] as? [[String: Any]])?.first)
        #expect(file["path"] as? String == "notes/plan.md")
        let lines = try #require(file["matches"] as? [[String: Any]])
        #expect(lines.map { $0["line"] as? Int } == [2, 3])
        #expect(try run("grep", ["pattern": "Book club"]).object["matches"] as? Int == 0)
        #expect(try run("grep", ["pattern": "Book club", "path": "pages"]).object["matches"] as? Int == 1)
        #expect(try run("grep", ["pattern": "Nara", "file_glob": "*.txt"]).object["matches"] as? Int == 0)
        #expect(try run("grep", ["pattern": "(unclosed"]).output.isError)
        let context = try run("grep", ["pattern": "Nara", "path": "notes/trips/japan.md", "context_lines": 1]).object
        let match = try #require(((context["results"] as? [[String: Any]])?.first?["matches"] as? [[String: Any]])?.first)
        #expect(match["before"] as? [String] == ["Kyoto"])
        #expect(match["after"] as? [String] == ["Osaka"])
    }

    @Test func writesNewFilesAndAppends() throws {
        let made = try run("write_file", ["path": "drafts/idea.md", "content": "One\n"]).object
        #expect(made["created"] as? Bool == true)
        #expect(try text("drafts/idea.md") == "One\n")
        let added = try run("write_file", ["path": "drafts/idea.md", "content": "Two\n", "append": true]).object
        #expect(added["created"] as? Bool == false)
        #expect(added["appended"] as? Bool == true)
        #expect(try text("drafts/idea.md") == "One\nTwo\n")
        _ = try run("write_file", ["path": "drafts/idea.md", "content": "Fresh"])
        #expect(try text("drafts/idea.md") == "Fresh")
    }

    @Test func neverWritesHikkisOwnData() throws {
        for path in [
            "pages/p1.json", "Pages/new.json", "PAGES/new.json", "ｐａｇｅｓ/new.json", "Workspace.JSON", "workspace.json",
            "assets/a.png", "history/p1/x.json", "",
        ] {
            #expect(try run("write_file", ["path": path, "content": "x"]).output.isError, "\(path)")
        }
        #expect(try text("pages/p1.json") == #"{"title":"Book club"}"#)
        #expect(try run("edit_file", ["path": "pages/p1.json", "old_string": "Book", "new_string": "Film"]).output.isError)
    }

    @Test func editsReplaceExactlyWhatWasNamed() throws {
        let once = try run("edit_file", ["path": "notes/plan.md", "old_string": "ryokan", "new_string": "hotel"]).object
        #expect(once["replacements"] as? Int == 1)
        #expect(try text("notes/plan.md") == "# Plan\nBook the hotel.\nBook the train.\n")
        // Twice in the file: refused unless every one is meant.
        let twice = try run("edit_file", ["path": "notes/plan.md", "old_string": "Book", "new_string": "Get"])
        #expect(twice.output.isError)
        #expect(twice.output.text.contains("2 times"))
        let all = try run("edit_file", ["path": "notes/plan.md", "old_string": "Book", "new_string": "Get", "replace_all": true])
        #expect(all.object["replacements"] as? Int == 2)
        #expect(try text("notes/plan.md") == "# Plan\nGet the hotel.\nGet the train.\n")
        #expect(try run("edit_file", ["path": "notes/plan.md", "old_string": "absent", "new_string": "x"]).output.isError)
        #expect(try run("edit_file", ["path": "notes/none.md", "old_string": "a", "new_string": "b"]).output.isError)
    }

    @Test func aChangeIsShownBeforeItIsMade() throws {
        let call = AIToolCall(id: "c", name: "edit_file", arguments: #"{"path":"notes/plan.md","old_string":"train","new_string":"bus"}"#)
        let change = try files.change(for: call).get()
        #expect(change.before == "# Plan\nBook the ryokan.\nBook the train.\n")
        #expect(change.after == "# Plan\nBook the ryokan.\nBook the bus.\n")
        #expect(try text("notes/plan.md").contains("train"))
        let new = try files.change(for: AIToolCall(id: "c", name: "write_file", arguments: #"{"path":"a.md","content":"x"}"#)).get()
        #expect(new.before == nil)
        #expect(WorkspaceFiles.Tool.editFile.changesFiles && !WorkspaceFiles.Tool.readFile.changesFiles)
    }
}
