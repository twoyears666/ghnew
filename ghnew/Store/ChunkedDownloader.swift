import Foundation

/// Downloads a single file in parallel byte-range chunks and stitches the parts
/// back together. Used by `DownloadManager` when the "并发" (concurrency) option
/// is on and the server supports range requests. Reports progress/finish through
/// callbacks; all callbacks fire on the main thread.
final class ChunkedDownloader: NSObject {
    /// (item key, progress 0...1)
    var onProgress: ((String, Double) -> Void)?
    /// (item key, final file URL on success, error on failure)
    var onFinish: ((String, URL?, Error?) -> Void)?

    /// Only bother chunking files larger than this.
    static let threshold: Int64 = 1_048_576   // 1 MB

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 120
        return URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }()

    private struct Job {
        let key: String
        let total: Int64
        let target: URL
        let partDir: URL
        var parts: [URL?]
        var bytes: [Int64]
    }

    private var jobs: [String: Job] = [:]
    private var taskMap: [Int: (key: String, index: Int)] = [:]

    /// Probe whether `url` supports range requests. Returns the total byte size
    /// only when the server honoured a `bytes=0-0` range request.
    func probeTotal(url: URL, token: String?) async -> Int64? {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        req.setValue("ghnew/1.0", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 30
        if let token, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        }
        let probeSession = URLSession(configuration: .ephemeral)
        defer { probeSession.finishTasksAndInvalidate() }
        do {
            let (_, resp) = try await probeSession.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 206 else { return nil }
            // Content-Range: bytes 0-0/<total>
            if let cr = http.value(forHTTPHeaderField: "Content-Range"),
               let totalPart = cr.split(separator: "/").last,
               let total = Int64(totalPart.trimmingCharacters(in: .whitespaces)),
               total > 0 {
                return total
            }
            return nil
        } catch {
            return nil
        }
    }

    /// Start downloading `url` into `target` using `level` parallel connections.
    func start(key: String, url: URL, token: String?, total: Int64, level: Int, target: URL) {
        let count = max(2, min(level, 16))
        let partSize = max(1, (total + Int64(count) - 1) / Int64(count))
        var ranges: [(start: Int64, end: Int64)] = []
        var start: Int64 = 0
        while start < total {
            let end = min(start + partSize - 1, total - 1)
            ranges.append((start, end))
            start = end + 1
        }

        let partDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghnew-parts-\(key.replacingOccurrences(of: "/", with: "_"))",
                                    isDirectory: true)
        try? FileManager.default.removeItem(at: partDir)
        try? FileManager.default.createDirectory(at: partDir, withIntermediateDirectories: true)

        jobs[key] = Job(key: key, total: total, target: target, partDir: partDir,
                        parts: Array(repeating: nil, count: ranges.count),
                        bytes: Array(repeating: 0, count: ranges.count))

        for (index, range) in ranges.enumerated() {
            var req = URLRequest(url: url)
            req.setValue("bytes=\(range.start)-\(range.end)", forHTTPHeaderField: "Range")
            req.setValue("ghnew/1.0", forHTTPHeaderField: "User-Agent")
            req.timeoutInterval = 120
            if let token, !token.isEmpty {
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            }
            let task = session.downloadTask(with: req)
            taskMap[task.taskIdentifier] = (key, index)
            task.resume()
        }
    }

    // MARK: - Stitching

    private func finish(_ job: Job) {
        do {
            _ = FileManager.default.createFile(atPath: job.target.path, contents: nil)
            let out = try FileHandle(forWritingTo: job.target)
            defer { try? out.close() }
            for part in job.parts {
                guard let part else { continue }
                let input = try FileHandle(forReadingFrom: part)
                defer { try? input.close() }
                while true {
                    let data = try input.read(upToCount: 1 << 20) ?? Data()
                    if data.isEmpty { break }
                    try out.write(contentsOf: data)
                }
            }
            try? FileManager.default.removeItem(at: job.partDir)
            jobs[job.key] = nil
            onFinish?(job.key, job.target, nil)
        } catch {
            fail(key: job.key, error: error)
        }
    }

    private func fail(key: String, error: Error?) {
        guard let job = jobs[key] else { return }
        try? FileManager.default.removeItem(at: job.target)
        try? FileManager.default.removeItem(at: job.partDir)
        jobs[key] = nil
        onFinish?(key, nil, error)
    }
}

extension ChunkedDownloader: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard let (key, index) = taskMap[downloadTask.taskIdentifier],
              var job = jobs[key], index < job.bytes.count else { return }
        job.bytes[index] = totalBytesWritten
        jobs[key] = job
        let received = job.bytes.reduce(0, +)
        onProgress?(key, min(max(Double(received) / Double(job.total), 0), 1))
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let (key, index) = taskMap[downloadTask.taskIdentifier],
              var job = jobs[key] else { return }
        taskMap[downloadTask.taskIdentifier] = nil

        let partURL = job.partDir.appendingPathComponent("part-\(index)")
        try? FileManager.default.removeItem(at: partURL)
        do {
            try FileManager.default.moveItem(at: location, to: partURL)
        } catch {
            fail(key: key, error: error)
            return
        }
        job.parts[index] = partURL
        jobs[key] = job
        if job.parts.allSatisfy({ $0 != nil }) {
            finish(job)
        }
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        guard let (key, _) = taskMap[task.taskIdentifier] else { return }
        taskMap[task.taskIdentifier] = nil
        if let error {
            fail(key: key, error: error)
        }
    }
}