import Foundation
import Synchronization

/// Appends JSON Lines to `hikki.log`, rotating to `hikki.1.log` … `hikki.<maxFiles-1>.log`.
public final class FileLogSink: Sendable {
    public let directory: URL
    public let maxBytes: UInt64
    public let maxFiles: Int

    private struct State: ~Copyable {
        var handle: FileHandle?
        var size: UInt64
    }

    private let state: Mutex<State>
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    public init(directory: URL, maxBytes: UInt64 = 5 * 1024 * 1024, maxFiles: Int = 3) throws {
        precondition(maxFiles >= 1)
        self.directory = directory
        self.maxBytes = maxBytes
        self.maxFiles = maxFiles
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let current = directory.appending(path: "hikki.log")
        let size = (try? FileManager.default.attributesOfItem(atPath: current.path)[.size] as? UInt64) ?? 0
        state = Mutex(State(handle: nil, size: size ?? 0))
    }

    public var currentFile: URL { file(at: 0) }

    /// Newest first.
    public var files: [URL] {
        (0..<maxFiles).map(file(at:)).filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    public func write(_ entry: LogEntry) {
        guard var line = try? encoder.encode(entry) else { return }
        line.append(0x0A)
        let encoded = line
        state.withLock { state in
            if state.size > 0, state.size + UInt64(encoded.count) > maxBytes {
                rotate(&state)
            }
            if state.handle == nil {
                state.handle = openForAppend()
            }
            guard let handle = state.handle else { return }
            do {
                try handle.write(contentsOf: encoded)
                state.size += UInt64(encoded.count)
            } catch {
                state.handle = nil
            }
        }
    }

    private func file(at index: Int) -> URL {
        directory.appending(path: index == 0 ? "hikki.log" : "hikki.\(index).log")
    }

    private func openForAppend() -> FileHandle? {
        let url = currentFile
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return nil }
        _ = try? handle.seekToEnd()
        return handle
    }

    private func rotate(_ state: inout State) {
        try? state.handle?.close()
        state.handle = nil
        let fm = FileManager.default
        try? fm.removeItem(at: file(at: maxFiles - 1))
        if maxFiles > 1 {
            for index in stride(from: maxFiles - 2, through: 0, by: -1) {
                try? fm.moveItem(at: file(at: index), to: file(at: index + 1))
            }
        } else {
            try? fm.removeItem(at: currentFile)
        }
        state.size = 0
    }
}
