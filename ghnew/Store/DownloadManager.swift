import Foundation
import UIKit
import SwiftUI

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

    override init() {
        super.init()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 120
        session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }

    func item(for key: String) -> DownloadItem? { items[key] }

    /// Start a download. If `needsAuth` is true but no token is set, the item is
    /// marked `.authRequired` and nothing is downloaded (caller shows a login hint).
    func download(key: String, name: String, size: Int64?, url: URL, needsAuth: Bool) {
        if needsAuth {
            guard let token = api.token, !token.isEmpty else {
                let item = DownloadItem(id: key, name: name, size: size, url: url, needsAuth: needsAuth)
                item.state = .authRequired
                items[key] = item
                return
            }
            start(key: key, name: name, size: size, url: url, token: token)
            return
        }
        start(key: key, name: name, size: size, url: url, token: nil)
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

    /// Present the downloaded file for saving / sharing via the Files app.
    func reveal(_ item: DownloadItem) {
        guard let url = item.fileURL else { return }
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
            root.present(activity, animated: true)
        }
    }

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
        let safeName = item.name.replacingOccurrences(of: "/", with: "_")
        var target = dir.appendingPathComponent(safeName)
        var counter = 1
        while FileManager.default.fileExists(atPath: target.path) {
            let ext = target.pathExtension
            let base = (target.lastPathComponent as NSString).deletingPathExtension
            let newName = "\(base) (\(counter))" + (ext.isEmpty ? "" : ".\(ext)")
            target = dir.appendingPathComponent(newName)
            counter += 1
        }
        do {
            try FileManager.default.moveItem(at: location, to: target)
            item.state = .done
            item.progress = 1
            item.fileURL = target
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