import Foundation
import Synchronization
import os

public enum LogLevel: String, Codable, Sendable, CaseIterable {
    case debug, info, warn, error

    var osType: OSLogType {
        switch self {
        case .debug: .debug
        case .info: .info
        case .warn: .default
        case .error: .error
        }
    }
}

public struct LogEntry: Codable, Sendable, Equatable {
    public var timestamp: Date
    public var level: LogLevel
    public var category: String
    public var message: String
    public var context: [String: String]?
    /// The app run it came from (`Log.session`), so one run's lines can be picked out of an exported log.
    public var session: String?

    public init(
        timestamp: Date, level: LogLevel, category: String, message: String, context: [String: String]? = nil,
        session: String? = nil
    ) {
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
        self.context = context
        self.session = session
    }
}

/// App-wide logging facade: every entry goes to unified logging (Console.app / `log stream`)
/// and, once bootstrapped, to a rotating JSONL file the user can export with a bug report.
/// Writes are synchronous so an entry logged right before a crash still reaches disk.
public enum Log {
    public static let subsystem = "app.hikki"
    private static let sink = Mutex<FileLogSink?>(nil)
    /// This run's id, on every entry.
    public static let session = Incident.newID()

    public static func bootstrap(directory: URL) throws {
        let fileSink = try FileLogSink(directory: directory)
        sink.withLock { $0 = fileSink }
    }

    public static var files: [URL] {
        sink.withLock { $0?.files ?? [] }
    }

    /// The newest entries in the log files, newest first (Settings → About → Logs).
    public static func recent(limit: Int = 500) -> [LogEntry] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var entries: [LogEntry] = []
        // `files` runs newest first; each file is oldest-first inside.
        for file in files {
            guard let data = try? Data(contentsOf: file) else { continue }
            let lines = data.split(separator: UInt8(ascii: "\n")).reversed()
            for line in lines {
                if let entry = try? decoder.decode(LogEntry.self, from: Data(line)) { entries.append(entry) }
                if entries.count >= limit { return entries }
            }
        }
        return entries
    }

    public static func debug(_ message: String, category: String = "app", context: [String: String]? = nil) {
        write(.debug, message, category: category, context: context)
    }

    public static func info(_ message: String, category: String = "app", context: [String: String]? = nil) {
        write(.info, message, category: category, context: context)
    }

    public static func warn(_ message: String, category: String = "app", context: [String: String]? = nil) {
        write(.warn, message, category: category, context: context)
    }

    public static func error(_ message: String, category: String = "app", context: [String: String]? = nil) {
        write(.error, message, category: category, context: context)
    }

    public static func write(_ level: LogLevel, _ message: String, category: String, context: [String: String]?) {
        let suffix = context.map { " \($0)" } ?? ""
        Logger(subsystem: subsystem, category: category).log(level: level.osType, "\(message, privacy: .public)\(suffix, privacy: .public)")
        let entry = LogEntry(
            timestamp: .now, level: level, category: category, message: message, context: context, session: session)
        sink.withLock { $0?.write(entry) }
    }
}
