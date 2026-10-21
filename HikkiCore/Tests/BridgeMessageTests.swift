import Foundation
import Testing

@testable import HikkiCore

struct BridgeMessageTests {
    @Test func onlyTheEditorsOwnMainFrameMayPostMessages() {
        #expect(BridgeProtocol.trustsFrame(isMainFrame: true, scheme: "hikki-editor", editorScheme: "hikki-editor"))
        // An embed's frame, whatever it was loaded from.
        #expect(!BridgeProtocol.trustsFrame(isMainFrame: false, scheme: "hikki-editor", editorScheme: "hikki-editor"))
        #expect(!BridgeProtocol.trustsFrame(isMainFrame: false, scheme: "https", editorScheme: "hikki-editor"))
        // The main frame navigated away (it never should).
        #expect(!BridgeProtocol.trustsFrame(isMainFrame: true, scheme: "https", editorScheme: "hikki-editor"))
        #expect(!BridgeProtocol.trustsFrame(isMainFrame: true, scheme: nil, editorScheme: "hikki-editor"))
    }

    /// Shapes exactly as WebKit bridges a JS object literal (NSDictionary / NSNumber).
    @Test func decodesReady() throws {
        let body: NSDictionary = ["type": "ready", "protocolVersion": NSNumber(value: BridgeProtocol.version)]
        #expect(try BridgeMessage.decode(scriptMessageBody: body) == .ready(protocolVersion: BridgeProtocol.version))
    }

    @Test func decodesLinkPreview() throws {
        let body: NSDictionary = ["type": "linkPreview", "url": "https://www.yanceyleo.com/"]
        #expect(try BridgeMessage.decode(scriptMessageBody: body) == .linkPreview(url: "https://www.yanceyleo.com/"))
    }

    @Test func decodesTheOpenThread() throws {
        let open: NSDictionary = ["type": "commentThread", "docId": "a", "threadId": "t1"]
        #expect(try BridgeMessage.decode(scriptMessageBody: open) == .commentThread(docId: "a", threadId: "t1"))
        let closed: NSDictionary = ["type": "commentThread", "docId": "a", "threadId": NSNull()]
        #expect(try BridgeMessage.decode(scriptMessageBody: closed) == .commentThread(docId: "a", threadId: nil))
    }

