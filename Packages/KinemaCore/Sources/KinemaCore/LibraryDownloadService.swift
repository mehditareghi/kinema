import Foundation
import KinemaCore

public struct LibraryDownloadItem: Identifiable, Sendable {
    public let id: UUID
    public let sourceURL: URL
    public let destinationURL: URL
    public var progress: Double
    public var isFinished: Bool
    public var errorMessage: String?

    public init(
        id: UUID = UUID(),
        sourceURL: URL,
        destinationURL: URL,
        progress: Double = 0,
        isFinished: Bool = false,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
        self.progress = progress
        self.isFinished = isFinished
        self.errorMessage = errorMessage
    }
}

/// Downloads HTTP/FTP media into the built-in library (or a chosen folder).
@MainActor
public final class LibraryDownloadService: NSObject {
    public static let shared = LibraryDownloadService()

    public private(set) var items: [LibraryDownloadItem] = [] {
        didSet { NotificationCenter.default.post(name: .kinemaDownloadsChanged, object: nil) }
    }

    private var tasks: [UUID: URLSessionDownloadTask] = [:]
    private var session: URLSession!

    private override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.allowsCellularAccess = true
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    @discardableResult
    public func enqueue(url: URL, destinationDirectory: URL? = nil) -> UUID {
        let directory = destinationDirectory ?? LibraryMediaPaths.ensureBuiltInDirectory()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileName = url.lastPathComponent.isEmpty ? "download-\(UUID().uuidString)" : url.lastPathComponent
        let safeName = (fileName as NSString).lastPathComponent
        let destination = uniqueDestination(in: directory, fileName: safeName)

        let item = LibraryDownloadItem(sourceURL: url, destinationURL: destination)
        items.insert(item, at: 0)

        let task = session.downloadTask(with: url)
        task.taskDescription = item.id.uuidString
        tasks[item.id] = task
        task.resume()
        return item.id
    }

    public func cancel(_ id: UUID) {
        tasks[id]?.cancel()
        tasks.removeValue(forKey: id)
        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index].errorMessage = "Cancelled"
            items[index].isFinished = true
        }
    }

    private func uniqueDestination(in directory: URL, fileName: String) -> URL {
        var destination = directory.appendingPathComponent(fileName)
        if !FileManager.default.fileExists(atPath: destination.path) {
            return destination
        }
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var index = 1
        repeat {
            let candidate = ext.isEmpty ? "\(base)-\(index)" : "\(base)-\(index).\(ext)"
            destination = directory.appendingPathComponent(candidate)
            index += 1
        } while FileManager.default.fileExists(atPath: destination.path)
        return destination
    }

    private func update(id: UUID, mutate: (inout LibraryDownloadItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        mutate(&items[index])
    }
}

public extension Notification.Name {
    static let kinemaDownloadsChanged = Notification.Name("io.kinema.downloadsChanged")
}

extension LibraryDownloadService: URLSessionDownloadDelegate {
    public nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let idString = downloadTask.taskDescription ?? ""
        guard let id = UUID(uuidString: idString) else { return }

        // Copy out of temp location before the delegate returns.
        let tempCopy = FileManager.default.temporaryDirectory
            .appendingPathComponent("kinema-dl-\(id.uuidString)")
        try? FileManager.default.removeItem(at: tempCopy)
        try? FileManager.default.copyItem(at: location, to: tempCopy)

        Task { @MainActor in
            guard let index = self.items.firstIndex(where: { $0.id == id }) else {
                try? FileManager.default.removeItem(at: tempCopy)
                return
            }
            let destination = self.items[index].destinationURL
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: tempCopy, to: destination)
                self.items[index].progress = 1
                self.items[index].isFinished = true
                self.tasks.removeValue(forKey: id)
                EventBus.shared.emit(.libraryChanged)
                #if os(iOS) || os(macOS)
                LibrarySpotlightIndexer.shared.indexBuiltInLibrary()
                #endif
            } catch {
                try? FileManager.default.removeItem(at: tempCopy)
                self.items[index].errorMessage = error.localizedDescription
                self.items[index].isFinished = true
                self.tasks.removeValue(forKey: id)
            }
        }
    }

    public nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let idString = downloadTask.taskDescription ?? ""
        guard let id = UUID(uuidString: idString) else { return }
        let progress: Double
        if totalBytesExpectedToWrite > 0 {
            progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        } else {
            progress = 0
        }
        Task { @MainActor in
            self.update(id: id) { $0.progress = min(max(progress, 0), 1) }
        }
    }

    public nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }
        let idString = task.taskDescription ?? ""
        guard let id = UUID(uuidString: idString) else { return }
        Task { @MainActor in
            self.update(id: id) {
                $0.errorMessage = error.localizedDescription
                $0.isFinished = true
            }
            self.tasks.removeValue(forKey: id)
        }
    }
}
