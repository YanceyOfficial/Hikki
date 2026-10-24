import Foundation
import Testing

@testable import HikkiCore

struct PageSyncStateTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func state(_ uploads: CloudUploads, _ id: String = "a", editing: Bool = false, cloud: PageSyncState.Cloud = .on)
        -> PageSyncState?
    {
        PageSyncState.resolve(
            editing: editing, savedAt: uploads.pages[id]?.savedAt, cloud: cloud, upload: uploads.pages[id],
            offline: uploads.offline)
    }

    @Test func pathsNameTheirPages() {
        #expect(CloudUploads.pageID(forPath: "pages/abc.json") == "abc")
        #expect(CloudUploads.pageID(forPath: "pages/.json") == nil)
        #expect(CloudUploads.pageID(forPath: "comments/abc.json") == nil)
        #expect(CloudUploads.pageID(forPath: "pages/a/b.json") == nil)
        #expect(CloudUploads.pageID(forPath: "pages/abc.txt") == nil)
    }

    /// Nothing edited in this run shows nothing; typing shows Saving… whatever the cloud is doing.
    @Test func untouchedPagesShowNothingAndTypingIsSaving() {
        let uploads = CloudUploads()
        #expect(state(uploads) == nil)
        #expect(state(uploads, editing: true) == .saving)
        #expect(state(uploads, editing: true, cloud: .off) == .saving)
    }

    /// A save goes: uploading (until a scan), queued, sent, then synced once the cloud acknowledged that file.
    @Test func aSaveGoesUpAndIsAcknowledged() {
        var uploads = CloudUploads()
        let changed1 = uploads.saved("a", at: t0, written: t0 + 0.05)
        #expect(changed1)
        #expect(state(uploads) == .uploading)
        let changed2 = uploads.scanned(changed: ["pages/a.json", "assets/x.png"], at: t0 + 1)
        #expect(changed2)
        #expect(uploads.pages["a"]?.phase == .queued)
        #expect(state(uploads) == .uploading)
        let changed3 = uploads.sending("pages/a.json", asOf: t0 + 0.01)
        #expect(changed3)
        #expect(state(uploads) == .uploading)
        let changed4 = uploads.uploaded("pages/a.json", asOf: t0 + 0.01, at: t0 + 3)
        #expect(changed4)
        #expect(state(uploads) == .synced(t0 + 3))
        // Another scan changes nothing: no publish for nothing.
        let changed5 = uploads.scanned(changed: [], at: t0 + 10)
        #expect(!changed5)
        #expect(state(uploads) == .synced(t0 + 3))
    }

    /// An acknowledgement of a file older than the latest save isn't "synced".
    @Test func anOlderUploadDoesNotCountForANewerSave() {
        var uploads = CloudUploads()
        uploads.saved("a", at: t0, written: t0 + 0.05)
        uploads.sending("pages/a.json", asOf: t0 + 0.01)
        uploads.saved("a", at: t0 + 2, written: t0 + 2 + 0.05)
        uploads.uploaded("pages/a.json", asOf: t0 + 0.01, at: t0 + 3)
        #expect(state(uploads) == .uploading)
        uploads.scanned(changed: ["pages/a.json"], at: t0 + 4)
        #expect(uploads.pages["a"]?.phase == .queued)
    }

    /// A save that left the file as it was (or one a scan finds already agreed) counts as in the cloud then.
    @Test func anUnchangedFileIsInTheCloudAsOfTheScan() {
        var uploads = CloudUploads()
        uploads.saved("a", at: t0, written: t0 + 0.05)
        let changed6 = uploads.scanned(changed: [], at: t0 + 1)
        #expect(changed6)
        #expect(state(uploads) == .synced(t0 + 1))
        // Untracked pages are never followed.
        #expect(uploads.pages["b"] == nil)
        let changed7 = uploads.uploaded("pages/b.json", asOf: t0, at: t0)
        #expect(!changed7)
    }

    /// A scan that started before the save's file was written may have read the file before: it vouches for
    /// nothing; one that started after does.
    @Test func aScanFromBeforeTheWriteDoesNotVouch() {
        var uploads = CloudUploads()
        uploads.saved("a", at: t0, written: t0 + 0.5)
        let early = uploads.scanned(changed: [], at: t0 + 0.2)
        #expect(!early)
        #expect(state(uploads) == .uploading)
        uploads.scanned(changed: [], at: t0 + 0.6)
        #expect(state(uploads) == .synced(t0 + 0.6))
        // Saved again: the earlier agreement is too old, and an early scan leaves it so.
        uploads.saved("a", at: t0 + 2, written: t0 + 2.5)
        uploads.scanned(changed: [], at: t0 + 2.2)
        #expect(state(uploads) == .uploading)
    }

    /// Saved again while the file is in a batch: it stays there, and its acknowledgement doesn't count for the
    /// newer save.
    @Test func aSaveDuringABatchWaitsForTheNextOne() {
        var uploads = CloudUploads()
        uploads.saved("a", at: t0, written: t0 + 0.05)
        uploads.sending("pages/a.json", asOf: t0 + 0.01)
        uploads.saved("a", at: t0 + 1, written: t0 + 1.05)
        #expect(uploads.pages["a"]?.phase == .sending(asOf: t0 + 0.01))
        #expect(uploads.pages["a"]?.savedAt == t0 + 1)
        uploads.uploaded("pages/a.json", asOf: t0 + 0.01, at: t0 + 2)
        #expect(state(uploads) == .uploading)
        uploads.sending("pages/a.json", asOf: t0 + 1.01)
        uploads.uploaded("pages/a.json", asOf: t0 + 1.01, at: t0 + 3)
        #expect(state(uploads) == .synced(t0 + 3))
    }

    /// A scan while the file is in a batch leaves it to its acknowledgement.
    @Test func aScanLeavesAFileBeingSentAlone() {
        var uploads = CloudUploads()
        uploads.saved("a", at: t0, written: t0 + 0.05)
        uploads.sending("pages/a.json", asOf: t0 + 0.01)
        let changed8 = uploads.scanned(changed: ["pages/a.json"], at: t0 + 1)
        #expect(!changed8)
        let changed9 = uploads.scanned(changed: [], at: t0 + 1)
        #expect(!changed9)
        #expect(uploads.pages["a"]?.phase == .sending(asOf: t0 + 0.01))
    }

    @Test func offlineAndRefusalsWait() {
        var uploads = CloudUploads()
        uploads.saved("a", at: t0, written: t0 + 0.05)
        let changed10 = uploads.setOffline(true)
        #expect(changed10)
        let changed11 = uploads.setOffline(true)
        #expect(!changed11)
        #expect(state(uploads) == .waiting)
        uploads.setOffline(false)
        uploads.refused("pages/a.json", retry: .retrying)
        #expect(state(uploads) == .waiting)
        uploads.refused("pages/a.json", retry: .failed)
        #expect(state(uploads) == .notSyncing(.failed))
        // Synced stays synced offline: the cloud has it.
        uploads.uploaded("pages/a.json", asOf: t0, at: t0 + 1)
        uploads.setOffline(true)
        #expect(state(uploads) == .synced(t0 + 1))
    }

    @Test func theWorkspaceDecidesFirst() {
        var uploads = CloudUploads()
        uploads.saved("a", at: t0, written: t0 + 0.05)
        uploads.uploaded("pages/a.json", asOf: t0, at: t0 + 1)
        #expect(state(uploads, cloud: .off) == .savedOnDevice(t0))
        #expect(state(uploads, cloud: .trouble(.noAccount)) == .notSyncing(.noAccount))
        #expect(state(uploads, cloud: .trouble(.accountChanged)) == .notSyncing(.accountChanged))
    }
}
