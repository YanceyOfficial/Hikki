import HikkiCore
import Observation

@Observable
final class AppModel {
    let store: DocumentStore
    let crashReporter: CrashReporter
    private(set) var summaries: [DocumentSummary] = []

    init(store: DocumentStore, crashReporter: CrashReporter) {
        self.store = store
        self.crashReporter = crashReporter
    }

    /// Keeps `summaries` in sync with the database for the lifetime of the calling task.
    func observeSummaries() async {
        do {
            for try await value in store.observeSummaries() {
                summaries = value
            }
        } catch {
            Log.error("summary observation failed: \(error)", category: "store")
        }
    }

    func createDocument() -> String? {
        do {
            return try store.create().id
        } catch {
            Log.error("create document failed: \(error)", category: "store")
            return nil
        }
    }

    func deleteDocument(id: String) {
        do {
            try store.delete(id: id)
        } catch {
            Log.error("delete document failed: \(error)", category: "store", context: ["docId": id])
        }
    }

    var exportableFiles: [URL] {
        Log.files + crashReporter.reports
    }
}
