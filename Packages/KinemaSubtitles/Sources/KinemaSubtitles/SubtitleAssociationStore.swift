import Foundation
import KinemaCore

public struct ManualSubtitleAssociation: Codable, Identifiable, Sendable, Hashable {
    public var id: String
    public var displayName: String
    public var path: String
    public var bookmarkData: Data?
    public var encodingID: String
    public var delay: Double

    public init(
        id: String = UUID().uuidString,
        displayName: String,
        path: String,
        bookmarkData: Data? = nil,
        encodingID: String = SubtitlePreferenceCatalog.defaultEncodingID,
        delay: Double = 0
    ) {
        self.id = id
        self.displayName = displayName
        self.path = path
        self.bookmarkData = bookmarkData
        self.encodingID = encodingID
        self.delay = delay
    }

    public var fileURL: URL {
        URL(fileURLWithPath: path)
    }
}

/// Remembers user-added (non-sidecar-auto) subtitle files per media.
@MainActor
public enum SubtitleAssociationStore {
    private static let fileName = "manual-subtitles.json"

    public static func associations(for mediaURL: URL) -> [ManualSubtitleAssociation] {
        let id = PlaybackHistoryEntry.mediaID(for: mediaURL)
        return loadAll()[id] ?? []
    }

    @discardableResult
    public static func add(
        for mediaURL: URL,
        subtitleURL: URL,
        encodingID: String
    ) -> ManualSubtitleAssociation? {
        // Sidecars are rediscovered via mpv sub-auto / local matching — don't pin them twice.
        if SubtitleFileMatcher.isAssociatedSidecar(subtitleURL, of: mediaURL) {
            return nil
        }

        let mediaID = PlaybackHistoryEntry.mediaID(for: mediaURL)
        var all = loadAll()
        var items = all[mediaID] ?? []

        let path = subtitleURL.path
        if let existing = items.firstIndex(where: { $0.path == path }) {
            items[existing].encodingID = encodingID
            items[existing].displayName = subtitleURL.lastPathComponent
            all[mediaID] = items
            save(all)
            return items[existing]
        }

        #if os(iOS) || os(tvOS)
        let bookmark = SecurityScopedBookmark.make(for: subtitleURL)
        #else
        let bookmark: Data? = nil
        #endif

        let item = ManualSubtitleAssociation(
            displayName: subtitleURL.lastPathComponent,
            path: path,
            bookmarkData: bookmark,
            encodingID: encodingID
        )
        items.append(item)
        all[mediaID] = items
        save(all)
        return item
    }

    /// Drops remembered entries that are already ordinary sidecars for this media.
    public static func pruneSidecarAssociations(for mediaURL: URL) {
        let mediaID = PlaybackHistoryEntry.mediaID(for: mediaURL)
        var all = loadAll()
        guard var items = all[mediaID], !items.isEmpty else { return }
        let before = items.count
        items.removeAll { SubtitleFileMatcher.isAssociatedSidecar($0.fileURL, of: mediaURL) }
        guard items.count != before else { return }
        if items.isEmpty {
            all.removeValue(forKey: mediaID)
        } else {
            all[mediaID] = items
        }
        save(all)
    }

    public static func updateDelay(for mediaURL: URL, associationID: String, delay: Double) {
        let mediaID = PlaybackHistoryEntry.mediaID(for: mediaURL)
        var all = loadAll()
        guard var items = all[mediaID],
              let index = items.firstIndex(where: { $0.id == associationID }) else { return }
        items[index].delay = delay
        all[mediaID] = items
        save(all)
    }

    public static func remove(for mediaURL: URL, associationID: String) {
        let mediaID = PlaybackHistoryEntry.mediaID(for: mediaURL)
        var all = loadAll()
        guard var items = all[mediaID] else { return }
        items.removeAll { $0.id == associationID }
        if items.isEmpty {
            all.removeValue(forKey: mediaID)
        } else {
            all[mediaID] = items
        }
        save(all)
    }

    public static func resolveURL(_ association: ManualSubtitleAssociation) -> URL? {
        #if os(iOS) || os(tvOS)
        if let data = association.bookmarkData, let url = SecurityScopedBookmark.resolve(data) {
            return url
        }
        #endif
        let url = association.fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    private static func storeURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("Kinema", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(fileName)
    }

    private static func loadAll() -> [String: [ManualSubtitleAssociation]] {
        let url = storeURL()
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: [ManualSubtitleAssociation]].self, from: data)) ?? [:]
    }

    private static func save(_ all: [String: [ManualSubtitleAssociation]]) {
        let url = storeURL()
        guard let data = try? JSONEncoder().encode(all) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
