import Foundation

#if os(iOS) || os(tvOS)
public enum SecurityScopedBookmark {
    public static func make(for url: URL) -> Data? {
        try? url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    public static func resolve(_ data: Data) -> URL? {
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withoutUI,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        return url
    }
}
#endif
