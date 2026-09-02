import Foundation
import KinemaCore
import KinemaMedia

@MainActor
public enum PlaybillLibraryResolver {
    /// Cheap play-button check — linked files only, no library walk.
    public static func hasLinkedMedia(for targetID: String) -> Bool {
        for link in PlaybillStore.mediaLinks(for: targetID) {
            if resolveMediaURL(mediaID: link.mediaID) != nil { return true }
        }
        return false
    }

    /// Local or stream files in Kinema that match a Playbill catalog title.
    public static func localMedia(for targetID: String, scanLibrary: Bool = true) -> [PlaybillLocalMedia] {
        guard let entry = PlaybillStore.entry(for: targetID) else { return [] }

        var results: [PlaybillLocalMedia] = []
        var seen = Set<String>()

        for link in PlaybillStore.mediaLinks(for: targetID) {
            if let url = resolveMediaURL(mediaID: link.mediaID),
               seen.insert(url.standardizedFileURL.path).inserted {
                results.append(PlaybillLocalMedia(
                    url: url,
                    title: displayTitle(for: url)
                ))
            }
        }

        guard scanLibrary else {
            return results.sorted {
                $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        }

        LibraryRootStore.shared.prepareLibraryServices()
        for root in LibraryRootStore.shared.roots {
            guard let rootURL = LibraryRootStore.shared.resolveURL(for: root) else { continue }
            for url in WatchProgressStore.mediaURLs(under: rootURL) {
                let key = url.standardizedFileURL.path
                guard seen.insert(key).inserted else { continue }
                guard PlaybillMatcher.matchesCatalogEntry(entry, url: url) else { continue }
                results.append(PlaybillLocalMedia(url: url, title: displayTitle(for: url)))
            }
        }

        for progressEntry in WatchProgressStore.recentEntries(limit: 200) {
            guard let url = progressEntry.url else { continue }
            let key = url.standardizedFileURL.path
            guard seen.insert(key).inserted else { continue }
            guard PlaybillMatcher.matchesCatalogEntry(entry, url: url) else { continue }
            results.append(PlaybillLocalMedia(url: url, title: progressEntry.title))
        }

        return results.sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    /// Links local library files to episode catalog entries for a tracked show.
    public static func indexLibraryMedia(forShowTargetID showTargetID: String) {
        indexLibraryMedia(forShowTargetIDs: [showTargetID])
    }

    /// Index multiple shows in one library walk. Timeline used to check links only,
    /// so matching files that had never been played remained invisible to Up Next.
    public static func indexLibraryMedia(forShowTargetIDs showTargetIDs: [String]) {
        let shows = showTargetIDs.compactMap { targetID -> CatalogEntry? in
            guard let show = PlaybillStore.entry(for: targetID), show.kind == .tvShow else { return nil }
            return show
        }
        guard !shows.isEmpty else { return }

        let showsByExactKey = Dictionary(grouping: shows) {
            MediaSeriesOrganizer.showKey(forTitle: $0.title)
        }
        LibraryRootStore.shared.prepareLibraryServices()

        var pendingLinks: [(mediaID: String, targetID: String)] = []
        var pendingMemories: [(showKey: String, tmdbShowID: Int)] = []
        var seenURLs = Set<String>()

        for root in LibraryRootStore.shared.roots {
            guard let rootURL = LibraryRootStore.shared.resolveURL(for: root) else { continue }
            for url in WatchProgressStore.mediaURLs(under: rootURL) {
                guard seenURLs.insert(url.standardizedFileURL.path).inserted else { continue }
                guard let episode = MediaSeriesOrganizer.episodeIdentity(from: url) else { continue }
                let filenameShowKey = MediaSeriesOrganizer.showKey(forTitle: episode.showTitle)
                let matchingShow: CatalogEntry?
                if let exact = showsByExactKey[filenameShowKey], exact.count == 1 {
                    matchingShow = exact[0]
                } else {
                    let fuzzy = shows.filter {
                        MediaSeriesOrganizer.showTitleMatches(episode.showTitle, catalogTitle: $0.title)
                    }
                    matchingShow = fuzzy.count == 1 ? fuzzy[0] : nil
                }
                guard let show = matchingShow else { continue }

                let catalogShowKey = MediaSeriesOrganizer.showKey(forTitle: show.title)
                if filenameShowKey != catalogShowKey {
                    pendingMemories.append((filenameShowKey, show.tmdbID))
                }

                let targetID = CatalogEntry.episodeID(
                    showTmdbID: show.tmdbID,
                    season: episode.season,
                    episode: episode.episode
                )
                let mediaID = WatchProgressStore.mediaID(for: url)
                guard PlaybillStore.link(for: mediaID)?.targetID != targetID else { continue }
                pendingLinks.append((mediaID, targetID))
            }
        }

        for memoryKey in Set(pendingMemories.map { "\($0.showKey)|\($0.tmdbShowID)" }) {
            let parts = memoryKey.split(separator: "|", maxSplits: 1)
            guard parts.count == 2, let tmdbShowID = Int(parts[1]) else { continue }
            PlaybillStore.rememberShow(showKey: String(parts[0]), tmdbShowID: tmdbShowID)
        }
        if !pendingLinks.isEmpty {
            PlaybillStore.linkMediaBatch(
                pendingLinks.map {
                    (mediaID: $0.mediaID, targetID: $0.targetID, confidence: .high, confirmedByUser: false)
                }
            )
        }
    }

    /// Best file to open — prefers the copy with the most playback progress.
    public static func preferredPlayMedia(for targetID: String) -> PlaybillLocalMedia? {
        // Prefer already-linked files first (no filesystem walk).
        let linked = localMedia(for: targetID, scanLibrary: false)
        if !linked.isEmpty {
            return pickPreferred(from: linked)
        }
        return pickPreferred(from: localMedia(for: targetID, scanLibrary: true))
    }

    private static func pickPreferred(from candidates: [PlaybillLocalMedia]) -> PlaybillLocalMedia? {
        candidates.max { lhs, rhs in
            let left = WatchProgressStore.entry(for: lhs.url)?.lastPosition ?? 0
            let right = WatchProgressStore.entry(for: rhs.url)?.lastPosition ?? 0
            if left != right { return left < right }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedDescending
        }
    }

    private static func resolveMediaURL(mediaID: String) -> URL? {
        if let entry = WatchProgressStore.entry(forMediaID: mediaID),
           let url = entry.url,
           urlIsAvailable(url) {
            return url
        }
        if let url = PlaybackHistoryEntry.recoverFileURL(fromStoredPathOrURL: mediaID),
           urlIsAvailable(url) {
            return url
        }
        return nil
    }

    private static func urlIsAvailable(_ url: URL) -> Bool {
        if url.isFileURL {
            return FileManager.default.fileExists(atPath: url.path)
        }
        return true
    }

    private static func displayTitle(for url: URL) -> String {
        WatchProgressStore.entry(for: url)?.title
            ?? url.deletingPathExtension().lastPathComponent
    }
}
