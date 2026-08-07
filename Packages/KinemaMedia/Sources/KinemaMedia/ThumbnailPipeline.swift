import Foundation

/// Serializes thumbnail generation with limited parallelism so we never spin up
/// many ffmpeg/mpv decoders at once, while still keeping scroll responsive.
public actor ThumbnailPipeline {
    public static let shared = ThumbnailPipeline()

    public enum Priority: Int, Comparable, Sendable {
        case background = 0
        case visible = 1

        public static func < (lhs: Priority, rhs: Priority) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// Enough for grid scrolling without thrashing decoders on large libraries.
    private static let maxConcurrent = 2

    private var cached: [String: MediaPreview] = [:]
    private var waiters: [String: [CheckedContinuation<MediaPreview, Never>]] = [:]
    private var pending: [(key: String, url: URL, time: TimeInterval, priority: Priority)] = []
    private var activeKeys: Set<String> = []

    public func loadPreview(
        for url: URL,
        at time: TimeInterval,
        priority: Priority = .visible
    ) async -> MediaPreview {
        let key = Self.cacheKey(url: url, time: time)
        if let hit = cached[key] { return hit }

        return await withCheckedContinuation { continuation in
            waiters[key, default: []].append(continuation)

            if let index = pending.firstIndex(where: { $0.key == key }) {
                // Promote background work when a visible card asks for the same URL.
                if pending[index].priority < priority {
                    pending[index].priority = priority
                    pending.sort { $0.priority > $1.priority }
                }
            } else if !activeKeys.contains(key) {
                pending.append((key, url, time, priority))
                pending.sort { $0.priority > $1.priority }
            }

            drainQueue()
        }
    }

    private func drainQueue() {
        while activeKeys.count < Self.maxConcurrent, !pending.isEmpty {
            let job = pending.removeFirst()
            activeKeys.insert(job.key)

            Task.detached(priority: job.priority == .visible ? .userInitiated : .utility) { [job] in
                if Task.isCancelled {
                    await self.finish(
                        key: job.key,
                        preview: MediaPreview(duration: nil, width: nil, height: nil, image: nil)
                    )
                    return
                }

                let preview = MediaArtworkService.extractPreview(from: job.url, at: job.time)
                await self.finish(key: job.key, preview: preview)
            }
        }
    }

    private func finish(key: String, preview: MediaPreview) {
        if let image = preview.image, MediaFrameValidator.isAcceptable(image) {
            cached[key] = preview
        }
        activeKeys.remove(key)

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
