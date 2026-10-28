import Compression
import Foundation

/// A zip archive read for import (a Notion export, a folder of documents): its central directory, and each entry
/// written out to a file — stored or deflated (the Compression framework's `.zlib` is raw deflate, zip's), ZIP64
/// sizes and offsets understood. Nothing more: no encryption, no other methods (`unsupportedMethod`), and no
/// writing — tests make their archives with `ZipArchive.stored`.
public struct ZipArchive: Sendable {
    public struct Entry: Equatable, Sendable {
        public var path: String
        public var isDirectory: Bool
        public var uncompressedSize: UInt64
        var compressedSize: UInt64
        var method: UInt16
        var headerOffset: UInt64
    }

    public enum ReadError: Error, Equatable {
        /// No central directory where a zip has one.
        case notAZip
        case corrupt
        /// Compressed another way than deflate (or encrypted).
        case unsupportedMethod(UInt16)
    }

    public let url: URL
    public let entries: [Entry]

    /// Reads the central directory (the end of the file).
    public init(url: URL) throws {
        self.url = url
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let length = try handle.seekToEnd()
        // The end-of-central-directory record: in the last 64 KB + 22 bytes (its comment may follow it).
        let tailLength = min(length, 65_557)
        try handle.seek(toOffset: length - tailLength)
        let tail = try handle.read(upToCount: Int(tailLength)) ?? Data()
        guard let eocd = Self.lastIndex(of: [0x50, 0x4B, 0x05, 0x06], in: tail) else { throw ReadError.notAZip }
        var count = UInt64(tail.u16(eocd + 10))
        var directorySize = UInt64(tail.u32(eocd + 12))
        var directoryOffset = UInt64(tail.u32(eocd + 16))
        // ZIP64: the counts saturate and a locator before the record points at the real one.
        if count == 0xFFFF || directorySize == 0xFFFF_FFFF || directoryOffset == 0xFFFF_FFFF, eocd >= 20,
            tail.u32(eocd - 20) == 0x0706_4B50
        {
            let zip64Offset = tail.u64(eocd - 20 + 8)
            try handle.seek(toOffset: zip64Offset)
            let record = try handle.read(upToCount: 56) ?? Data()
            guard record.count == 56, record.u32(0) == 0x0606_4B50 else { throw ReadError.corrupt }
            count = record.u64(32)
            directorySize = record.u64(40)
            directoryOffset = record.u64(48)
        }
        guard directoryOffset + directorySize <= length, directorySize < 256 * 1024 * 1024 else { throw ReadError.corrupt }
        try handle.seek(toOffset: directoryOffset)
        let directory = try handle.read(upToCount: Int(directorySize)) ?? Data()
        var entries: [Entry] = []
        var at = 0
        while entries.count < count, at + 46 <= directory.count {
            guard directory.u32(at) == 0x0201_4B50 else { throw ReadError.corrupt }
            let flags = directory.u16(at + 8)
            let method = directory.u16(at + 10)
            var compressed = UInt64(directory.u32(at + 20))
            var uncompressed = UInt64(directory.u32(at + 24))
            let nameLength = Int(directory.u16(at + 28))
            let extraLength = Int(directory.u16(at + 30))
            let commentLength = Int(directory.u16(at + 32))
            var headerOffset = UInt64(directory.u32(at + 42))
            let nameStart = at + 46
            guard nameStart + nameLength + extraLength + commentLength <= directory.count else { throw ReadError.corrupt }
            let nameData = directory.subdata(in: nameStart..<nameStart + nameLength)
            // Names are UTF-8 when flagged (bit 11), else the maker's code page — read as UTF-8, else Latin-1.
            let name =
                String(data: nameData, encoding: .utf8) ?? String(data: nameData, encoding: .isoLatin1) ?? ""
            // ZIP64 extra field (0x0001): the saturated sizes and offset, in that order, only those saturated.
            var extraAt = nameStart + nameLength
            let extraEnd = extraAt + extraLength
            while extraAt + 4 <= extraEnd {
                let id = directory.u16(extraAt)
                let size = Int(directory.u16(extraAt + 2))
                if id == 0x0001 {
                    var field = extraAt + 4
                    if uncompressed == 0xFFFF_FFFF, field + 8 <= extraEnd {
                        uncompressed = directory.u64(field)
                        field += 8
                    }
                    if compressed == 0xFFFF_FFFF, field + 8 <= extraEnd {
                        compressed = directory.u64(field)
                        field += 8
                    }
                    if headerOffset == 0xFFFF_FFFF, field + 8 <= extraEnd { headerOffset = directory.u64(field) }
                }
                extraAt += 4 + size
            }
            _ = flags
            entries.append(
                Entry(
                    path: name, isDirectory: name.hasSuffix("/"), uncompressedSize: uncompressed, compressedSize: compressed,
                    method: method, headerOffset: headerOffset))
            at = nameStart + nameLength + extraLength + commentLength
        }
        self.entries = entries
    }

