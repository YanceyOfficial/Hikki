import CloudKit
import Foundation
import Testing

@testable import HikkiCore

struct CloudSyncTests {
    /// A server record in a conflict may come without its asset: it isn't settled from (or resent over) then.
    @Test func aRecordWithoutItsContentsIsNotReadable() throws {
        let id = CloudSync.recordID(for: "pages/p.json")
        let inline = CKRecord(recordType: CloudSync.recordType, recordID: id)
        inline.encryptedValues["path"] = "pages/p.json"
        inline.encryptedValues["data"] = Data("{}".utf8)
        #expect(CloudSync.isReadable(inline))

        let missingAsset = CKRecord(recordType: CloudSync.recordType, recordID: id)
        missingAsset.encryptedValues["path"] = "assets/a.png"
        missingAsset["file"] = CKAsset(fileURL: try makeTempDirectory().appending(path: "not-downloaded"))
        #expect(!CloudSync.isReadable(missingAsset))

        let noPath = CKRecord(recordType: CloudSync.recordType, recordID: id)
        noPath.encryptedValues["data"] = Data("{}".utf8)
        #expect(!CloudSync.isReadable(noPath))
    }
}
