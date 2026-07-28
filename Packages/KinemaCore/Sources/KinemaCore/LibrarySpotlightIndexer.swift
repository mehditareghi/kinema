import Foundation
import KinemaCore
#if canImport(CoreSpotlight)
import CoreSpotlight
import UniformTypeIdentifiers
#endif

/// Indexes built-in (and optionally user) library media into Core Spotlight.
@MainActor
public final class LibrarySpotlightIndexer {
    public static let shared = LibrarySpotlightIndexer()

    private let domainID = "io.kinema.library"

    private init() {}

    public func indexBuiltInLibrary() {
        #if os(iOS) || os(macOS)
        let root = LibraryMediaPaths.ensureBuiltInDirectory()
        let urls = collectMedia(under: root)
        index(urls: urls)
        #endif
    }

    public func removeAll() {
        #if os(iOS) || os(macOS)
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domainID], completionHandler: nil)
        #endif
    }

    public func remove(url: URL) {
        #if os(iOS) || os(macOS)
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [url.path], completionHandler: nil)
        #endif
    }

    private func index(urls: [URL]) {
        #if os(iOS) || os(macOS)
        let items: [CSSearchableItem] = urls.map { url in
            let attributes = CSSearchableItemAttributeSet(contentType: .movie)
            attributes.displayName = url.deletingPathExtension().lastPathComponent
            attributes.contentURL = url
            attributes.path = url.path
            attributes.kind = "Video"
            return CSSearchableItem(
                uniqueIdentifier: url.path,
                domainIdentifier: domainID,
                attributeSet: attributes
            )
        }
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domainID]) { _ in
            CSSearchableIndex.default().indexSearchableItems(items, completionHandler: nil)
        }
        #endif
    }

    private func collectMedia(under root: URL) -> [URL] {
        var results: [URL] = []
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        for case let url as URL in enumerator {
            if LibraryMediaPaths.isIgnoredName(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            if MediaFileTypes.isMediaFile(url) {
                results.append(url)
            }
        }
        return results
    }
}
