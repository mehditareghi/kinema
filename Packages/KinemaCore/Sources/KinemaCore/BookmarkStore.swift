import Foundation

#if os(iOS) || os(tvOS)
/// Persists security-scoped URL bookmarks outside SwiftData.
public enum BookmarkStore {
    private static let prefix = "io.kinema.bookmark."

    public static func save(_ data: Data, for mediaID: String) {
        UserDefaults.standard.set(data, forKey: prefix + mediaID)
    }

    public static func load(for mediaID: String) -> Data? {
        UserDefaults.standard.data(forKey: prefix + mediaID)
    }
}
#endif
