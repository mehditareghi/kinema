import Foundation
import KinemaCore

/// Full subtitle layout + selection remembered per media title.
public struct SubtitleSessionState: Codable, Sendable, Equatable {
    public var primaryKey: String?
    public var secondaryKey: String?
    public var primaryAlignX: String
    public var primaryAlignY: String
    public var primaryPos: Int
    public var secondaryAlignX: String
    public var secondaryPos: Int
    public var primaryDelay: Double
    public var secondaryDelay: Double
    public var audioDelay: Double
    public var syncTarget: String
    public var usingBakedLayout: Bool

    public init(
        primaryKey: String? = nil,
        secondaryKey: String? = nil,
        primaryAlignX: String = SubtitleHorizontalAlign.center.rawValue,
        primaryAlignY: String = SubtitleVerticalAlign.bottom.rawValue,
        primaryPos: Int = 100,
        secondaryAlignX: String = SubtitleHorizontalAlign.center.rawValue,
        secondaryPos: Int = 10,
        primaryDelay: Double = 0,
        secondaryDelay: Double = 0,
        audioDelay: Double = 0,
        syncTarget: String = SubtitleSyncTarget.primary.rawValue,
        usingBakedLayout: Bool = false
    ) {
        self.primaryKey = primaryKey
        self.secondaryKey = secondaryKey
        self.primaryAlignX = primaryAlignX
        self.primaryAlignY = primaryAlignY
        self.primaryPos = primaryPos
        self.secondaryAlignX = secondaryAlignX
        self.secondaryPos = secondaryPos
        self.primaryDelay = primaryDelay
        self.secondaryDelay = secondaryDelay
        self.audioDelay = audioDelay
        self.syncTarget = syncTarget
        self.usingBakedLayout = usingBakedLayout
    }
}

@MainActor
public enum SubtitleSessionStore {
    private static let fileName = "subtitle-sessions.json"

    public static func load(for mediaURL: URL) -> SubtitleSessionState? {
        let id = PlaybackHistoryEntry.mediaID(for: mediaURL)
        return loadAll()[id]
    }

    public static func save(_ state: SubtitleSessionState, for mediaURL: URL) {
        let id = PlaybackHistoryEntry.mediaID(for: mediaURL)
        var all = loadAll()
        all[id] = state
        persist(all)
    }

    public static func clear(for mediaURL: URL) {
        let id = PlaybackHistoryEntry.mediaID(for: mediaURL)
        var all = loadAll()
        all.removeValue(forKey: id)
        persist(all)
    }

    /// Stable identity for a track across reopen (embedded or external).
    public static func trackKey(for track: Track, sourceURL: URL?) -> String {
        if track.isExternal, let sourceURL {
            return "external:\(sourceURL.path)"
        }
        if let sourceURL, track.isExternal {
            return "external:\(sourceURL.path)"
        }
        let lang = track.language ?? ""
        let title = track.title
        let codec = track.codec ?? ""
        let ff = track.ffIndex.map(String.init) ?? "\(track.id)"
        return "embedded:\(ff):\(lang):\(title):\(codec)"
    }

    private static func storeURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("Kinema", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(fileName)
    }

    private static func loadAll() -> [String: SubtitleSessionState] {
        let url = storeURL()
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: SubtitleSessionState].self, from: data)) ?? [:]
    }

    private static func persist(_ all: [String: SubtitleSessionState]) {
        let url = storeURL()
        guard let data = try? JSONEncoder().encode(all) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
