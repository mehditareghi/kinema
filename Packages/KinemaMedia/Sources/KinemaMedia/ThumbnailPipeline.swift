import Foundation

/// Serializes thumbnail generation so we never spin up many mpv/ffmpeg
/// decoders at once (which crashes on large libraries).
public actor ThumbnailPipeline {
    public static let shared = ThumbnailPipeline()

    private var cached: [String: MediaPreview] = [:]
    private var waiters: [String: [CheckedContinuation<MediaPreview, Never>]] = [:]
    private var pending: [(key: String, url: URL, time: TimeInterval)] = []
    private var activeKey: String?

    public func loadPreview(for url: URL, at time: TimeInterval) async -> MediaPreview {
        let key = Self.cacheKey(url: url, time: time)
        if let hit = cached[key] { return hit }

        return await withCheckedContinuation { continuation in
            waiters[key, default: []].append(continuation)
            if !pending.contains(where: { $0.key == key }) {
                pending.append((key, url, time))
            }
            drainQueue()
        }
    }

    private func drainQueue() {
        guard activeKey == nil, let job = pending.first else { return }
        pending.removeFirst()
        activeKey = job.key

        Task.detached(priority: .utility) { [job] in
            if Task.isCancelled {
                await self.finish(key: job.key, preview: MediaPreview(duration: nil, width: nil, height: nil, image: nil))
                return
            }

            let preview = MediaArtworkService.extractPreview(from: job.url, at: job.time)
            await self.finish(key: job.key, preview: preview)
        }
    }

    private func finish(key: String, preview: MediaPreview) {
        if let image = preview.image, MediaFrameValidator.isAcceptable(image) {
            cached[key] = preview
        }
        activeKey = nil

        let continuations = waiters.removeValue(forKey: key) ?? []
        for continuation in continuations {
            continuation.resume(returning: preview)
        }

        drainQueue()
    }

    private static func cacheKey(url: URL, time: TimeInterval) -> String {
        url.path
    }
}
