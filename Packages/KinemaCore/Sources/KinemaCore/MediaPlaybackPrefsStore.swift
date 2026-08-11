import Foundation

/// Per-media playback prefs keyed by stable media ID.
public struct MediaPlaybackPrefs: Codable, Sendable, Equatable {
    public var speed: Double?
    public var audioDelay: Double?
    /// Stable track key (`SubtitleSessionStore.trackKey`) or `MediaPlaybackPrefsStore.audioTrackOffKey`.
    public var audioTrackKey: String?

    public init(speed: Double? = nil, audioDelay: Double? = nil, audioTrackKey: String? = nil) {
        self.speed = speed
        self.audioDelay = audioDelay
        self.audioTrackKey = audioTrackKey
    }
}

@MainActor
public enum MediaPlaybackPrefsStore {
    public static let audioTrackOffKey = "off"

    private static let defaultsKey = "kinema.mediaPlaybackPrefs"
    /// Legacy speed-only map from the first speed-remember ship.
    private static let legacySpeedKey = "kinema.playbackSpeeds"
    private static let maxEntries = 400

    public static func prefs(for url: URL) -> MediaPlaybackPrefs {
        migrateLegacySpeedsIfNeeded()
        let id = PlaybackHistoryEntry.mediaID(for: url)
        return loadAll()[id] ?? MediaPlaybackPrefs()
    }

    public static func speed(for url: URL) -> Double? {
        prefs(for: url).speed
    }

    public static func audioDelay(for url: URL) -> Double? {
        prefs(for: url).audioDelay
    }

    public static func audioTrackKey(for url: URL) -> String? {
        prefs(for: url).audioTrackKey
    }

    public static func saveSpeed(_ speed: Double, for url: URL) {
        update(url) { $0.speed = speed }
    }

    public static func saveAudioDelay(_ delay: Double, for url: URL) {
        update(url) { $0.audioDelay = delay }
    }

    public static func saveAudioTrackKey(_ key: String?, for url: URL) {
        update(url) { $0.audioTrackKey = key }
    }

    public static func clear(for url: URL) {
        migrateLegacySpeedsIfNeeded()
        let id = PlaybackHistoryEntry.mediaID(for: url)
        var all = loadAll()
        guard all.removeValue(forKey: id) != nil else { return }
        save(all)
    }

    private static func update(_ url: URL, mutate: (inout MediaPlaybackPrefs) -> Void) {
        migrateLegacySpeedsIfNeeded()
        let id = PlaybackHistoryEntry.mediaID(for: url)
        var all = loadAll()
        var entry = all[id] ?? MediaPlaybackPrefs()
        mutate(&entry)
        all[id] = entry
        if all.count > maxEntries {
            let keysToDrop = Array(all.keys.prefix(all.count - maxEntries))
            for key in keysToDrop {
                all.removeValue(forKey: key)
            }
        }
        save(all)
    }

    private static func migrateLegacySpeedsIfNeeded() {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: legacySpeedKey),
              let legacy = try? JSONDecoder().decode([String: Double].self, from: data),
              !legacy.isEmpty else {
            return
        }
        var all = loadAll()
        for (id, speed) in legacy {
            var entry = all[id] ?? MediaPlaybackPrefs()
            if entry.speed == nil {
                entry.speed = speed
            }
            all[id] = entry
        }
        save(all)
        defaults.removeObject(forKey: legacySpeedKey)
    }

    private static func loadAll() -> [String: MediaPlaybackPrefs] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([String: MediaPlaybackPrefs].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private static func save(_ map: [String: MediaPlaybackPrefs]) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
