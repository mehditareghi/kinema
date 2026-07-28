import Foundation
import SwiftData

@Model
public final class PlaybackHistoryEntry {
    @Attribute(.unique) public var mediaID: String
    public var title: String
    public var urlString: String
    public var lastPosition: TimeInterval
    public var duration: TimeInterval
    public var lastPlayedAt: Date
    public var playCount: Int

    public init(
        mediaID: String,
        title: String,
        urlString: String,
        lastPosition: TimeInterval = 0,
        duration: TimeInterval = 0,
        lastPlayedAt: Date = .now,
        playCount: Int = 1
    ) {
        self.mediaID = mediaID
        self.title = title
        self.urlString = urlString
        self.lastPosition = lastPosition
        self.duration = duration
        self.lastPlayedAt = lastPlayedAt
        self.playCount = playCount
    }

    public var url: URL? { URL(string: urlString) }

    /// Stable id that survives Xcode reinstalls (app container UUID changes).
    /// In-container files use `container:/Documents/...`; external files keep a normalized path.
    public static func mediaID(for url: URL) -> String {
        if url.isFileURL {
            return stableFileMediaID(path: url.standardizedFileURL.path)
        }
        return url.absoluteString
    }

    public static func stableFileMediaID(path rawPath: String) -> String {
        let path = strippingPrivatePrefix(rawPath)
        let home = strippingPrivatePrefix(NSHomeDirectory())

        if path == home {
            return "container:/"
        }
        if path.hasPrefix(home + "/") {
            let relative = String(path.dropFirst(home.count)) // begins with "/"
            return "container:" + relative
        }

        // Legacy absolute paths written before this fix — strip the random container UUID.
        if let relative = relativePathByStrippingContainerUUID(path) {
            return "container:" + relative
        }

        return path
    }

    /// Rebuild a usable file URL after the app container UUID changed.
    public static func recoverFileURL(fromStoredPathOrURL value: String) -> URL? {
        let path: String
        if value.hasPrefix("container:") {
            let relative = String(value.dropFirst("container:".count))
            path = strippingPrivatePrefix(NSHomeDirectory()) + (relative.hasPrefix("/") ? relative : "/" + relative)
        } else if let url = URL(string: value), url.isFileURL {
            path = strippingPrivatePrefix(url.standardizedFileURL.path)
        } else if value.hasPrefix("/") {
            path = strippingPrivatePrefix(value)
        } else {
            return nil
        }

        if FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        guard let relative = relativePathByStrippingContainerUUID(path) else { return nil }
        let candidate = strippingPrivatePrefix(NSHomeDirectory()) + relative
        guard FileManager.default.fileExists(atPath: candidate) else { return nil }
        return URL(fileURLWithPath: candidate)
    }

    private static func strippingPrivatePrefix(_ path: String) -> String {
        if path.hasPrefix("/private/") {
            return String(path.dropFirst("/private".count))
        }
        return path
    }

    /// `/var/.../Application/<UUID>/Documents/foo` → `/Documents/foo`
    private static func relativePathByStrippingContainerUUID(_ path: String) -> String? {
        let markers = ["/Documents/", "/Library/", "/tmp/", "/tmp"]
        for marker in markers {
            if let range = path.range(of: marker) {
                return String(path[range.lowerBound...])
            }
        }
        return nil
    }
}

@Model
public final class PlaylistEntity {
    public var name: String
    public var createdAt: Date
    @Relationship(deleteRule: .cascade) public var items: [PlaylistItemEntity]

    public init(name: String, createdAt: Date = .now, items: [PlaylistItemEntity] = []) {
        self.name = name
        self.createdAt = createdAt
        self.items = items
    }
}

@Model
public final class PlaylistItemEntity {
    public var title: String
    public var urlString: String
    public var sortOrder: Int

    public init(title: String, urlString: String, sortOrder: Int) {
        self.title = title
        self.urlString = urlString
        self.sortOrder = sortOrder
    }

    public var url: URL? { URL(string: urlString) }

    public var mediaItem: MediaItem? {
        guard let url else { return nil }
        return MediaItem(url: url, title: title)
    }
}

@MainActor
public enum HistoryStore {
    public static let schema = Schema([PlaybackHistoryEntry.self, PlaylistEntity.self, PlaylistItemEntity.self])
    private static let storeName = "Kinema"
    private static let schemaVersion = 3
    private static let schemaVersionKey = "io.kinema.swiftdata.schemaVersion"

    public static func container(inMemory: Bool = false) throws -> ModelContainer {
        if !inMemory {
            migrateStoreIfNeeded()
        }
        let config = ModelConfiguration(storeName, schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private static func migrateStoreIfNeeded() {
        let defaults = UserDefaults.standard
        let installed = defaults.integer(forKey: schemaVersionKey)
        guard installed < schemaVersion else { return }

        removeAllPersistedStores()
        defaults.set(schemaVersion, forKey: schemaVersionKey)
        NSLog("Kinema: reset SwiftData store for schema v%d", schemaVersion)
    }

    private static func removeAllPersistedStores() {
        let config = ModelConfiguration(storeName, schema: schema, isStoredInMemoryOnly: false)
        removeStoreFiles(for: config)

        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
              let files = try? FileManager.default.contentsOfDirectory(at: appSupport, includingPropertiesForKeys: nil)
        else { return }

        for file in files where file.lastPathComponent.contains(".store") {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private static func removeStoreFiles(for config: ModelConfiguration) {
        let storeURL = config.url
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + suffix))
        }
    }

    public static func recordPlayback(
        context: ModelContext,
        item: MediaItem,
        position: TimeInterval,
        duration: TimeInterval
    ) {
        #if os(iOS) || os(tvOS)
        // SwiftData fetch is disabled on iOS playback path until store stability is verified.
        return
        #else
        if let existing = entry(for: item.url, in: context) {
            existing.title = item.title
            existing.lastPosition = position
            existing.duration = duration
            existing.lastPlayedAt = .now
            existing.playCount += 1
        } else {
            let entry = PlaybackHistoryEntry(
                mediaID: PlaybackHistoryEntry.mediaID(for: item.url),
                title: item.title,
                urlString: item.url.absoluteString,
                lastPosition: position,
                duration: duration
            )
            context.insert(entry)
        }
        try? context.save()
        #endif
    }

    public static func resumePosition(context: ModelContext, for url: URL) -> TimeInterval? {
        #if os(iOS) || os(tvOS)
        return nil
        #else
        guard let entry = entry(for: url, in: context) else { return nil }
        guard entry.duration > 0, entry.lastPosition < entry.duration - 10 else { return nil }
        return entry.lastPosition
        #endif
    }

    private static func entry(for url: URL, in context: ModelContext) -> PlaybackHistoryEntry? {
        let targetID = PlaybackHistoryEntry.mediaID(for: url)
        let descriptor = FetchDescriptor<PlaybackHistoryEntry>()
        guard let entries = try? context.fetch(descriptor) else { return nil }
        return entries.first { $0.mediaID == targetID }
    }
}