    @Test func decodesTheCoverSheetRequest() throws {
        let body: NSDictionary = [
            "type": "coverSheet", "docId": "a", "cover": "gradient:dusk", "mode": "actions", "bff": "https://unsplash.yancey.app",
        ]
        #expect(
            try BridgeMessage.decode(scriptMessageBody: body)
                == .coverSheet(docId: "a", cover: "gradient:dusk", mode: .actions, bff: URL(string: "https://unsplash.yancey.app")))
        let bare: NSDictionary = ["type": "coverSheet", "docId": "a", "cover": NSNull(), "mode": "picker", "bff": NSNull()]
        #expect(try BridgeMessage.decode(scriptMessageBody: bare) == .coverSheet(docId: "a", cover: nil, mode: .picker, bff: nil))
    }

    @Test func decodesTheIconSheetRequest() throws {
        let callout: NSDictionary = [
            "type": "iconSheet", "docId": "a", "id": "r1", "kind": "callout", "icon": "💡", "color": "blue",
        ]
        #expect(
            try BridgeMessage.decode(scriptMessageBody: callout)
                == .iconSheet(docId: "a", id: "r1", kind: .callout, icon: "💡", color: "blue"))
        let page: NSDictionary = ["type": "iconSheet", "docId": "a", "id": "r2", "kind": "page", "icon": NSNull(), "color": NSNull()]
        #expect(
            try BridgeMessage.decode(scriptMessageBody: page) == .iconSheet(docId: "a", id: "r2", kind: .page, icon: nil, color: nil))
    }

    @Test func decodesPageInfoWithOptionalBlockIds() throws {
        let body: NSDictionary = [
            "type": "pageInfo", "docId": "a",
            "headings": [["id": "h1", "level": 1, "text": "One"], ["id": NSNull(), "level": 2, "text": "Two"]],
            "words": 4, "characters": 19,
        ]
        #expect(
            try BridgeMessage.decode(scriptMessageBody: body)
                == .pageInfo(
                    docId: "a",
                    headings: [OutlineHeading(id: "h1", level: 1, text: "One"), OutlineHeading(id: nil, level: 2, text: "Two")],
                    words: 4, characters: 19))
    }

    @Test func decodesChangedWithOpaqueContent() throws {
        let content: NSDictionary = ["type": "doc", "content": [["type": "paragraph", "attrs": ["level": 1, "checked": true]]]]
        let body: NSDictionary = [
            "type": "changed",
            "snapshot": ["docId": "a", "content": content, "title": "会议", "text": "会议", "wordCount": 2],
        ]
        guard case .changed(let snapshot) = try BridgeMessage.decode(scriptMessageBody: body) else {
            Issue.record("expected .changed")
            return
        }
        #expect(snapshot.docId == "a")
        #expect(snapshot.title == "会议")
        #expect(
            snapshot.content
                == .object([
                    "type": .string("doc"),
                    "content": .array([
                        .object(["type": .string("paragraph"), "attrs": .object(["level": .number(1), "checked": .bool(true)])])
                    ]),
                ]))
    }

    @Test func decodesLogAndActiveFormats() throws {
        #expect(
            try BridgeMessage.decode(scriptMessageBody: ["type": "log", "level": "warn", "message": "m"] as NSDictionary)
                == .log(level: .warn, message: "m", context: nil))
        #expect(
            try BridgeMessage.decode(scriptMessageBody: ["type": "activeFormats", "active": ["bold"]] as NSDictionary)
                == .activeFormats(["bold"]))
    }

    @Test func decodesMetadataMessages() throws {
        #expect(
            try BridgeMessage.decode(scriptMessageBody: ["type": "setIcon", "docId": "a", "icon": "👋"] as NSDictionary)
                == .setIcon(docId: "a", icon: "👋"))
        #expect(
            try BridgeMessage.decode(scriptMessageBody: ["type": "setIcon", "docId": "a", "icon": NSNull()] as NSDictionary)
                == .setIcon(docId: "a", icon: nil))
        #expect(
            try BridgeMessage.decode(scriptMessageBody: ["type": "setCover", "docId": "a", "cover": "gradient:ocean"] as NSDictionary)
                == .setCover(docId: "a", cover: "gradient:ocean"))
        #expect(
            try BridgeMessage.decode(
                scriptMessageBody: ["type": "saveAsset", "fileExtension": "png", "dataBase64": "AQID"] as NSDictionary)
                == .saveAsset(fileExtension: "png", data: Data([1, 2, 3])))
        #expect(throws: BridgeError.invalidPayload("saveAsset: dataBase64 is not base64")) {
            try BridgeMessage.decode(scriptMessageBody: ["type": "saveAsset", "fileExtension": "png", "dataBase64": "%%%"] as NSDictionary)
        }
    }

    @Test func pagePayloadCarriesTitleAndMetadataSeparatelyFromContent() throws {
        let record = DocumentRecord(
            id: "a", title: "Plan", content: #"{"type":"doc","content":[]}"#, plainText: "", wordCount: 0,
            createdAt: .now, updatedAt: .now, parentId: nil, icon: "🌊", cover: nil, favoritedAt: nil,
            deletedAt: nil, sortKey: 0)
        let payload = try PagePayload.make(from: record)
        #expect(payload["title"] as? String == "Plan")
        #expect(payload["icon"] as? String == "🌊")
        #expect(payload["cover"] is NSNull)
        #expect(payload["locked"] as? Bool == false)
        #expect((payload["content"] as? [String: Any])?["type"] as? String == "doc")
        #expect(JSONSerialization.isValidJSONObject(payload))
        var locked = record
        locked.lockedAt = .now
        #expect(try PagePayload.make(from: locked)["locked"] as? Bool == true)
    }

    @Test func rejectsUnknownTypesAndNonJSON() {
        #expect(throws: BridgeError.unknownType("nope")) { try BridgeMessage.decode(scriptMessageBody: ["type": "nope"] as NSDictionary) }
        #expect(throws: BridgeError.notJSON) { try BridgeMessage.decode(scriptMessageBody: "just a string") }
    }

    @Test func jsonValueRoundTripsIntegersWithoutTurningThemIntoFloats() throws {
        let original = Data(#"{"a":[1,2.5,true,null,"x"]}"#.utf8)
        let value = try JSONValue(jsonData: original)
        #expect(String(decoding: try value.jsonData(), as: UTF8.self) == #"{"a":[1,2.5,true,null,"x"]}"#)
    }

    @Test func decodesUploadAndOpenMessages() throws {
        func decode(_ body: [String: Any]) throws -> BridgeMessage {
            try BridgeMessage.decode(scriptMessageBody: body as NSDictionary)
        }
        #expect(try decode(["type": "beginUpload", "fileExtension": "mp4", "size": 10]) == .beginUpload(fileExtension: "mp4", size: 10))
        #expect(try decode(["type": "uploadChunk", "id": "u1", "dataBase64": "AQID"]) == .uploadChunk(id: "u1", data: Data([1, 2, 3])))
        #expect(try decode(["type": "finishUpload", "id": "u1"]) == .finishUpload(id: "u1"))
        #expect(try decode(["type": "cancelUpload", "id": "u1"]) == .cancelUpload(id: "u1"))
        #expect(
            try decode(["type": "openAsset", "url": "hikki-editor://assets/a.pdf"])
                == .openAsset(url: "hikki-editor://assets/a.pdf", name: nil))
        #expect(
            try decode(["type": "openAsset", "url": "hikki-editor://assets/a.pdf", "name": "Book.pdf"])
                == .openAsset(url: "hikki-editor://assets/a.pdf", name: "Book.pdf"))
        #expect(try decode(["type": "openPage", "id": "p1"]) == .openPage(id: "p1", block: nil))
        #expect(try decode(["type": "openPage", "id": "p1", "block": "b2"]) == .openPage(id: "p1", block: "b2"))
        #expect(try decode(["type": "openInSplit", "id": "p1"]) == .openInSplit(id: "p1"))
        #expect(try decode(["type": "splitDropHover", "active": true]) == .splitDropHover(active: true))
        #expect(
            try decode(["type": "toast", "kind": "success", "message": "Link copied"]) == .toast(kind: "success", message: "Link copied"))
        #expect(
            try decode(["type": "reportError", "code": 4004, "detail": "quota", "context": ["name": "a.png"]])
                == .reportError(code: 4004, detail: "quota", context: ["name": "a.png"]))
        #expect(try decode(["type": "activeHeading", "docId": "p1", "id": "h2"]) == .activeHeading(docId: "p1", id: "h2"))
        #expect(try decode(["type": "scroll", "docId": "p1", "top": 840]) == .scroll(docId: "p1", top: 840))
        #expect(try decode(["type": "aiCancel", "id": "r1"]) == .aiCancel(id: "r1"))
        #expect(
            try decode(["type": "aiChange", "docId": "p1", "id": "c1", "status": "approved", "before": "旧", "after": "新"])
                == .aiChange(docId: "p1", id: "c1", status: .approved, before: "旧", after: "新"))
        #expect(
            try decode(["type": "aiChange", "docId": "p1", "id": "c2", "status": "stale"])
                == .aiChange(docId: "p1", id: "c2", status: .stale, before: nil, after: nil))
        #expect(try decode(["type": "aiChangeFocus", "docId": "p1", "id": "c1"]) == .aiChangeFocus(docId: "p1", id: "c1"))
        #expect(try decode(["type": "aiChangeFocus", "docId": "p1"]) == .aiChangeFocus(docId: "p1", id: nil))
        #expect(try decode(["type": "selection", "docId": "p1", "text": "いいえ"]) == .selection(docId: "p1", text: "いいえ"))
        #expect(try decode(["type": "sheet", "open": true]) == .sheet(open: true))
        #expect(try decode(["type": "fullScreen", "open": false]) == .fullScreen(open: false))
        #expect(try decode(["type": "drawingLibrary"]) == .drawingLibrary)
        #expect(
            try decode(["type": "saveDrawingLibrary", "items": [["id": "a", "elements": []]]])
                == .saveDrawingLibrary(items: .array([.object(["id": .string("a"), "elements": .array([])])])))
        #expect(
            try decode(["type": "commentCreate", "docId": "p1", "threadId": "t", "quote": "そうです", "body": "样态"])
                == .commentCreate(docId: "p1", threadId: "t", quote: "そうです", body: "样态"))
        #expect(
            try decode([
                "type": "commentCreate", "docId": "p1", "threadId": "t", "quote": "Image", "body": "ok", "blockId": "b1",
            ])
                == .commentCreate(docId: "p1", threadId: "t", quote: "Image", body: "ok", blockId: "b1"))
        #expect(
            try decode([
                "type": "aiRequest", "id": "r2", "action": "describe", "answer": true, "units": [],
                "context": ["title": "Trip", "before": "", "after": ""],
                "media": ["url": "hikki-editor://assets/a.png", "kind": "image", "name": NSNull()],
            ])
                == .aiRequest(
                    AIRequestPayload(
                        id: "r2", action: "describe", answer: true, units: [],
                        context: .init(title: "Trip", before: "", after: ""),
                        media: .init(url: "hikki-editor://assets/a.png", kind: .image))))
        #expect(throws: (any Error).self) {
            try decode([
                "type": "aiRequest", "id": "r3", "action": "describe", "answer": true, "units": [],
                "context": ["title": "", "before": "", "after": ""],
                "media": ["url": "hikki-editor://assets/a.mov", "kind": "video"],
            ])
        }
        #expect(
            try decode(["type": "commentReply", "docId": "p1", "threadId": "t", "body": "ok"])
                == .commentReply(docId: "p1", threadId: "t", body: "ok"))
        #expect(
            try decode(["type": "commentResolve", "docId": "p1", "threadId": "t", "resolved": true])
                == .commentResolve(docId: "p1", threadId: "t", resolved: true))
        #expect(
            try decode(["type": "commentDelete", "docId": "p1", "threadId": "t"])
                == .commentDelete(docId: "p1", threadId: "t", commentId: nil))
        #expect(
            try decode(["type": "commentEdit", "docId": "p1", "threadId": "t", "commentId": "c", "body": "更正"])
                == .commentEdit(docId: "p1", threadId: "t", commentId: "c", body: "更正"))
        #expect(
            try decode([
                "type": "aiRequest", "id": "r1", "action": "tone:casual", "answer": false,
                "units": [["key": "p1:0", "html": "Hello <strong>there</strong>"]],
                "context": ["title": "Notes", "before": "", "after": "Bye"],
            ])
                == .aiRequest(
                    AIRequestPayload(
                        id: "r1", action: "tone:casual", answer: false,
                        units: [.init(key: "p1:0", html: "Hello <strong>there</strong>")],
                        context: .init(title: "Notes", before: "", after: "Bye"))))
        #expect(
            try decode(["type": "aiHandoff", "docId": "p1", "instruction": "Write a report on this", "selection": "Foxes"])
                == .aiHandoff(AIHandoff(docId: "p1", instruction: "Write a report on this", selection: "Foxes")))
        #expect(throws: (any Error).self) { try decode(["type": "aiHandoff", "docId": "p1", "instruction": "x"]) }
        #expect(try decode(["type": "activeHeading", "docId": "p1", "id": NSNull()]) == .activeHeading(docId: "p1", id: nil))
        #expect(try decode(["type": "openLink", "url": "https://example.com"]) == .openLink(url: "https://example.com"))
        #expect(try decode(["type": "suggestReading", "text": "漢字"]) == .suggestReading(text: "漢字"))
        #expect(throws: BridgeError.invalidPayload("uploadChunk: dataBase64 is not base64")) {
            try decode(["type": "uploadChunk", "id": "u1", "dataBase64": "%%%"])
        }
    }

    @Test func decodesAnImportedPageAndKnowsWhichFilesImport() throws {
        let body: [String: Any] = [
            "title": "Trip", "content": ["type": "doc", "content": [["type": "paragraph"]]], "text": "", "wordCount": 1,
        ]
        let page = try ImportedPage.decode(scriptResult: body as NSDictionary)
        #expect(page.title == "Trip" && page.wordCount == 1)
        #expect(page.content == .object(["type": .string("doc"), "content": .array([.object(["type": .string("paragraph")])])]))
        #expect(ImportFormat(fileExtension: "MD") == .markdown)
        #expect(ImportFormat(fileExtension: "htm") == .html)
        #expect(ImportFormat(fileExtension: "txt") == .text)
        #expect(ImportFormat(fileExtension: "pdf") == nil)
    }
}
