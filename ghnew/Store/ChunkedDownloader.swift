import Foundation

/// Downloads a single file in parallel byte-range chunks and stitches the parts
/// back together. Used by `DownloadManager` when the "并发" (concurrency) option
/// is on and the server supports range requests.
///
/// Concurrency is deliberately conservative so a burst of parallel range
/// requests does not trip GitHub/CDN rate limits: chunks are fed through a
/// bounded window that starts small, ramps up while the server stays happy and
/// shrinks (down to a single connection) on 429/403/503. Rate-limited chunks are
/// re-queued after `Retry-After` and a whole-download connection budget keeps N
/// simultaneous downloads from multiplying into N×level connections. All
/// callbacks fire on the main thread.
final class ChunkedDownloader: NSObject {
    /// (item key, progress 0...1)
    var onProgress: ((String, Double) -> Void)?
    /// (item key, final file URL on success, error on failure)
    var onFinish: ((String, URL?, Error?) -> Void)?

    /// Only bother chunking files larger than this.
    static let threshold: Int64 = 1_048_576   // 1 MB

    /// Absolute cap on simultaneous range connections across *every* active
    /// download, so several parallel downloads can't multiply into a flood.
    private static let globalConnectionLimit = 6
    /// Most transport/HTTP errors a single chunk may suffer before we give up.
    private static let maxAttempts = 4
    /// Most rate-limit responses a single chunk may hit before we give up.
    private static let maxRateLimitEvents = 12
    /// Longest single cool-down / Retry-After wait.
    private static let maxCoolDown: TimeInterval = 60
    /// After a rate-limit, ignore window ramping for this long to avoid flapping.
    private static let rampQuietPeriod: TimeInterval = 20
    /// The widest a job's window is ever allowed to become.
    private static let hardWindowCap = 8
    /// Connections a job opens with, before ramping toward its target.
    private static let initialWindow = 2

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 120
        config.httpMaximumConnectionsPerHost = ChunkedDownloader.hardWindowCap
        return URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }()

    private struct Chunk {
        let start: Int64
        let end: Int64
        var file: URL?
        var attempts: Int
        var rateLimitEvents: Int
    }

    private struct Job {
        let key: String
        let url: URL
        let token: String?
        let total: Int64
        let target: URL
        let partDir: URL
        var chunks: [Chunk]
        var pending: [Int]                              // ready to launch, in order
        var waiting: [(index: Int, readyAt: Date)]      // backing off / cooling down
        var running: Set<Int>
        var bytes: [Int64]
        var window: Int
        let maxWindow: Int
        var cooldownUntil: Date?
        var lastRateLimit: Date?
    }

    private var jobs: [String: Job] = [:]
    private var taskMap: [Int: (key: String, index: Int)] = [:]
    private var tasks: [Int: URLSessionTask] = [:]
    private var wakeItems: [String: DispatchWorkItem] = [:]
    private var activeConnections = 0

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

    /// Start downloading `url` into `target`, splitting it into `level` chunks
    /// fed through an adaptive window.
    func start(key: String, url: URL, token: String?, total: Int64, level: Int, target: URL) {
        let count = max(2, min(level, Self.hardWindowCap))
        let partSize = max(1, (total + Int64(count) - 1) / Int64(count))
        var chunks: [Chunk] = []
        var start: Int64 = 0
        while start < total {
            let end = min(start + partSize - 1, total - 1)
            chunks.append(Chunk(start: start, end: end, file: nil,
                                attempts: 0, rateLimitEvents: 0))
            start = end + 1
        }

        let partDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghnew-parts-\(key.replacingOccurrences(of: "/", with: "_"))",
                                    isDirectory: true)
        try? FileManager.default.removeItem(at: partDir)
        try? FileManager.default.createDirectory(at: partDir, withIntermediateDirectories: true)

        let maxWindow = max(2, min(level, Self.hardWindowCap))
        jobs[key] = Job(key: key, url: url, token: token, total: total, target: target,
                        partDir: partDir, chunks: chunks,
                        pending: Array(chunks.indices), waiting: [], running: [],
                        bytes: Array(repeating: 0, count: chunks.count),
                        window: min(maxWindow, Self.initialWindow), maxWindow: maxWindow,
                        cooldownUntil: nil, lastRateLimit: nil)
        pump(key: key)
    }

    // MARK: - Scheduling

    /// Feed as many chunks as the job window and the global budget allow.
    private func pump(key: String) {
        guard var job = jobs[key] else { return }

        let now = Date()
        if let until = job.cooldownUntil {
            if now < until {
                jobs[key] = job
                scheduleWake(key: key, after: until.timeIntervalSinceNow + 0.05)
                return
            }
            job.cooldownUntil = nil
        }

        // Promote chunks whose back-off / cool-down has elapsed.
        var stillWaiting: [(index: Int, readyAt: Date)] = []
        var nextWake: TimeInterval?
        for entry in job.waiting {
            if entry.readyAt <= now {
                job.pending.append(entry.index)
            } else {
                stillWaiting.append(entry)
                let delta = entry.readyAt.timeIntervalSinceNow
                nextWake = min(nextWake ?? .greatestFiniteMagnitude, delta)
            }
        }
        job.waiting = stillWaiting

        while activeConnections < Self.globalConnectionLimit,
              job.running.count < job.window,
              let index = job.pending.first {
            job.pending.removeFirst()
            job.running.insert(index)
            activeConnections += 1
            launch(key: key, job: job, index: index)
        }
        jobs[key] = job

        if let nextWake { scheduleWake(key: key, after: nextWake + 0.05) }
        maybeFinish(key: key)
    }

    private func launch(key: String, job: Job, index: Int) {
        let chunk = job.chunks[index]
        var req = URLRequest(url: job.url)
        req.setValue("bytes=\(chunk.start)-\(chunk.end)", forHTTPHeaderField: "Range")
        req.setValue("ghnew/1.0", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 120
        if let token = job.token, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        }
        let task = session.downloadTask(with: req)
        taskMap[task.taskIdentifier] = (key, index)
        tasks[task.taskIdentifier] = task
        task.resume()
    }

    private func scheduleWake(key: String, after delay: TimeInterval) {
        guard delay > 0 else { return }
        wakeItems[key]?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.wakeItems[key] = nil
            self?.pump(key: key)
        }
        wakeItems[key] = item
        let capped = min(max(delay, 0.05), Self.maxCoolDown + 5)
        DispatchQueue.main.asyncAfter(deadline: .now() + capped, execute: item)
    }

    /// Put a chunk back in line after a back-off, or fail the job once it has
    /// burned through its attempts.
    private func retryChunk(key: String, index: Int, delay: TimeInterval) {
        guard var job = jobs[key], index < job.chunks.count else { return }
        job.chunks[index].attempts += 1
        if job.chunks[index].attempts > Self.maxAttempts {
            jobs[key] = job
            fail(key: key, error: nil, message: "A chunk kept failing and the download was aborted.")
            return
        }
        job.waiting.append((index, Date().addingTimeInterval(max(0, delay))))
        jobs[key] = job
        pump(key: key)
    }

    /// React to a 429/403/503: shrink the window, remember the cool-down and
    /// re-queue the chunk for after it.
    private func handleRateLimit(key: String, index: Int, response: HTTPURLResponse?) {
        guard var job = jobs[key], index < job.chunks.count else { return }
        job.chunks[index].rateLimitEvents += 1
        if job.chunks[index].rateLimitEvents > Self.maxRateLimitEvents {
            jobs[key] = job
            fail(key: key, error: nil, message: "The server kept rate-limiting this download.")
            return
        }
        let delay = rateLimitDelay(response)
        job.window = max(1, job.window / 2)
        job.lastRateLimit = Date()
        job.cooldownUntil = Date().addingTimeInterval(delay)
        if !job.waiting.contains(where: { $0.index == index }) {
            job.waiting.append((index, Date().addingTimeInterval(delay)))
        }
        jobs[key] = job
        pump(key: key)
    }

    /// Widen the window by one after a success, but only once the server has
    /// been quiet for a while — otherwise a rate-limited host would oscillate.
    private func rampWindow(key: String) {
        guard var job = jobs[key] else { return }
        if let last = job.lastRateLimit, Date().timeIntervalSince(last) < Self.rampQuietPeriod {
            jobs[key] = job
            return
        }
        if job.window < job.maxWindow { job.window += 1 }
        jobs[key] = job
    }

    private func rateLimitDelay(_ response: HTTPURLResponse?) -> TimeInterval {
        guard let response else { return 5 }
        if let raw = response.value(forHTTPHeaderField: "Retry-After") {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if let seconds = Double(trimmed), seconds >= 0 {
                return min(Self.maxCoolDown, max(1, seconds))
            }
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "en_US_POSIX")
            fmt.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            if let date = fmt.date(from: trimmed) {
                return min(Self.maxCoolDown, max(1, date.timeIntervalSinceNow))
            }
        }
        if let raw = response.value(forHTTPHeaderField: "X-RateLimit-Reset"),
           let epoch = Double(raw.trimmingCharacters(in: .whitespaces)) {
            let seconds = Date(timeIntervalSince1970: epoch).timeIntervalSinceNow
            if seconds > 0 { return min(Self.maxCoolDown, seconds) }
        }
        return 5
    }

    private func isRateLimited(status: Int, headers: HTTPURLResponse?) -> Bool {
        guard status == 403 else { return false }
        if headers?.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0" { return true }
        return headers?.value(forHTTPHeaderField: "Retry-After") != nil
    }

    private func backoff(attempts: Int) -> TimeInterval {
        let base = 0.8 * pow(2.0, Double(max(0, attempts)))
        return min(15, base + Double.random(in: 0...0.4))
    }

    // MARK: - Completion

    private func maybeFinish(key: String) {
        guard let job = jobs[key] else { return }
        guard job.pending.isEmpty, job.running.isEmpty, job.waiting.isEmpty else { return }
        finish(job)
    }

    private func finish(_ job: Job) {
        do {
            _ = FileManager.default.createFile(atPath: job.target.path, contents: nil)
            let out = try FileHandle(forWritingTo: job.target)
            defer { try? out.close() }
            for chunk in job.chunks {
                guard let part = chunk.file else { continue }
                let input = try FileHandle(forReadingFrom: part)
                defer { try? input.close() }
                while true {
                    let data = try input.read(upToCount: 1 << 20) ?? Data()
                    if data.isEmpty { break }
                    try out.write(contentsOf: data)
                }
            }
            try? FileManager.default.removeItem(at: job.partDir)
            wakeItems[job.key]?.cancel()
            wakeItems[job.key] = nil
            jobs[job.key] = nil
            onFinish?(job.key, job.target, nil)
        } catch {
            fail(key: job.key, error: error)
        }
    }

    private func fail(key: String, error: Error?, message: String? = nil) {
        guard let job = jobs[key] else { return }
        wakeItems[key]?.cancel()
        wakeItems[key] = nil
        for (id, info) in taskMap where info.key == key {
            tasks[id]?.cancel()
            tasks[id] = nil
            taskMap[id] = nil
            activeConnections = max(0, activeConnections - 1)
        }
        try? FileManager.default.removeItem(at: job.target)
        try? FileManager.default.removeItem(at: job.partDir)
        jobs[key] = nil
        let err = error ?? NSError(domain: "ghnew.ChunkedDownloader", code: -1,
                                   userInfo: [NSLocalizedDescriptionKey: message ?? "Download failed."])
        onFinish?(key, nil, err)
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
        guard let (key, index) = taskMap[downloadTask.taskIdentifier] else { return }
        taskMap[downloadTask.taskIdentifier] = nil
        tasks[downloadTask.taskIdentifier] = nil
        activeConnections = max(0, activeConnections - 1)

        guard var job = jobs[key], index < job.chunks.count else { return }
        job.running.remove(index)

        // URLSession treats 4xx/5xx as a normal body, so a rate-limited or error
        // response still lands here — never trust the payload without the status.
        let http = downloadTask.response as? HTTPURLResponse
        let status = http?.statusCode ?? 0

        if status == 429 || status == 503 || isRateLimited(status: status, headers: http) {
            jobs[key] = job
            handleRateLimit(key: key, index: index, response: http)
            return
        }
        guard status == 206 else {
            jobs[key] = job
            let retryable = status >= 500 || status == 408 || status == 0
            retryChunk(key: key, index: index,
                       delay: retryable ? backoff(attempts: job.chunks[index].attempts) : 0.5)
            return
        }

        let chunk = job.chunks[index]
        let expected = chunk.end - chunk.start + 1
        let actual = (try? FileManager.default.attributesOfItem(atPath: location.path))?[.size] as? Int64 ?? 0
        guard actual == expected else {
            // A truncated or oversized body (e.g. an error page) means corruption.
            jobs[key] = job
            retryChunk(key: key, index: index, delay: backoff(attempts: chunk.attempts))
            return
        }

        let partURL = job.partDir.appendingPathComponent("part-\(index)")
        try? FileManager.default.removeItem(at: partURL)
        do {
            try FileManager.default.moveItem(at: location, to: partURL)
        } catch {
            jobs[key] = job
            retryChunk(key: key, index: index, delay: backoff(attempts: chunk.attempts))
            return
        }
        job.chunks[index].file = partURL
        job.bytes[index] = expected
        jobs[key] = job

        rampWindow(key: key)
        pump(key: key)
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        guard let (key, index) = taskMap[task.taskIdentifier] else { return }
        taskMap[task.taskIdentifier] = nil
        tasks[task.taskIdentifier] = nil
        activeConnections = max(0, activeConnections - 1)

        guard var job = jobs[key], index < job.chunks.count else { return }
        job.running.remove(index)
        jobs[key] = job

        if error != nil {
            // Transport-level failure (timeout, connection reset): re-queue.
            retryChunk(key: key, index: index, delay: backoff(attempts: job.chunks[index].attempts))
        } else {
            pump(key: key)
        }
    }
}