    /// Writes the entry's contents to `destination` (made or replaced); a directory entry makes the folder.
    public func extract(_ entry: Entry, to destination: URL) throws {
        if entry.isDirectory {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            return
        }
        guard entry.method == 0 || entry.method == 8 else { throw ReadError.unsupportedMethod(entry.method) }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        // The local header before the data repeats the name and may carry its own extra field.
        try handle.seek(toOffset: entry.headerOffset)
        let header = try handle.read(upToCount: 30) ?? Data()
        guard header.count == 30, header.u32(0) == 0x0403_4B50 else { throw ReadError.corrupt }
        let dataOffset = entry.headerOffset + 30 + UInt64(header.u16(26)) + UInt64(header.u16(28))
        try handle.seek(toOffset: dataOffset)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        var remaining = entry.compressedSize
        let chunk = 256 * 1024
        if entry.method == 0 {
            while remaining > 0 {
                let piece = try handle.read(upToCount: Int(min(UInt64(chunk), remaining))) ?? Data()
                guard !piece.isEmpty else { throw ReadError.corrupt }
                try output.write(contentsOf: piece)
                remaining -= UInt64(piece.count)
            }
            return
        }
        var written: UInt64 = 0
        let filter = try InputFilter(.decompress, using: .zlib) { count -> Data? in
            guard remaining > 0 else { return nil }
            let piece = try handle.read(upToCount: Int(min(UInt64(min(count, chunk)), remaining))) ?? Data()
            remaining -= UInt64(piece.count)
            return piece
        }
        while let page = try filter.readData(ofLength: chunk) {
            guard !page.isEmpty else { break }
            try output.write(contentsOf: page)
            written += UInt64(page.count)
        }
        guard written == entry.uncompressedSize else { throw ReadError.corrupt }
    }

    private static func lastIndex(of signature: [UInt8], in data: Data) -> Int? {
        guard data.count >= signature.count else { return nil }
        var i = data.count - signature.count
        while i >= 0 {
            if data[data.startIndex + i] == signature[0], data.subdata(in: i..<i + signature.count).elementsEqual(signature) {
                return i
            }
            i -= 1
        }
        return nil
    }

    // MARK: - Making one (tests, and nothing else writes archives yet)

    /// A zip of `files` with every entry stored (no compression), in order, as a test fixture or a plain container.
    public static func stored(_ files: [(path: String, data: Data)]) -> Data {
        var out = Data()
        var directory = Data()
        for (path, data) in files {
            let name = Data(path.utf8)
            let crc = crc32(data)
            let offset = UInt32(out.count)
            out.append(le32(0x0403_4B50))
            out.append(le16(20))  // version needed
            out.append(le16(0x0800))  // UTF-8 names
            out.append(le16(0))  // stored
            out.append(le16(0))
            out.append(le16(0))  // time, date
            out.append(le32(crc))
            out.append(le32(UInt32(data.count)))
            out.append(le32(UInt32(data.count)))
            out.append(le16(UInt16(name.count)))
            out.append(le16(0))
            out.append(name)
            out.append(data)
            directory.append(le32(0x0201_4B50))
            directory.append(le16(20))
            directory.append(le16(20))
            directory.append(le16(0x0800))
            directory.append(le16(0))
            directory.append(le16(0))
            directory.append(le16(0))
            directory.append(le32(crc))
            directory.append(le32(UInt32(data.count)))
            directory.append(le32(UInt32(data.count)))
            directory.append(le16(UInt16(name.count)))
            directory.append(le16(0))
            directory.append(le16(0))
            directory.append(le16(0))
            directory.append(le16(0))
            directory.append(le32(0))
            directory.append(le32(offset))
            directory.append(name)
        }
        let directoryOffset = UInt32(out.count)
        out.append(directory)
        out.append(le32(0x0605_4B50))
        out.append(le16(0))
        out.append(le16(0))
        out.append(le16(UInt16(files.count)))
        out.append(le16(UInt16(files.count)))
        out.append(le32(UInt32(directory.count)))
        out.append(le32(directoryOffset))
        out.append(le16(0))
        return out
    }

    private static func le16(_ value: UInt16) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
    private static func le32(_ value: UInt32) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }

    static func crc32(_ data: Data) -> UInt32 {
        var table = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var c = UInt32(i)
            for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
            table[i] = c
        }
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFF_FFFF
    }
}

extension Data {
    fileprivate func u16(_ offset: Int) -> UInt16 {
        UInt16(self[startIndex + offset]) | UInt16(self[startIndex + offset + 1]) << 8
    }

    fileprivate func u32(_ offset: Int) -> UInt32 {
        UInt32(u16(offset)) | UInt32(u16(offset + 2)) << 16
    }

    fileprivate func u64(_ offset: Int) -> UInt64 {
        UInt64(u32(offset)) | UInt64(u32(offset + 4)) << 32
    }
}
