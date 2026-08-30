import Foundation

@MainActor
public enum PlaybillPreferencesStore {
    private static let tmdbAPIKeyKey = "playbill.tmdbAPIKey"
    private static let autoScrobbleKey = "playbill.autoScrobble"
    private static let completionThresholdKey = "playbill.completionThreshold"
    private static let scrobbleStreamsKey = "playbill.scrobbleStreams"

    public static var tmdbAPIKey: String {
        get { UserDefaults.standard.string(forKey: tmdbAPIKeyKey) ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: tmdbAPIKeyKey) }
    }

    public static var isConfigured: Bool {
        !tmdbAPIKey.isEmpty
    }

    /// Auto-log watches from Kinema playback when completion threshold is reached.
    public static var autoScrobbleEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: autoScrobbleKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: autoScrobbleKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: autoScrobbleKey) }
    }

    /// Fraction of runtime (0–1) required to count as watched. Default 1.0 (100%); adjustable down to 0.90.
    public static var completionThreshold: Double {
        get {
            let stored = UserDefaults.standard.double(forKey: completionThresholdKey)
            let resolved = stored > 0 ? stored : 1.0
            return min(1.0, max(0.90, resolved))
        }
        set { UserDefaults.standard.set(min(1.0, max(0.90, newValue)), forKey: completionThresholdKey) }
    }

    /// When false, only local files are scrobbled (not stream URLs). Default: true.
    public static var scrobbleStreams: Bool {
        get {
            if UserDefaults.standard.object(forKey: scrobbleStreamsKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: scrobbleStreamsKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: scrobbleStreamsKey) }
    }
}
