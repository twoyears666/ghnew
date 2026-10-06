import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Tracks a single artifact/asset download with live progress.
final class DownloadItem: Identifiable, ObservableObject {
    let id: String          // "<kind>-<repoKey>-<assetId>"
    let name: String
    let size: Int64?
    let url: URL
    let needsAuth: Bool

    @Published var state: State = .idle
    @Published var progress: Double = 0
    var fileURL: URL?

    enum State: Equatable {
        case idle
        case downloading
        case done
        case failed(String)
        case authRequired
    }

    var progressText: String {
        guard state == .downloading else { return "" }
        return "\(Int(progress * 100))%"
    }

    init(id: String, name: String, size: Int64?, url: URL, needsAuth: Bool) {
        self.id = id
        self.name = name
        self.size = size
        self.url = url
        self.needsAuth = needsAuth
    }
}

/// Central download manager. Its URLSession is configured with a main-actor
/// delegate queue, so progress mutations happen on the main thread. Items are
/// keyed by `"<kind>-<repoKey>-<assetId>"`.
final class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()

    @Published private(set) var items: [String: DownloadItem] = [:]

    private var session: URLSession!
    private var taskKeys: [Int: String] = [:]   // URLSessionTask.identifier -> item id

    private let api = GitHubAPI.shared
    private let chunked = ChunkedDownloader()

    override init() {
        super.init()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 120
        session = URLSession(configuration: config, delegate: self, delegateQueue: .main)

        chunked.onProgress = { [weak self] key, progress in
            self?.items[key]?.progress = progress
        }
        chunked.onFinish = { [weak self] key, url, error in
            guard let self, let item = self.items[key] else { return }
            if let url {
                item.state = .done
                item.progress = 1
                item.fileURL = url
                #if canImport(UIKit)
                self.reveal(item)
                #endif
            } else {
                item.state = .failed(error?.localizedDescription ?? "Download failed.")
            }
        }
    }

    func item(for key: String) -> DownloadItem? { items[key] }

    /// Start a download. If `needsAuth` is true but no token is set, the item is
    /// marked `.authRequired` and nothing is downloaded (caller shows a login hint).
    func download(key: String, name: String, size: Int64?, url: URL, needsAuth: Bool) {
        var token: String?
        if needsAuth {
            guard let t = api.token, !t.isEmpty else {
                let item = DownloadItem(id: key, name: name, size: size, url: url, needsAuth: needsAuth)
                item.state = .authRequired
                items[key] = item
                return
            }
            token = t
        }

        let isArtifact = key.hasPrefix("act-")
        let settings = AppSettings.shared

        // 中转: route the request through the selected mirror node.
        var effective = url
        if settings.accelRelayEnabled, !isArtifact || settings.accelRelayIncludeArtifacts,
           let rewritten = Accelerator.rewrite(url, host: settings.accelRelayNode) {
            effective = rewritten
        }

        // 并发: multi-connection byte-range download.
        if settings.accelConcurrencyEnabled, !isArtifact || settings.accelConcurrencyIncludeArtifacts {
            startChunked(key: key, name: name, size: size, url: effective, token: token)
        } else {
            start(key: key, name: name, size: size, url: effective, token: token)
        }
    }

    /// Re-run a previously failed download.
    func startRetry(_ item: DownloadItem) {
        download(key: item.id, name: item.name, size: item.size, url: item.url, needsAuth: item.needsAuth)
    }

    private func start(key: String, name: String, size: Int64?, url: URL, token: String?) {
        var req = URLRequest(url: url)
        req.setValue("ghnew/1.0", forHTTPHeaderField: "User-Agent")
        if let token, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        }
        let item = DownloadItem(id: key, name: name, size: size, url: url, needsAuth: token != nil)
        item.state = .downloading
        items[key] = item
        let task = session.downloadTask(with: req)
        taskKeys[task.taskIdentifier] = key
        task.resume()
    }

    /// Probe the effective URL, then start a chunked download — falling back to a
    /// plain single-thread download when the file is small or ranges are unsupported.
    private func startChunked(key: String, name: String, size: Int64?, url: URL, token: String?) {
        let level = max(2, min(8, AppSettings.shared.accelConcurrencyLevel))
        Task { [weak self] in
            guard let self else { return }
            let total = await self.chunked.probeTotal(url: url, token: token)
            DispatchQueue.main.async {
                guard let total, total > ChunkedDownloader.threshold else {
                    self.start(key: key, name: name, size: size, url: url, token: token)
                    return
                }
                let dir = Persistence.documentsDirectory.appendingPathComponent("Downloads")
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let target = DownloadManager.uniqueURL(
                    in: dir, fileName: DownloadManager.desiredFileName(key: key, name: name))
                let item = DownloadItem(id: key, name: name, size: total, url: url, needsAuth: token != nil)
                item.state = .downloading
                self.items[key] = item
                self.chunked.start(key: key, url: url, token: token,
                                   total: total, level: level, target: target)
            }
        }
    }

    /// Final on-disk name. Actions artifacts are zip archives whose GitHub name
    /// carries no extension, so add one.
    private static func desiredFileName(key: String, name: String) -> String {
        let safeName = name.replacingOccurrences(of: "/", with: "_")
        if key.hasPrefix("act-"), (safeName as NSString).pathExtension.isEmpty {
            return safeName + ".zip"
        }
        return safeName
    }

    /// Never clobber an existing file: append " (n)" until the name is free.
    private static func uniqueURL(in dir: URL, fileName: String) -> URL {
        var target = dir.appendingPathComponent(fileName)
        var counter = 1
        while FileManager.default.fileExists(atPath: target.path) {
            let ext = target.pathExtension
            let base = (target.lastPathComponent as NSString).deletingPathExtension
            let newName = "\(base) (\(counter))" + (ext.isEmpty ? "" : ".\(ext)")
            target = dir.appendingPathComponent(newName)
            counter += 1
        }
        return target
    }

    /// Present the downloaded file for saving / sharing via the Files app.
    ///
    /// Safe to call from the download delegate the instant a transfer finishes:
    /// the presentation is deferred to the next runloop turn (never inside the
    /// URLSession callback), and on iPad the activity controller gets a popover
    /// anchor — presenting it without one raises an exception and crashes.
    func reveal(_ item: DownloadItem) {
        guard let url = item.fileURL else { return }
        #if canImport(UIKit)
        DispatchQueue.main.async {
            guard let scene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first(where: { $0.activationState == .foregroundActive }),
                  let window = scene.windows.first(where: { $0.isKeyWindow }),
                  let presenter = DownloadManager.topmostPresentable(window.rootViewController)
            else { return }
            let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            // iPad presents this modally as a popover; it must have an anchor.
            if let popover = activity.popoverPresentationController {
                popover.sourceView = presenter.view
                popover.sourceRect = CGRect(x: presenter.view.bounds.midX,
                                            y: presenter.view.bounds.midY,
                                            width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            presenter.present(activity, animated: true)
        }
        #else
        NSWorkspace.shared.activateFileViewerSelecting([url])
        #endif
    }

    #if canImport(UIKit)
    /// Walk to the deepest presented controller and only return it if its view is
    /// actually on screen, so we never present on a detached controller.
    private static func topmostPresentable(_ root: UIViewController?) -> UIViewController? {
        guard var current = root else { return nil }
        while let presented = current.presentedViewController { current = presented }
        return current.viewIfLoaded?.window != nil ? current : nil
    }
    #endif

    static func bytesString(_ bytes: Int64?) -> String {
        guard let bytes, bytes >= 0 else { return "" }
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.0f KB", kb) }
        let mb = kb / 1024
        if mb < 1024 { return String(format: "%.1f MB", mb) }
        return String(format: "%.2f GB", mb / 1024)
    }
}

extension DownloadManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard let key = taskKeys[downloadTask.taskIdentifier], let item = items[key] else { return }
        let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : 1
        item.progress = min(max(Double(totalBytesWritten) / Double(expected), 0), 1)
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let key = taskKeys[downloadTask.taskIdentifier] else { return }
        guard let item = items[key] else { return }
        let dir = Persistence.documentsDirectory.appendingPathComponent("Downloads")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let target = DownloadManager.uniqueURL(
            in: dir, fileName: DownloadManager.desiredFileName(key: key, name: item.name))
        do {
            try FileManager.default.moveItem(at: location, to: target)
            item.state = .done
            item.progress = 1
            item.fileURL = target
            #if canImport(UIKit)
            // On iOS, once a download finishes, present the Apple share sheet
            // immediately so the user can save / AirDrop the file.
            reveal(item)
            #endif
        } catch {
            item.state = .failed(error.localizedDescription)
        }
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        guard let key = taskKeys[task.taskIdentifier], let item = items[key] else { return }
        taskKeys[task.taskIdentifier] = nil
        if item.state != .done, let error {
            item.state = .failed(error.localizedDescription)
        }
    }
}