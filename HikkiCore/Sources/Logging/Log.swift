import Foundation
import os
import Synchronization

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

    public init(timestamp: Date, level: LogLevel, category: String, message: String, context: [String: String]? = nil) {
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
        self.context = context
    }
}

/// App-wide logging facade: every entry goes to unified logging (Console.app / `log stream`)
/// and, once bootstrapped, to a rotating JSONL file the user can export with a bug report.
/// Writes are synchronous so an entry logged right before a crash still reaches disk.
public enum Log {
    public static let subsystem = "app.hikki"
    private static let sink = Mutex<FileLogSink?>(nil)

    public static func bootstrap(directory: URL) throws {
        let fileSink = try FileLogSink(directory: directory)
        sink.withLock { $0 = fileSink }
    }

    public static var files: [URL] {
        sink.withLock { $0?.files ?? [] }
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
        let entry = LogEntry(timestamp: .now, level: level, category: category, message: message, context: context)
        sink.withLock { $0?.write(entry) }
    }
}
