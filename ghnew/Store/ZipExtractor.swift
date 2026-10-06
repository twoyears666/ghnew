import Foundation
import zlib

/// Minimal, dependency-free ZIP reader used to unpack Actions artifacts.
///
/// GitHub serves Actions artifacts as zip archives whose download name carries no
/// extension; `DownloadManager` gives them a `.zip` suffix and `ZipExtractor`
/// unpacks them in place afterwards. It supports the two compression methods
/// artifacts actually use — stored (0) and deflate (8) — via the system `zlib`.
/// Zip64, encryption and multi-disk archives are intentionally not supported.
enum ZipExtractor {
    enum ZipError: Error, LocalizedError {
        case notAZip
        case truncated
        case unsupportedCompression(UInt16)
        case inflateFailed

        var errorDescription: String? {
            switch self {
            case .notAZip: return "Not a valid zip archive."
            case .truncated: return "Zip archive is truncated."
            case .unsupportedCompression(let method):
                return "Unsupported zip compression method \(method)."
            case .inflateFailed: return "Failed to inflate zip entry."
            }
        }
    }

    private struct Entry {
        let name: String
        let method: UInt16
        /// Byte range of the compressed payload inside the archive, when locatable.
        let dataRange: Range<Int>?
    }

    /// Extract `archive` into `directory`, preserving the archive's folder
    /// structure. Returns the number of files written.
    @discardableResult
    static func extract(_ archive: URL, to directory: URL) throws -> Int {
        // Memory-map rather than loading the whole archive into the heap.
        let data = try Data(contentsOf: archive, options: .mappedIfSafe)
        let entries = try centralDirectory(in: data)
        let fm = FileManager.default
        var fileCount = 0

        for entry in entries {
            let name = sanitized(entry.name)
            guard !name.isEmpty else { continue }
            let destination = directory.appendingPathComponent(name)

            // Directory entry.
            if entry.name.hasSuffix("/") {
                try? fm.createDirectory(at: destination, withIntermediateDirectories: true)
                continue
            }

            guard let range = entry.dataRange else { continue }
            let compressed = data.subdata(in: range)
            let payload: Data
            switch entry.method {
            case 0:
                payload = compressed
            case 8:
                payload = try inflateRaw(compressed)
            default:
                throw ZipError.unsupportedCompression(entry.method)
            }

            try fm.createDirectory(at: destination.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
            try payload.write(to: destination, options: .atomic)
            fileCount += 1
        }
        return fileCount
    }

    // MARK: - Parsing

    private static func centralDirectory(in data: Data) throws -> [Entry] {
        let count = data.count
        guard count >= 22 else { throw ZipError.notAZip }

        // Locate the End Of Central Directory record by scanning backwards.
        let eocdSignature: UInt32 = 0x06054b50
        let lowest = max(0, count - 22 - 65535)
        var eocd = -1
        var cursor = count - 22
        while cursor >= lowest {
            if data.readUInt32(at: cursor) == eocdSignature {
                eocd = cursor
                break
            }
            cursor -= 1
        }
        guard eocd >= 0 else { throw ZipError.notAZip }

        let total = Int(data.readUInt16(at: eocd + 10))
        let cdSize = Int(data.readUInt32(at: eocd + 12))
        let cdOffset = Int(data.readUInt32(at: eocd + 16))
        guard cdOffset >= 0, cdOffset + cdSize <= count else { throw ZipError.truncated }

        let cdSignature: UInt32 = 0x02014b50
        let localSignature: UInt32 = 0x04034b50
        var entries: [Entry] = []
        var p = cdOffset

        for _ in 0..<total {
            guard p + 46 <= count, data.readUInt32(at: p) == cdSignature else { break }
            let method = data.readUInt16(at: p + 10)
            let compressedSize = Int(data.readUInt32(at: p + 20))
            let nameLength = Int(data.readUInt16(at: p + 28))
            let extraLength = Int(data.readUInt16(at: p + 30))
            let commentLength = Int(data.readUInt16(at: p + 32))
            let localOffset = Int(data.readUInt32(at: p + 42))
            let nameStart = p + 46
            guard nameStart + nameLength <= count else { throw ZipError.truncated }
            let name = String(decoding: data.subdata(in: nameStart..<(nameStart + nameLength)),
                              as: UTF8.self)

            // Resolve the payload from the *local* header: its own name/extra
            // lengths can differ from the central directory's.
            var range: Range<Int>?
            if localOffset >= 0, localOffset + 30 <= count,
               data.readUInt32(at: localOffset) == localSignature {
                let localNameLength = Int(data.readUInt16(at: localOffset + 26))
                let localExtraLength = Int(data.readUInt16(at: localOffset + 28))
                let start = localOffset + 30 + localNameLength + localExtraLength
                if start >= 0, start + compressedSize <= count {
                    range = start..<(start + compressedSize)
                }
            }

            entries.append(Entry(name: name, method: method, dataRange: range))
            p = nameStart + nameLength + extraLength + commentLength
        }
        return entries
    }

    /// Drop `.`/`..` components so a crafted entry can never escape `directory`.
    private static func sanitized(_ name: String) -> String {
        let parts = name.split(separator: "/", omittingEmptySubsequences: true)
            .filter { $0 != "." && $0 != ".." }
        return parts.joined(separator: "/")
    }

    // MARK: - Raw deflate

    /// Inflate raw DEFLATE data (`windowBits = -15`, no zlib/gzip wrapper).
    private static func inflateRaw(_ input: Data) throws -> Data {
        var stream = z_stream()
        let initResult = inflateInit2_(&stream, -15, zlibVersion(),
                                       Int32(MemoryLayout<z_stream>.size))
        guard initResult == Z_OK else { throw ZipError.inflateFailed }
        defer { inflateEnd(&stream) }

        let bufferSize = 1 << 16
        var output = Data()
        var buffer = [UInt8](repeating: 0, count: bufferSize)

        let succeeded = input.withUnsafeBytes { raw -> Bool in
            guard let base = raw.bindMemory(to: Bytef.self).baseAddress else { return true }
            stream.next_in = UnsafeMutablePointer(mutating: base)
            stream.avail_in = uInt(raw.count)

            while true {
                let produced = buffer.withUnsafeMutableBytes { outRaw -> Int in
                    let outPointer = outRaw.bindMemory(to: Bytef.self).baseAddress!
                    stream.next_out = outPointer
                    stream.avail_out = uInt(bufferSize)
                    let status = inflate(&stream, Z_NO_FLUSH)
                    if status != Z_OK && status != Z_STREAM_END && status != Z_BUF_ERROR {
                        return -1
                    }
                    return bufferSize - Int(stream.avail_out)
                }
                if produced < 0 { return false }
                if produced > 0 { output.append(contentsOf: buffer[0..<produced]) }
                // A short write means the stream ended or the input is exhausted.
                if stream.avail_out != 0 || produced == 0 { return true }
            }
        }
        guard succeeded else { throw ZipError.inflateFailed }
        return output
    }
}

private extension Data {
    func readUInt16(at offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= count else { return 0 }
        let base = startIndex + offset
        return UInt16(self[base]) | (UInt16(self[base + 1]) << 8)
    }

    func readUInt32(at offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= count else { return 0 }
        let base = startIndex + offset
        return UInt32(self[base])
            | (UInt32(self[base + 1]) << 8)
            | (UInt32(self[base + 2]) << 16)
            | (UInt32(self[base + 3]) << 24)
    }
}