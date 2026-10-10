import Foundation
import Testing

@testable import HikkiCore

struct MoveTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func store(_ setup: (DocumentStore) throws -> Void) throws -> DocumentStore {
        let store = try DocumentStore.inMemory()
        try setup(store)
        return store
    }

    private func children(_ store: DocumentStore, of parent: String?) throws -> [String] {
        try store.pages().filter { $0.parentId == parent }.map(\.id)
    }

    @Test func reordersSiblings() throws {
        let s = try store { s in for id in ["a", "b", "c"] { try s.create(id: id, now: t0) } }
        try s.move(id: "c", toParent: nil, at: 0)
        #expect(try children(s, of: nil) == ["c", "a", "b"])
        try s.move(id: "c", toParent: nil, at: 99)  // clamped to the end
        #expect(try children(s, of: nil) == ["a", "b", "c"])
    }

    @Test func nestsAPageUnderAnotherAndBack() throws {
        let s = try store { s in
            try s.create(id: "a", now: t0)
            try s.create(id: "b", now: t0)
            try s.create(id: "a1", parentId: "a", now: t0)
        }
        try s.move(id: "b", toParent: "a", at: 0)
        #expect(try children(s, of: "a") == ["b", "a1"])
        #expect(try children(s, of: nil) == ["a"])
        try s.move(id: "b", toParent: nil, at: 1)
        #expect(try children(s, of: nil) == ["a", "b"])
    }

    @Test func movingCarriesTheSubtree() throws {
        let s = try store { s in
            try s.create(id: "a", now: t0)
            try s.create(id: "b", now: t0)
            try s.create(id: "b1", parentId: "b", now: t0)
        }
        try s.move(id: "b", toParent: "a", at: 0)
        #expect(PageTree(try s.pages()).path(to: "b1").map(\.id) == ["a", "b", "b1"])
    }

    @Test func refusesCycles() throws {
        let s = try store { s in
            try s.create(id: "a", now: t0)
            try s.create(id: "a1", parentId: "a", now: t0)
            try s.create(id: "a1x", parentId: "a1", now: t0)
        }
        #expect(throws: DocumentStore.MoveError.wouldCreateCycle) { try s.move(id: "a", toParent: "a", at: 0) }
        #expect(throws: DocumentStore.MoveError.wouldCreateCycle) { try s.move(id: "a", toParent: "a1x", at: 0) }
        #expect(try children(s, of: nil) == ["a"])  // unchanged
    }

    @Test func refusesUnknownPages() throws {
        let s = try store { s in try s.create(id: "a", now: t0) }
        #expect(throws: DocumentStore.MoveError.notFound("ghost")) { try s.move(id: "ghost", toParent: nil, at: 0) }
        #expect(throws: DocumentStore.MoveError.notFound("ghost")) { try s.move(id: "a", toParent: "ghost", at: 0) }
    }

    @Test func movingIsNotAnEdit() throws {
        let s = try store { s in
            try s.create(id: "a", now: t0)
            try s.create(id: "b", now: t0)
        }
        try s.move(id: "b", toParent: "a", at: 0)
        #expect(try s.document(id: "b")?.updatedAt == t0)
    }

    @Test func trashedSiblingsDoNotTakeUpPositions() throws {
        let s = try store { s in for id in ["a", "b", "c"] { try s.create(id: id, now: t0) } }
        try s.moveToTrash(id: "b")
        try s.move(id: "c", toParent: nil, at: 1)
        #expect(try children(s, of: nil) == ["a", "c"])
        try s.restore(id: "b")
        #expect(try children(s, of: nil).first == "a")
    }
}
