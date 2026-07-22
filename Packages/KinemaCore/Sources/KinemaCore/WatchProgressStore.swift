import Foundation

public struct WatchProgressEntry: Codable, Identifiable, Sendable {
    public var mediaID: String
    public var title: String
    public var urlString: String
    public var lastPosition: TimeInterval
    public var duration: TimeInterval
    public var lastPlayedAt: Date
    public var playCount: Int

    public var id: String { mediaID }

    public var url: URL? { URL(string: urlString) }

    public var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, lastPosition / duration))
    }

    public var isMostlyFinished: Bool {
        duration > 0 && lastPosition >= duration - 10
    }
}

@MainActor
public enum WatchProgressStore {
    private static let fileName = "watch-progress.json"

    public static func mediaID(for url: URL) -> String {
        PlaybackHistoryEntry.mediaID(for: url)
    }

    public static func recentEntries(limit: Int = 20) -> [WatchProgressEntry] {
        purgeUnstartedEntries()
        return loadAll()
            .filter { Self.belongsInContinue($0) }
            .sorted { $0.lastPlayedAt > $1.lastPlayedAt }
            .prefix(limit)
            .map { $0 }
    }

    /// True when we actually got playback (not a failed open / dead stream).
    public static func hasEstablishedPlayback(position: TimeInterval, duration: TimeInterval) -> Bool {
        duration > 0 || position > 1
    }

    private static func belongsInContinue(_ entry: WatchProgressEntry) -> Bool {
        guard let url = entry.url else { return false }
        guard hasEstablishedPlayback(position: entry.lastPosition, duration: entry.duration) else {
            return false
        }
        if url.isFileURL {
            return FileManager.default.fileExists(atPath: url.path)
        }
        return true
    }

    /// Drop stubs that never started — e.g. invalid stream links.
    private static func purgeUnstartedEntries() {
        var entries = loadAll()
        let originalCount = entries.count
        entries.removeAll { !hasEstablishedPlayback(position: $0.lastPosition, duration: $0.duration) }
        guard entries.count != originalCount else { return }
        save(entries)
    }

    public static func resumePosition(for url: URL) -> TimeInterval? {
        let id = mediaID(for: url)
        guard let entry = loadAll().first(where: { $0.mediaID == id }) else { return nil }
        guard entry.duration > 0, !entry.isMostlyFinished else { return nil }
        guard entry.lastPosition > 5 else { return nil }
        return entry.lastPosition
    }

    public static func entry(for url: URL) -> WatchProgressEntry? {
        let id = mediaID(for: url)
        return loadAll().first { $0.mediaID == id }
    }

    @discardableResult
    public static func record(
        item: MediaItem,
        position: TimeInterval,
        duration: TimeInterval
    ) -> WatchProgressEntry? {
        let established = hasEstablishedPlayback(position: position, duration: duration)
        var entries = loadAll()
        let id = mediaID(for: item.url)
        let now = Date()

        if let index = entries.firstIndex(where: { $0.mediaID == id }) {
            // Never overwrite a real Continue entry with a failed 0:0 open.
            guard established else { return entries[index] }

            entries[index].title = item.title
            entries[index].lastPosition = position
            entries[index].duration = max(duration, entries[index].duration)
            entries[index].lastPlayedAt = now
            entries[index].playCount += 1
            save(entries)
            EventBus.shared.emit(.watchProgressUpdated)
            return entries[index]
        }

        guard established else { return nil }

        let entry = WatchProgressEntry(
            mediaID: id,
            title: item.title,
            urlString: item.url.absoluteString,
            lastPosition: position,
            duration: duration,
            lastPlayedAt: now,
            playCount: 1
        )
        entries.append(entry)
        save(entries)
        EventBus.shared.emit(.watchProgressUpdated)
        return entry
    }

    public static func markWatched(item: MediaItem, duration: TimeInterval) {
        guard duration > 0 else { return }
        var entries = loadAll()
        let id = mediaID(for: item.url)
        let now = Date()

        if let index = entries.firstIndex(where: { $0.mediaID == id }) {
            entries[index].title = item.title
            entries[index].lastPosition = duration
            entries[index].duration = duration
            entries[index].lastPlayedAt = now
        } else {
            entries.append(WatchProgressEntry(
                mediaID: id,
                title: item.title,
                urlString: item.url.absoluteString,
                lastPosition: duration,
                duration: duration,
                lastPlayedAt: now,
                playCount: 0
            ))
        }
        save(entries)
        EventBus.shared.emit(.watchProgressUpdated)
    }

    public static func clearProgress(for url: URL) {
        let id = mediaID(for: url)
        var entries = loadAll()
        let originalCount = entries.count
        entries.removeAll { $0.mediaID == id }
        guard entries.count != originalCount else { return }
        save(entries)
        EventBus.shared.emit(.watchProgressUpdated)
    }

    /// True when every title has been watched (empty set → false).
    public static func areAllWatched(_ urls: [URL]) -> Bool {
        guard !urls.isEmpty else { return false }
        return urls.allSatisfy { entry(for: $0)?.isMostlyFinished == true }
    }

    /// Collect media files under a folder (recursive).
    public static func mediaURLs(under directory: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var urls: [URL] = []
        for case let url as URL in enumerator {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir { continue }
            if MediaFileTypes.isMediaFile(url) {
                urls.append(url)
            }
        }
        return urls
    }

    private static func storeURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("Kinema", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(fileName)
    }

    private static func loadAll() -> [WatchProgressEntry] {
        let url = storeURL()
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([WatchProgressEntry].self, from: data)) ?? []
    }

    private static func save(_ entries: [WatchProgressEntry]) {
        let url = storeURL()
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
