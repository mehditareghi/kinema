import Foundation
import KinemaCore
import KinemaMedia

@MainActor
public enum PlaybillStore {
    private static let fileName = "playbill.json"
    private static var memoryCache: PlaybillDatabase?

    public static func reload() {
        memoryCache = nil
        _ = load()
    }

    public static func rawDatabase() -> PlaybillDatabase {
        load()
    }

    // MARK: - Offline metadata and unresolved watches

    public static func showMetadataSnapshot(for showTargetID: String) -> PlaybillShowMetadataSnapshot? {
        load().showMetadataSnapshots[showTargetID]
    }

    public static func saveShowMetadataSnapshot(_ snapshot: PlaybillShowMetadataSnapshot) {
        var db = load()
        db.showMetadataSnapshots[snapshot.showTargetID] = snapshot
        save(db)
    }

    public static func pendingWatchResolutions() -> [PendingWatchResolution] {
        load().pendingWatchResolutions.sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    public static func enqueuePendingWatch(
        mediaID: String,
        mediaURL: URL,
        mediaTitle: String,
        watchedAt: Date,
        source: WatchSource,
        watchedSeconds: TimeInterval
    ) -> PendingWatchResolution {
        _ = PlaybillConnectivity.shared
        var db = load()
        if let existing = db.pendingWatchResolutions.first(where: {
            $0.mediaID == mediaID && abs($0.watchedAt.timeIntervalSince(watchedAt)) < 60
        }) {
            return existing
        }
        let parsed = MediaSeriesOrganizer.episodeIdentity(from: mediaURL)
        let pending = PendingWatchResolution(
            mediaID: mediaID,
            mediaLocation: mediaURL.absoluteString,
            mediaTitle: mediaTitle,
            parsedShowTitle: parsed?.showTitle,
            parsedSeason: parsed?.season,
            parsedEpisode: parsed?.episode,
            watchedAt: watchedAt,
            source: source,
            watchedSeconds: watchedSeconds
        )
        db.pendingWatchResolutions.append(pending)
        save(db)
        EventBus.shared.emit(.playbillUpdated)
        return pending
    }

    public static func updatePendingWatchAttempt(id: UUID, error: String?) {
        var db = load()
        guard let index = db.pendingWatchResolutions.firstIndex(where: { $0.id == id }) else { return }
        db.pendingWatchResolutions[index].retryCount += 1
        db.pendingWatchResolutions[index].lastAttemptAt = Date()
        db.pendingWatchResolutions[index].lastError = error
        save(db)
        EventBus.shared.emit(.playbillUpdated)
    }

    public static func removePendingWatch(id: UUID) {
        var db = load()
        let oldCount = db.pendingWatchResolutions.count
        db.pendingWatchResolutions.removeAll { $0.id == id }
        guard db.pendingWatchResolutions.count != oldCount else { return }
        save(db)
        EventBus.shared.emit(.playbillUpdated)
    }

    // MARK: - Tracking

    public static func trackedShows() -> [TrackedShow] {
        load().trackedShows.sorted { $0.trackedAt > $1.trackedAt }
    }

    public static func trackedShow(for targetID: String) -> TrackedShow? {
        load().trackedShows.first { $0.targetID == targetID }
    }

    public static func isTracked(targetID: String) -> Bool {
        trackedShow(for: targetID) != nil
    }

    @discardableResult
    public static func trackShow(
        targetID: String,
        status: TrackedShowStatus = .planToWatch
    ) -> TrackedShow? {
        guard let entry = load().catalog[targetID], entry.kind == .tvShow else { return nil }

        var db = load()
        _ = repairWatchedSeriesTracking(in: &db)
        let hasWatchedEpisodes = db.activities.contains { activity in
            guard activity.completion == .full,
                  let episode = db.catalog[activity.targetID],
                  episode.kind == .episode else {
                return false
            }
            return Self.episode(episode, belongsTo: entry)
        }
        let resolvedStatus: TrackedShowStatus = status == .planToWatch && hasWatchedEpisodes ? .watching : status
        db.trackedShows.removeAll { $0.targetID == targetID }
        let tracked = TrackedShow(targetID: targetID, status: resolvedStatus)
        db.trackedShows.append(tracked)
        if let trackingListID = db.lists.first(where: { $0.systemKind == .tracking })?.id {
            db.listItems.removeAll { $0.listID == trackingListID && $0.targetID == targetID }
            db.listItems.append(PlaybillListItem(listID: trackingListID, targetID: targetID))
        }
        if resolvedStatus == .planToWatch,
           let watchlistID = db.lists.first(where: { $0.systemKind == .watchlist })?.id,
           !db.listItems.contains(where: { $0.listID == watchlistID && $0.targetID == targetID }) {
            db.listItems.append(PlaybillListItem(listID: watchlistID, targetID: targetID))
        }
        save(db)
        rememberShow(showKey: MediaSeriesOrganizer.showKey(forTitle: entry.title), tmdbShowID: entry.tmdbID)
        PlaybillLibraryResolver.indexLibraryMedia(forShowTargetID: targetID)
        EventBus.shared.emit(.playbillUpdated)
        return tracked
    }

    public static func untrackShow(targetID: String) {
        var db = load()
        let had = db.trackedShows.contains { $0.targetID == targetID }
        db.trackedShows.removeAll { $0.targetID == targetID }
        if let trackingListID = db.lists.first(where: { $0.systemKind == .tracking })?.id {
            db.listItems.removeAll { $0.listID == trackingListID && $0.targetID == targetID }
        }
        guard had else { return }
        save(db)
        EventBus.shared.emit(.playbillUpdated)
    }

    public static func updateTrackedShowStatus(
        targetID: String,
        status: TrackedShowStatus,
        notify: Bool = true
    ) {
        var db = load()
        guard let index = db.trackedShows.firstIndex(where: { $0.targetID == targetID }) else { return }
        var changed = db.trackedShows[index].status != status
        db.trackedShows[index].status = status
        if let watchlistID = db.lists.first(where: { $0.systemKind == .watchlist })?.id {
            let hasItem = db.listItems.contains { $0.listID == watchlistID && $0.targetID == targetID }
            if status == .planToWatch, !hasItem {
                db.listItems.append(PlaybillListItem(listID: watchlistID, targetID: targetID))
                changed = true
            } else if status != .planToWatch, hasItem {
                db.listItems.removeAll { $0.listID == watchlistID && $0.targetID == targetID }
                changed = true
            }
        }
        guard changed else { return }
        // Status-only writes must not rebuild watched-episode indexes or rescan watchlist.
        save(db, invalidateDerivedCaches: false, pruneWatchlist: false)
        if notify {
            EventBus.shared.emit(.playbillUpdated)
        }
    }

    /// Demote false "Completed" shows in one write — used on Playbill open instead of per-show reconcile.
    @discardableResult
    public static func demoteIncompleteCompletedShows(notify: Bool = true) -> Int {
        var db = load()
        var demoted = 0
        for index in db.trackedShows.indices {
            guard db.trackedShows[index].status == .completed else { continue }
            let targetID = db.trackedShows[index].targetID
            guard let show = db.catalog[targetID], show.kind == .tvShow else { continue }
            let watched = watchedEpisodeCount(forShowTargetID: targetID, tmdbID: show.tmdbID, in: db)
            guard watched > 0 else { continue }

            let required = requiredEpisodeCountForCompletion(show: show, in: db)
            // Completion and detail reconciliation must use the same released
            // episode boundary. Raw TMDB totals can include an undated phantom
            // season (or a genuinely announced future season).
            let shouldDemote = !seriesIsEffectivelyFinished(show, in: db)
                || required == 0
                || watched < required
            guard shouldDemote else { continue }
            db.trackedShows[index].status = .watching
            demoted += 1
        }
        guard demoted > 0 else { return 0 }
        save(db, invalidateDerivedCaches: false, pruneWatchlist: false)
        if notify {
            EventBus.shared.emit(.playbillUpdated)
        }
        return demoted
    }

    public static func reindexTrackedShowsLibraryMedia() {
        for tracked in trackedShows() {
            if let show = entry(for: tracked.targetID), show.kind == .tvShow {
                rememberShow(
                    showKey: MediaSeriesOrganizer.showKey(forTitle: show.title),
                    tmdbShowID: show.tmdbID
                )
            }
            PlaybillLibraryResolver.indexLibraryMedia(forShowTargetID: tracked.targetID)
        }
    }

    public static func reindexTrackedShowsLibraryMediaAsync() async {
        let tracked = trackedShows()
        for item in tracked {
            if let show = entry(for: item.targetID), show.kind == .tvShow {
                rememberShow(
                    showKey: MediaSeriesOrganizer.showKey(forTitle: show.title),
                    tmdbShowID: show.tmdbID
                )
            }
            PlaybillLibraryResolver.indexLibraryMedia(forShowTargetID: item.targetID)
            await Task.yield()
        }
    }

    @discardableResult
    public static func repairWatchedSeriesTracking() -> Int {
        var db = load()
        let repaired = repairWatchedSeriesTracking(in: &db)
            + repairTrackedShowStatuses(in: &db)
            + PlaybillShowProgress.pruneUntrustworthySnapshots(in: &db)
        guard repaired > 0 else { return 0 }
        save(db)
        EventBus.shared.emit(.playbillUpdated)
        return repaired
    }

    // MARK: - Lists

    public static func lists() -> [PlaybillList] {
        let db = load()
        return db.lists.sorted { lhs, rhs in
            if lhs.isSystem != rhs.isSystem { return lhs.isSystem && !rhs.isSystem }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    public static func list(id: UUID) -> PlaybillList? {
        load().lists.first { $0.id == id }
    }

    public static func listEntries(for listID: UUID) -> [PlaybillListEntry] {
        let db = load()
        return db.listItems
            .filter { $0.listID == listID }
            .sorted { $0.addedAt > $1.addedAt }
            .compactMap { item in
                guard let entry = db.catalog[item.targetID] else { return nil }
                return PlaybillListEntry(item: item, entry: entry)
            }
    }

    public static func watchlistID() -> UUID? {
        load().lists.first { $0.systemKind == .watchlist }?.id
    }

    public static func isInWatchlist(targetID: String) -> Bool {
        guard let listID = watchlistID() else { return false }
        return isInList(listID: listID, targetID: targetID)
    }

    public static func titleState(for result: PlaybillSearchResult) -> PlaybillTitleState {
        titleState(targetID: result.id, tmdbID: result.tmdbID, kind: result.kind)
    }

    public static func titleState(targetID: String, tmdbID: Int, kind: PlaybillMediaKind) -> PlaybillTitleState {
        let db = load()
        if kind == .tvShow {
            if let tracked = db.trackedShows.first(where: { $0.targetID == targetID }) {
                return .tracked(tracked.status)
            }

            let watchedCount = watchedEpisodeCount(forShowTargetID: targetID, tmdbID: tmdbID, in: db)
            if watchedCount > 0 {
                return .watched(count: watchedCount)
            }
        } else {
            let watchCount = db.activities.filter {
                $0.targetID == targetID && $0.completion == .full
            }.count
            if watchCount > 0 {
                return .watched(count: watchCount)
            }
        }

        if let watchlistID = db.lists.first(where: { $0.systemKind == .watchlist })?.id,
           db.listItems.contains(where: { $0.listID == watchlistID && $0.targetID == targetID }) {
            return .watchLater
        }
        return .new
    }

    public static func isInList(listID: UUID, targetID: String) -> Bool {
        load().listItems.contains { $0.listID == listID && $0.targetID == targetID }
    }

    @discardableResult
    public static func createList(name: String) -> PlaybillList {
        var db = load()
        let list = PlaybillList(name: name.trimmingCharacters(in: .whitespacesAndNewlines))
        db.lists.append(list)
        save(db)
        EventBus.shared.emit(.playbillUpdated)
        return list
    }

    public static func renameList(id: UUID, name: String) {
        var db = load()
        guard let index = db.lists.firstIndex(where: { $0.id == id }),
              !db.lists[index].isSystem else { return }
        db.lists[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        db.lists[index].updatedAt = Date()
        save(db)
        EventBus.shared.emit(.playbillUpdated)
    }

    public static func deleteList(id: UUID) {
        var db = load()
        guard let list = db.lists.first(where: { $0.id == id }), !list.isSystem else { return }
        db.lists.removeAll { $0.id == id }
        db.listItems.removeAll { $0.listID == id }
        save(db)
        EventBus.shared.emit(.playbillUpdated)
    }

    @discardableResult
    public static func addToList(listID: UUID, targetID: String) -> PlaybillListItem? {
        guard load().catalog[targetID] != nil else { return nil }
        var db = load()
        guard db.lists.contains(where: { $0.id == listID }) else { return nil }
        guard !db.listItems.contains(where: { $0.listID == listID && $0.targetID == targetID }) else {
            return db.listItems.first { $0.listID == listID && $0.targetID == targetID }
        }
        let item = PlaybillListItem(listID: listID, targetID: targetID)
        db.listItems.append(item)
        if let index = db.lists.firstIndex(where: { $0.id == listID }) {
            db.lists[index].updatedAt = Date()
        }
        save(db)
        EventBus.shared.emit(.playbillUpdated)
        return item
    }

    public static func removeFromList(listID: UUID, targetID: String) {
        var db = load()
        let original = db.listItems.count
        db.listItems.removeAll { $0.listID == listID && $0.targetID == targetID }
        guard db.listItems.count != original else { return }
        if let index = db.lists.firstIndex(where: { $0.id == listID }) {
            db.lists[index].updatedAt = Date()
        }
        save(db)
        EventBus.shared.emit(.playbillUpdated)
    }

    @discardableResult
    public static func addToWatchlist(targetID: String) -> PlaybillListItem? {
        guard let listID = watchlistID() else { return nil }
        return addToList(listID: listID, targetID: targetID)
    }

    public static func removeFromWatchlist(targetID: String) {
        guard let listID = watchlistID() else { return }
        removeFromList(listID: listID, targetID: targetID)
    }

    public static func diaryItems(limit: Int? = nil) -> [PlaybillDiaryItem] {
        let db = load()
        let sorted = db.activities
            .sorted { $0.watchedAt > $1.watchedAt }
        let slice = limit.map { Array(sorted.prefix($0)) } ?? sorted
        return slice.compactMap { activity in
            guard let entry = db.catalog[activity.targetID] else { return nil }
            return PlaybillDiaryItem(activity: activity, entry: entry)
        }
    }

    public static func entry(for targetID: String) -> CatalogEntry? {
        load().catalog[targetID]
    }

    public static func activities(for targetID: String) -> [WatchActivity] {
        load().activities
            .filter { $0.targetID == targetID }
            .sorted { $0.watchedAt > $1.watchedAt }
    }

    public static func hasFullWatch(
        targetID: String,
        watchedAt: Date,
        source: WatchSource,
        tolerance: TimeInterval = 60
    ) -> Bool {
        let start = watchedAt.addingTimeInterval(-tolerance)
        let end = watchedAt.addingTimeInterval(tolerance)
        return load().activities.contains {
            $0.targetID == targetID &&
            $0.source == source &&
            $0.completion == .full &&
            $0.watchedAt >= start &&
            $0.watchedAt <= end
        }
    }

    public static func displayEpisodeTotal(for show: CatalogEntry) -> Int {
        let db = load()
        let watched = watchedEpisodeCount(forShowTargetID: show.id, tmdbID: show.tmdbID, in: db)
        let released = requiredEpisodeCountForCompletion(show: show, in: db)

        // Finished shows are capped at the released/watched body of work so an
        // undated placeholder season cannot turn "15 of 15" into "15 of 30".
        if seriesIsEffectivelyFinished(show, in: db) {
            return max(released, watched)
        }

        // For active shows the announced catalog total is useful context and,
        // unlike the old watched-only fallback, can never produce "2 of 2"
        // merely because two imported episode rows are locally available.
        return max(show.totalEpisodeCount ?? 0, max(released, watched))
    }

    public static func seriesIsEffectivelyFinished(
        showTargetID: String,
        watchedCount: Int
    ) -> Bool {
        let db = load()
        guard let show = db.catalog[showTargetID], show.kind == .tvShow else { return false }
        guard seriesIsEffectivelyFinished(show, in: db) else { return false }
        let required = max(requiredEpisodeCountForCompletion(show: show, in: db), showHasEnded(show) ? 0 : (show.totalEpisodeCount ?? 0))
        return watchedCount > 0 && (required == 0 || watchedCount >= required)
    }

    public static func episode(_ episode: CatalogEntry, belongsTo show: CatalogEntry) -> Bool {
        guard episode.kind == .episode, show.kind == .tvShow else { return false }
        if episode.parentShowID == show.id || episode.tmdbID == show.tmdbID {
            return true
        }
        guard episode.parentShowID == nil, episode.tmdbID <= 0 else { return false }
        return MediaSeriesOrganizer.showKey(forTitle: episode.title) == MediaSeriesOrganizer.showKey(forTitle: show.title)
    }

    public static func playbackProgress(for targetID: String) -> TitlePlaybackProgress? {
        load().playbackProgress[targetID]
    }

    public static func continueItems(limit: Int = 40) -> [PlaybillContinueItem] {
        let db = load()
        let items = db.playbackProgress.compactMap { targetID, progress -> PlaybillContinueItem? in
            guard progress.hasPartialResume,
                  let entry = db.catalog[targetID] else { return nil }
            return PlaybillContinueItem(entry: entry, progress: progress)
        }
        .sorted { $0.progress.updatedAt > $1.progress.updatedAt }
        return Array(items.prefix(limit))
    }

    public static func updatePlaybackProgress(
        targetID: String,
        position: TimeInterval,
        duration: TimeInterval
    ) {
        guard WatchProgressStore.hasEstablishedPlayback(position: position, duration: duration) else { return }

        var db = load()
        if duration > 0, position >= duration - 10 {
            db.playbackProgress.removeValue(forKey: targetID)
        } else if position > 5 {
            db.playbackProgress[targetID] = TitlePlaybackProgress(
                position: position,
                duration: max(duration, db.playbackProgress[targetID]?.duration ?? 0)
            )
        } else {
            return
        }
        save(db)
    }

    /// Put a confidently identified title into the user's active Playbill as soon
    /// as they genuinely begin watching it. Films are represented by their resume
    /// progress; an unwatched episode also starts or resumes its parent series.
    public static func beginPlayback(
        targetID: String,
        position: TimeInterval,
        duration: TimeInterval
    ) {
        updatePlaybackProgress(targetID: targetID, position: position, duration: duration)

        // A replay gets resume state and eventually another activity, but it must
        // not turn a completed series back into Watching.
        guard let episode = entry(for: targetID),
              episode.kind == .episode,
              !isWatched(targetID: targetID),
              let showTargetID = episode.parentShowID,
              entry(for: showTargetID)?.kind == .tvShow else {
            return
        }

        if trackedShow(for: showTargetID)?.status != .watching {
            _ = trackShow(targetID: showTargetID, status: .watching)
        }
    }

    public static func clearPlaybackProgress(for targetID: String) {
        var db = load()
        guard db.playbackProgress[targetID] != nil else { return }
        db.playbackProgress.removeValue(forKey: targetID)
        save(db)
    }

    public static func isWatched(targetID: String) -> Bool {
        load().activities.contains { $0.targetID == targetID && $0.completion == .full }
    }

    public static func watchCount(for targetID: String) -> Int {
        load().activities.filter { $0.targetID == targetID && $0.completion == .full }.count
    }

    public static func repeatWatchCount(for targetID: String) -> Int {
        let count = watchCount(for: targetID)
        return count > 1 ? count : 0
    }

    public static func seriesRepeatWatchCount(for showTargetID: String) -> Int {
        let db = load()
        guard let show = db.catalog[showTargetID], show.kind == .tvShow else { return 0 }
        let requiredCount = requiredEpisodeCountForCompletion(show: show, in: db)
        guard requiredCount > 0 else { return 0 }

        let expectedEpisodeIDs = releasedEpisodeIDs(for: show, in: db)
        guard expectedEpisodeIDs.count >= requiredCount else { return 0 }

        let countsByEpisodeID = episodeWatchCounts(for: show, in: db)
        var minimum = Int.max
        for episodeID in expectedEpisodeIDs {
            let count = countsByEpisodeID[episodeID, default: 0]
            guard count > 1 else { return 0 }
            minimum = min(minimum, count)
        }
        return minimum == Int.max ? 0 : minimum
    }

    public static func episodeRepeatWatchCount(showTargetID: String, season: Int, episode: Int) -> Int {
        let db = load()
        guard let show = db.catalog[showTargetID], show.kind == .tvShow else { return 0 }
        let episodeID = CatalogEntry.episodeID(showTmdbID: show.tmdbID, season: season, episode: episode)
        let count = episodeWatchCounts(for: show, in: db)[episodeID, default: 0]
        return count > 1 ? count : 0
    }

    public static func link(for mediaID: String) -> MediaLink? {
        load().mediaLinks.first { $0.mediaID == mediaID }
    }

    public static func targetID(for mediaID: String) -> String? {
        link(for: mediaID)?.targetID
    }

    public static func mediaLinks(for targetID: String) -> [MediaLink] {
        load().mediaLinks.filter { $0.targetID == targetID }
    }

    public static func activity(id: UUID) -> WatchActivity? {
        load().activities.first { $0.id == id }
    }

    @discardableResult
    public static func updateActivity(id: UUID, watchedAt: Date) -> Bool {
        var db = load()
        guard watchedAt <= Date(),
              let index = db.activities.firstIndex(where: { $0.id == id }),
              let entry = db.catalog[db.activities[index].targetID] else { return false }
        if entry.kind == .episode,
           let show = entry.parentShowID.flatMap({ db.catalog[$0] })
               ?? db.catalog[CatalogEntry.showID(entry.tmdbID)],
           !episodeIsReleased(entry, in: show, database: db, relativeTo: watchedAt) {
            return false
        }
        db.activities[index].watchedAt = watchedAt
        let targetID = db.activities[index].targetID
        save(db)
        EventBus.shared.emit(.playbillUpdated)
        MediaWatchCoordinator.syncAfterPlaybillActivityChange(targetID: targetID)
        return true
    }

    public static func showMemory(for showKey: String) -> ShowMatchMemory? {
        showMemory(matchingKey: showKey)
    }

    public static func showMemory(matchingKey key: String) -> ShowMatchMemory? {
        let db = load()
        if let exact = db.showMemories.first(where: { $0.showKey == key }) {
            return exact
        }
        return db.showMemories.first { memory in
            let catalogTitle = db.catalog[memory.showTargetID]?.title ?? memory.showKey
            return MediaSeriesOrganizer.showKeysMatch(key, catalogTitle: catalogTitle)
        }
    }

    @discardableResult
    public static func upsertCatalog(_ entry: CatalogEntry) -> CatalogEntry {
        var db = load()
        let resolved = db.catalog[entry.id].map { mergeCatalogEntry(existing: $0, incoming: entry) } ?? entry
        db.catalog[entry.id] = resolved
        save(db)
        return resolved
    }

    /// Imports and filename matches often carry only identity fields. They must
    /// enrich an entry, never downgrade a previously fetched TMDB record back to
    /// a watched-only placeholder on the next app launch/import.
    private static func mergeCatalogEntry(
        existing: CatalogEntry,
        incoming: CatalogEntry
    ) -> CatalogEntry {
        var merged = incoming
        merged.parentShowID = incoming.parentShowID ?? existing.parentShowID
        if incoming.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || incoming.title == "Series"
            || incoming.title == "Movie" {
            merged.title = existing.title
        }
        merged.subtitle = incoming.subtitle ?? existing.subtitle
        merged.year = incoming.year ?? existing.year
        merged.overview = incoming.overview ?? existing.overview
        merged.posterPath = incoming.posterPath ?? existing.posterPath
        merged.backdropPath = incoming.backdropPath ?? existing.backdropPath
        merged.genres = incoming.genres.isEmpty ? existing.genres : incoming.genres
        merged.runtimeMinutes = incoming.runtimeMinutes ?? existing.runtimeMinutes
        merged.seasonNumber = incoming.seasonNumber ?? existing.seasonNumber
        merged.episodeNumber = incoming.episodeNumber ?? existing.episodeNumber
        merged.episodeAirDate = incoming.episodeAirDate ?? existing.episodeAirDate
        merged.cachedAt = max(incoming.cachedAt, existing.cachedAt)

        if incoming.kind == .tvShow, incoming.seriesStatus == nil {
            merged.seriesStatus = existing.seriesStatus
            merged.seriesInProduction = existing.seriesInProduction
            merged.nextEpisodeAirDate = existing.nextEpisodeAirDate
            merged.totalEpisodeCount = existing.totalEpisodeCount
            merged.lastAiredSeasonNumber = existing.lastAiredSeasonNumber
            merged.lastAiredEpisodeNumber = existing.lastAiredEpisodeNumber
            merged.lastEpisodeAirDate = existing.lastEpisodeAirDate
        }
        return merged
    }

    @discardableResult
    public static func logWatch(
        targetID: String,
        watchedAt: Date = Date(),
        source: WatchSource,
        completion: WatchCompletion = .full,
        watchedSeconds: TimeInterval? = nil
    ) -> WatchActivity? {
        guard watchedAt <= Date() else { return nil }
        var db = load()
        guard let entry = db.catalog[targetID] else { return nil }
        guard entry.kind != .tvShow else { return nil }
        if completion == .full,
           entry.kind == .episode,
           let show = entry.parentShowID.flatMap({ db.catalog[$0] })
               ?? db.catalog[CatalogEntry.showID(entry.tmdbID)],
           !episodeIsReleased(entry, in: show, database: db, relativeTo: watchedAt) {
            return nil
        }

        // Avoid duplicate scrobbles/imports within the same minute for the same title.
        if completion == .full {
            let recentCutoff = watchedAt.addingTimeInterval(-60)
            let recentEnd = watchedAt.addingTimeInterval(60)
            if db.activities.contains(where: {
                $0.targetID == targetID &&
                $0.source == source &&
                $0.completion == .full &&
                $0.watchedAt >= recentCutoff &&
                $0.watchedAt <= recentEnd
            }) {
                return nil
            }
        }

        let activity = WatchActivity(
            targetID: targetID,
            watchedAt: watchedAt,
            source: source,
            completion: completion,
            watchedSeconds: watchedSeconds
        )
        db.activities.append(activity)
        if completion == .full {
            db.playbackProgress.removeValue(forKey: targetID)
            consumeWatchLaterAndStartSeries(for: entry, in: &db)
        }
        save(db)
        EventBus.shared.emit(.playbillUpdated)
        MediaWatchCoordinator.syncAfterPlaybillActivityChange(targetID: targetID)
        return activity
    }

    @discardableResult
    public static func logWatchBatch(
        targetIDs: [String],
        watchedAt: Date = Date(),
        source: WatchSource,
        completion: WatchCompletion = .full
    ) -> Int {
        guard !targetIDs.isEmpty, watchedAt <= Date() else { return 0 }

        var db = load()
        var logged = 0
        var loggedIDs: [String] = []

        for targetID in targetIDs {
            guard let entry = db.catalog[targetID], entry.kind != .tvShow else { continue }
            if completion == .full,
               entry.kind == .episode,
               let show = entry.parentShowID.flatMap({ db.catalog[$0] })
                   ?? db.catalog[CatalogEntry.showID(entry.tmdbID)],
               !episodeIsReleased(entry, in: show, database: db, relativeTo: watchedAt) {
                continue
            }
            let activity = WatchActivity(
                targetID: targetID,
                watchedAt: watchedAt,
                source: source,
                completion: completion,
                watchedSeconds: nil
            )
            db.activities.append(activity)
            if completion == .full {
                db.playbackProgress.removeValue(forKey: targetID)
                consumeWatchLaterAndStartSeries(for: entry, in: &db)
            }
            logged += 1
            loggedIDs.append(targetID)
        }

        guard logged > 0 else { return 0 }
        save(db)
        let lastLoggedID = loggedIDs.last
        Task { @MainActor in
            await Task.yield()
            EventBus.shared.emit(.playbillUpdated)
            if let lastLoggedID {
                MediaWatchCoordinator.syncAfterPlaybillActivityChange(targetID: lastLoggedID)
            }
        }
        return logged
    }

    /// Watching is the completion of the Watch Later action, not another task for the user.
    private static func consumeWatchLaterAndStartSeries(for entry: CatalogEntry, in db: inout PlaybillDatabase) {
        let owningTargetID = entry.parentShowID ?? entry.id
        if let watchlistID = db.lists.first(where: { $0.systemKind == .watchlist })?.id {
            db.listItems.removeAll {
                $0.listID == watchlistID && ($0.targetID == entry.id || $0.targetID == owningTargetID)
            }
        }
        if let parentID = entry.parentShowID,
           let index = db.trackedShows.firstIndex(where: { $0.targetID == parentID }),
           db.trackedShows[index].status == .planToWatch {
            db.trackedShows[index].status = .watching
        }
    }

    private static func watchedEpisodeCount(forShowTargetID showTargetID: String, tmdbID: Int, in db: PlaybillDatabase) -> Int {
        guard db.catalog[showTargetID] != nil else { return 0 }
        let watchedEpisodeIDs = db.activities.compactMap { activity -> String? in
            guard activity.completion == .full,
                  let episode = db.catalog[activity.targetID],
                  episode.kind == .episode else {
                return nil
            }
            guard episode.parentShowID == showTargetID
                    || (episode.parentShowID == nil && episode.tmdbID == tmdbID) else { return nil }
            guard let season = episode.seasonNumber, let number = episode.episodeNumber else {
                return activity.targetID
            }
            return CatalogEntry.episodeID(showTmdbID: tmdbID, season: season, episode: number)
        }
        return Set(watchedEpisodeIDs).count
    }

    private static func episodeWatchCounts(for show: CatalogEntry, in db: PlaybillDatabase) -> [String: Int] {
        return db.activities.reduce(into: [:]) { counts, activity in
            guard activity.completion == .full,
                  let episode = db.catalog[activity.targetID],
                  episode.kind == .episode,
                  Self.episode(episode, belongsTo: show) else { return }
            let canonicalID: String
            if let season = episode.seasonNumber, let number = episode.episodeNumber {
                canonicalID = CatalogEntry.episodeID(showTmdbID: show.tmdbID, season: season, episode: number)
            } else {
                canonicalID = activity.targetID
            }
            counts[canonicalID, default: 0] += 1
        }
    }

    private static func releasedEpisodeIDs(for show: CatalogEntry, in db: PlaybillDatabase) -> Set<String> {
        let today = Calendar.current.startOfDay(for: Date())
        var episodeIDs: Set<String> = []

        // A real watch record is stronger release evidence than incomplete
        // third-party air-date metadata.
        for activity in db.activities where activity.completion == .full {
            guard let episode = db.catalog[activity.targetID],
                  episode.kind == .episode,
                  Self.episode(episode, belongsTo: show),
                  let season = episode.seasonNumber,
                  let number = episode.episodeNumber else { continue }
            episodeIDs.insert(CatalogEntry.episodeID(
                showTmdbID: show.tmdbID,
                season: season,
                episode: number
            ))
        }

        if let snapshot = db.showMetadataSnapshots[show.id], snapshot.hasCompleteEpisodeMap {
            for season in snapshot.seasons where season.seasonNumber > 0 {
                if !season.episodes.isEmpty {
                    for episode in season.episodes {
                        let isReleased: Bool
                        if let airDate = episode.airDate {
                            isReleased = Calendar.current.startOfDay(for: airDate) <= today
                        } else if let lastSeason = show.lastAiredSeasonNumber,
                                  let lastEpisode = show.lastAiredEpisodeNumber {
                            isReleased = season.seasonNumber < lastSeason
                                || (season.seasonNumber == lastSeason && episode.episodeNumber <= lastEpisode)
                        } else {
                            isReleased = showHasEnded(show)
                        }
                        guard isReleased else { continue }
                        episodeIDs.insert(CatalogEntry.episodeID(
                            showTmdbID: show.tmdbID,
                            season: season.seasonNumber,
                            episode: episode.episodeNumber
                        ))
                    }
                } else if season.episodeCount > 0 {
                    let upperBound: Int
                    if let lastSeason = show.lastAiredSeasonNumber,
                       let lastEpisode = show.lastAiredEpisodeNumber,
                       season.seasonNumber == lastSeason {
                        upperBound = min(season.episodeCount, lastEpisode)
                    } else {
                        upperBound = season.episodeCount
                    }
                    guard upperBound > 0 else { continue }
                    for episode in 1...upperBound {
                        episodeIDs.insert(CatalogEntry.episodeID(
                            showTmdbID: show.tmdbID,
                            season: season.seasonNumber,
                            episode: episode
                        ))
                    }
                }
            }
        }

        if episodeIDs.isEmpty {
            for episode in db.catalog.values where episode.kind == .episode && Self.episode(episode, belongsTo: show) {
                guard episodeIsReleased(episode, in: show, database: db),
                      let season = episode.seasonNumber,
                      let number = episode.episodeNumber else { continue }
                episodeIDs.insert(CatalogEntry.episodeID(showTmdbID: show.tmdbID, season: season, episode: number))
            }
        }

        return episodeIDs
    }

    @discardableResult
    public static func removeActivity(id: UUID) -> PlaybillWatchRemovalSnapshot? {
        var db = load()
        guard let removed = db.activities.first(where: { $0.id == id }) else { return nil }
        let original = db.activities.count
        db.activities.removeAll { $0.id == id }
        guard db.activities.count != original else { return nil }
        save(db)
        EventBus.shared.emit(.playbillUpdated)
        MediaWatchCoordinator.syncAfterPlaybillActivityChange(targetID: removed.targetID)
        return PlaybillWatchRemovalSnapshot(activities: [removed])
    }

    public static func clearWatches(for targetID: String) {
        _ = removeWatchRecords(for: targetID)
    }

    @discardableResult
    public static func removeWatchRecords(for targetID: String) -> PlaybillWatchRemovalSnapshot? {
        var db = load()
        let removedActivities = db.activities.filter { $0.targetID == targetID }
        var removedProgress: [String: TitlePlaybackProgress] = [:]
        if let progress = db.playbackProgress[targetID] {
            removedProgress[targetID] = progress
        }
        let snapshot = PlaybillWatchRemovalSnapshot(
            activities: removedActivities,
            playbackProgress: removedProgress
        )
        guard !snapshot.isEmpty else { return nil }

        db.activities.removeAll { $0.targetID == targetID }
        db.playbackProgress.removeValue(forKey: targetID)
        save(db)
        EventBus.shared.emit(.playbillUpdated)
        MediaWatchCoordinator.syncAfterPlaybillActivityChange(targetID: targetID)
        return snapshot
    }

    @discardableResult
    public static func removeWatchRecordsForShow(targetID: String) -> PlaybillWatchRemovalSnapshot? {
        var db = load()
        guard let show = db.catalog[targetID], show.kind == .tvShow else {
            return removeWatchRecords(for: targetID)
        }

        let targetIDs = Set(db.catalog.values.compactMap { entry -> String? in
            if entry.id == targetID { return entry.id }
            return Self.episode(entry, belongsTo: show) ? entry.id : nil
        })
        guard !targetIDs.isEmpty else { return nil }

        let removedActivities = db.activities.filter { targetIDs.contains($0.targetID) }
        let removedProgress = db.playbackProgress.filter { targetIDs.contains($0.key) }
        let snapshot = PlaybillWatchRemovalSnapshot(
            activities: removedActivities,
            playbackProgress: removedProgress
        )
        guard !snapshot.isEmpty else { return nil }

        db.activities.removeAll { targetIDs.contains($0.targetID) }
        for targetID in targetIDs {
            db.playbackProgress.removeValue(forKey: targetID)
        }
        save(db)
        EventBus.shared.emit(.playbillUpdated)
        for targetID in targetIDs {
            MediaWatchCoordinator.syncAfterPlaybillActivityChange(targetID: targetID)
        }
        return snapshot
    }

    public static func restoreWatchRecords(_ snapshot: PlaybillWatchRemovalSnapshot) {
        guard !snapshot.isEmpty else { return }
        var db = load()
        var changed = false
        var targetIDs = Set<String>()

        let existingActivityIDs = Set(db.activities.map(\.id))
        for activity in snapshot.activities where !existingActivityIDs.contains(activity.id) {
            db.activities.append(activity)
            targetIDs.insert(activity.targetID)
            changed = true
        }

        for (targetID, progress) in snapshot.playbackProgress {
            db.playbackProgress[targetID] = progress
            targetIDs.insert(targetID)
            changed = true
        }

        guard changed else { return }
        save(db)
        EventBus.shared.emit(.playbillUpdated)
        for targetID in targetIDs {
            MediaWatchCoordinator.syncAfterPlaybillActivityChange(targetID: targetID)
        }
    }

    public static func linkMedia(
        mediaID: String,
        targetID: String,
        confidence: MatchConfidence,
        confirmedByUser: Bool
    ) {
        linkMediaBatch([(
            mediaID: mediaID,
            targetID: targetID,
            confidence: confidence,
            confirmedByUser: confirmedByUser
        )])
    }

    /// Link many files in one write — avoids N× JSON encode + event storms during reindex.
    public static func linkMediaBatch(
        _ links: [(mediaID: String, targetID: String, confidence: MatchConfidence, confirmedByUser: Bool)]
    ) {
        guard !links.isEmpty else { return }
        var db = load()
        var changed = false
        for link in links {
            let existing = db.mediaLinks.first { $0.mediaID == link.mediaID }
            if existing?.targetID == link.targetID,
               existing?.matchConfidence == link.confidence,
               existing?.confirmedByUser == link.confirmedByUser {
                continue
            }
            db.mediaLinks.removeAll { $0.mediaID == link.mediaID }
            db.mediaLinks.append(MediaLink(
                mediaID: link.mediaID,
                targetID: link.targetID,
                matchConfidence: link.confidence,
                confirmedByUser: link.confirmedByUser
            ))
            changed = true
        }
        guard changed else { return }
        save(db)
        for link in links {
            MediaWatchCoordinator.backfillPlaybillProgress(forMediaID: link.mediaID, targetID: link.targetID)
        }
        EventBus.shared.emit(.playbillUpdated)
    }

    public static func rememberShow(showKey: String, tmdbShowID: Int) {
        var db = load()
        if let existing = db.showMemories.first(where: { $0.showKey == showKey }),
           existing.tmdbShowID == tmdbShowID {
            return
        }
        db.showMemories.removeAll { $0.showKey == showKey }
        db.showMemories.append(ShowMatchMemory(
            showKey: showKey,
            tmdbShowID: tmdbShowID,
            showTargetID: CatalogEntry.showID(tmdbShowID),
            confirmedAt: Date()
        ))
        save(db)
    }

    public static func statistics() -> PlaybillStatistics {
        let db = load()
        let fullActivities = db.activities.filter { $0.completion == .full }
        guard !fullActivities.isEmpty else { return .empty }

        let calendar = Calendar.current
        let now = Date()
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let yearStart = calendar.date(from: calendar.dateComponents([.year], from: now)) ?? now

        var uniqueTargets = Set<String>()
        var movieWatches = 0
        var episodeWatches = 0
        var totalSeconds: TimeInterval = 0
        var watchesThisMonth = 0
        var watchesThisYear = 0
        var watchCounts: [String: Int] = [:]

        for activity in fullActivities {
            uniqueTargets.insert(activity.targetID)
            watchCounts[activity.targetID, default: 0] += 1
            if activity.watchedAt >= monthStart { watchesThisMonth += 1 }
            if activity.watchedAt >= yearStart { watchesThisYear += 1 }

            if let entry = db.catalog[activity.targetID] {
                switch entry.kind {
                case .movie: movieWatches += 1
                case .episode: episodeWatches += 1
                case .tvShow: break
                }
                if let seconds = activity.watchedSeconds, seconds > 0 {
                    totalSeconds += seconds
                } else if let runtime = entry.runtimeMinutes, runtime > 0 {
                    totalSeconds += TimeInterval(runtime * 60)
                }
            }
        }

        let rewatchCount = watchCounts.values.filter { $0 > 1 }.reduce(0) { $0 + ($1 - 1) }

        return PlaybillStatistics(
            totalWatches: fullActivities.count,
            uniqueTitles: uniqueTargets.count,
            movieWatches: movieWatches,
            episodeWatches: episodeWatches,
            rewatchCount: rewatchCount,
            totalWatchedHours: totalSeconds / 3600,
            watchesThisMonth: watchesThisMonth,
            watchesThisYear: watchesThisYear
        )
    }

    public static func exportBackup() throws -> Data {
        let db = load()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(db)
    }

    public static func importBackup(from data: Data, merge: Bool) throws -> Int {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let imported = try decoder.decode(PlaybillDatabase.self, from: data)

        var db = merge ? load() : PlaybillDatabase()
        var added = 0

        for (key, entry) in imported.catalog {
            if db.catalog[key] == nil || !merge {
                db.catalog[key] = entry
            }
        }

        let existingIDs = Set(db.activities.map(\.id))
        for activity in imported.activities {
            if !existingIDs.contains(activity.id) {
                db.activities.append(activity)
                added += 1
            }
        }

        let existingLinks = Set(db.mediaLinks.map(\.id))
        for link in imported.mediaLinks where !existingLinks.contains(link.id) {
            db.mediaLinks.append(link)
        }

        let existingMemories = Set(db.showMemories.map(\.showKey))
        for memory in imported.showMemories where !existingMemories.contains(memory.showKey) {
            db.showMemories.append(memory)
        }

        for progress in imported.playbackProgress {
            if db.playbackProgress[progress.key] == nil || !merge {
                db.playbackProgress[progress.key] = progress.value
            }
        }

        let existingTracked = Set(db.trackedShows.map(\.targetID))
        for tracked in imported.trackedShows where !existingTracked.contains(tracked.targetID) {
            db.trackedShows.append(tracked)
        }

        let existingListIDs = Set(db.lists.map(\.id))
        for list in imported.lists where !list.isSystem && !existingListIDs.contains(list.id) {
            db.lists.append(list)
        }

        let existingListItemIDs = Set(db.listItems.map(\.id))
        for item in imported.listItems where !existingListItemIDs.contains(item.id) {
            db.listItems.append(item)
        }

        ensureSystemLists(in: &db)
        _ = repairWatchedSeriesTracking(in: &db)
        save(db)
        EventBus.shared.emit(.playbillUpdated)
        return added
    }

    public static func replaceDatabase(_ database: PlaybillDatabase) {
        save(database)
        EventBus.shared.emit(.playbillUpdated)
    }

    private static func storeURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("Kinema", isDirectory: true)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
           !isDirectory.boolValue {
            let recovered = base.appendingPathComponent("Kinema.playbill-recovered.json")
            try? FileManager.default.removeItem(at: recovered)
            try? FileManager.default.moveItem(at: directory, to: recovered)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? FileManager.default.moveItem(at: recovered, to: directory.appendingPathComponent(fileName))
        } else {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory.appendingPathComponent(fileName)
    }

    private static func ensureSystemLists(in database: inout PlaybillDatabase) {
        if !database.lists.contains(where: { $0.systemKind == .tracking }) {
            database.lists.append(PlaybillList(name: "Tracking", systemKind: .tracking))
        }
        if !database.lists.contains(where: { $0.systemKind == .watchlist }) {
            database.lists.append(PlaybillList(name: "Watchlist", systemKind: .watchlist))
        }
    }

    @discardableResult
    private static func repairWatchedSeriesTracking(in database: inout PlaybillDatabase) -> Int {
        ensureSystemLists(in: &database)
        guard let trackingListID = database.lists.first(where: { $0.systemKind == .tracking })?.id else {
            return 0
        }

        var showIDsByTMDBID: [Int: Set<String>] = [:]
        var showIDsByTitleKey: [String: Set<String>] = [:]
        for show in database.catalog.values where show.kind == .tvShow {
            showIDsByTMDBID[show.tmdbID, default: []].insert(show.id)
            let key = MediaSeriesOrganizer.showKey(forTitle: show.title)
            showIDsByTitleKey[key, default: []].insert(show.id)
        }

        func rememberShowIndex(_ show: CatalogEntry) {
            showIDsByTMDBID[show.tmdbID, default: []].insert(show.id)
            let key = MediaSeriesOrganizer.showKey(forTitle: show.title)
            showIDsByTitleKey[key, default: []].insert(show.id)
        }

        var titleMatchCache: [String: Set<String>] = [:]
        func titleMatchedShowIDs(for episode: CatalogEntry) -> Set<String> {
            let episodeTitleKey = MediaSeriesOrganizer.showKey(forTitle: episode.title)
            if let cached = titleMatchCache[episodeTitleKey] {
                return cached
            }

            let matches = showIDsByTitleKey[episodeTitleKey] ?? []
            titleMatchCache[episodeTitleKey] = matches
            return matches
        }

        var repaired = 0
        var fullEpisodeWatches: [(showID: String, watchedAt: Date)] = []
        for activity in database.activities {
            guard activity.completion == .full,
                  let episode = database.catalog[activity.targetID],
                  episode.kind == .episode else {
                continue
            }

            var showIDs = Set<String>()
            if let showID = episode.parentShowID,
               database.catalog[showID]?.kind == .tvShow {
                showIDs.insert(showID)
            }

            for showID in showIDsByTMDBID[episode.tmdbID, default: []] {
                showIDs.insert(showID)
            }

            if showIDs.isEmpty, episode.parentShowID == nil, episode.tmdbID <= 0 {
                for showID in titleMatchedShowIDs(for: episode) {
                    showIDs.insert(showID)
                }
            }

            let tmdbShowID = CatalogEntry.showID(episode.tmdbID)
            if showIDs.isEmpty, episode.tmdbID > 0 {
                let show = CatalogEntry(
                    id: tmdbShowID,
                    kind: .tvShow,
                    tmdbID: episode.tmdbID,
                    title: episode.title,
                    runtimeMinutes: episode.runtimeMinutes,
                    cachedAt: episode.cachedAt
                )
                database.catalog[tmdbShowID] = show
                rememberShowIndex(show)
                showIDs.insert(tmdbShowID)
                repaired += 1
            }

            if let canonicalShowID = showIDs.sorted().first,
               database.catalog[activity.targetID]?.parentShowID == nil {
                database.catalog[activity.targetID]?.parentShowID = canonicalShowID
                repaired += 1
            }

            for showID in showIDs {
                fullEpisodeWatches.append((showID, activity.watchedAt))
            }
        }

        var latestWatchByShow: [String: Date] = [:]
        for watch in fullEpisodeWatches {
            latestWatchByShow[watch.showID] = max(latestWatchByShow[watch.showID] ?? watch.watchedAt, watch.watchedAt)
        }

        let trackedIDs = Set(database.trackedShows.map(\.targetID))
        for (showID, latestWatch) in latestWatchByShow where !trackedIDs.contains(showID) {
            database.trackedShows.append(TrackedShow(targetID: showID, trackedAt: latestWatch, status: .watching))
            repaired += 1
        }

        for showID in latestWatchByShow.keys {
            if !database.listItems.contains(where: { $0.listID == trackingListID && $0.targetID == showID }) {
                database.listItems.append(PlaybillListItem(listID: trackingListID, targetID: showID))
                repaired += 1
            }

            if let index = database.trackedShows.firstIndex(where: { $0.targetID == showID }),
               database.trackedShows[index].status == .planToWatch {
                database.trackedShows[index].status = .watching
                repaired += 1
            }

            if let watchlistID = database.lists.first(where: { $0.systemKind == .watchlist })?.id {
                let oldCount = database.listItems.count
                database.listItems.removeAll { $0.listID == watchlistID && $0.targetID == showID }
                if database.listItems.count != oldCount {
                    repaired += 1
                }
            }

            if let show = database.catalog[showID], show.kind == .tvShow {
                let showKey = MediaSeriesOrganizer.showKey(forTitle: show.title)
                if !database.showMemories.contains(where: { $0.showKey == showKey }) {
                    database.showMemories.append(ShowMatchMemory(
                        showKey: showKey,
                        tmdbShowID: show.tmdbID,
                        showTargetID: show.id,
                        confirmedAt: latestWatchByShow[showID] ?? Date()
                    ))
                    repaired += 1
                }
            }
        }

        return repaired
    }

    @discardableResult
    private static func repairTrackedShowStatuses(in database: inout PlaybillDatabase) -> Int {
        var repaired = 0
        for index in database.trackedShows.indices {
            let targetID = database.trackedShows[index].targetID
            guard let show = database.catalog[targetID], show.kind == .tvShow else { continue }
            let watched = watchedEpisodeCount(forShowTargetID: targetID, tmdbID: show.tmdbID, in: database)
            guard watched > 0 else { continue }

            if database.trackedShows[index].status == .planToWatch {
                database.trackedShows[index].status = .watching
                repaired += 1
            }

            let required = requiredEpisodeCountForCompletion(show: show, in: database)
            if database.trackedShows[index].status == .completed {
                let shouldDemote = !seriesIsEffectivelyFinished(show, in: database)
                    || required == 0
                    || watched < required
                if shouldDemote {
                    database.trackedShows[index].status = .watching
                    repaired += 1
                }
            } else if required > 0,
                      watched >= required,
                      seriesIsEffectivelyFinished(show, in: database),
                      database.trackedShows[index].status != .completed {
                database.trackedShows[index].status = .completed
                repaired += 1
            }
        }
        return repaired
    }

    private static func showHasEnded(_ show: CatalogEntry) -> Bool {
        let normalized = show.seriesStatus?.lowercased() ?? ""
        return normalized == "ended"
            || normalized == "canceled"
            || (show.seriesInProduction == false && show.nextEpisodeAirDate == nil)
    }

    /// TMDB occasionally leaves a completed series as "Returning Series" for
    /// years. Treat it as finished only when there is no announced next episode
    /// and the newest known episode is at least two years old. The watched-total
    /// guard is applied by callers before assigning Completed.
    private static func seriesIsEffectivelyFinished(
        _ show: CatalogEntry,
        in database: PlaybillDatabase,
        relativeTo date: Date = Date()
    ) -> Bool {
        if showHasEnded(show) { return true }
        guard show.nextEpisodeAirDate == nil else { return false }

        let catalogDates = database.catalog.values.compactMap { entry -> Date? in
            guard entry.kind == .episode, Self.episode(entry, belongsTo: show) else { return nil }
            return entry.episodeAirDate
        }
        let snapshotDates = database.showMetadataSnapshots[show.id]?.seasons.flatMap(\.episodes).compactMap(\.airDate) ?? []
        guard let lastAirDate = ([show.lastEpisodeAirDate].compactMap { $0 } + catalogDates + snapshotDates).max() else {
            return false
        }
        guard let staleCutoff = Calendar.current.date(byAdding: .year, value: -2, to: date) else { return false }
        return lastAirDate < staleCutoff
    }

    private static func requiredEpisodeCountForCompletion(show: CatalogEntry, in database: PlaybillDatabase) -> Int {
        var boundaryTotal = 0
        if let lastSeason = show.lastAiredSeasonNumber,
           let lastEpisode = show.lastAiredEpisodeNumber,
           lastSeason > 0,
           lastEpisode > 0 {
            if lastSeason == 1 {
                boundaryTotal = lastEpisode
            } else {
                boundaryTotal = database.showMetadataSnapshots[show.id]?.seasons.reduce(into: 0) { count, season in
                    guard season.seasonNumber > 0 else { return }
                    if season.seasonNumber < lastSeason {
                        count += season.episodeCount
                    } else if season.seasonNumber == lastSeason {
                        count += season.episodeCount > 0 ? min(season.episodeCount, lastEpisode) : lastEpisode
                    }
                } ?? 0
            }
        }

        var datedAiredTotal = 0
        if let snapshot = database.showMetadataSnapshots[show.id] {
            let today = Calendar.current.startOfDay(for: Date())
            datedAiredTotal = snapshot.seasons.reduce(into: 0) { count, season in
                guard season.seasonNumber > 0 else { return }
                count += season.episodes.filter { episode in
                    guard let airDate = episode.airDate else { return false }
                    return Calendar.current.startOfDay(for: airDate) <= today
                }.count
            }
        }

        let knownAiredTotal = max(boundaryTotal, datedAiredTotal)
        if knownAiredTotal > 0 {
            return knownAiredTotal
        }

        if showHasEnded(show) {
            return show.totalEpisodeCount ?? 0
        }

        // Imported catalogs only contain watched episodes — never treat that as the series total.
        return 0
    }

    private static func episodeIsReleased(
        _ episode: CatalogEntry,
        in show: CatalogEntry,
        database: PlaybillDatabase,
        relativeTo date: Date = Date()
    ) -> Bool {
        guard let season = episode.seasonNumber, let number = episode.episodeNumber else { return true }
        if database.activities.contains(where: {
            $0.targetID == episode.id && $0.completion == .full && $0.watchedAt <= date
        }) {
            return true
        }
        let snapshotAirDate = database.showMetadataSnapshots[show.id]?
            .seasons.first(where: { $0.seasonNumber == season })?
            .episodes.first(where: { $0.episodeNumber == number })?
            .airDate
        if let airDate = episode.episodeAirDate ?? snapshotAirDate {
            let calendar = Calendar.current
            return calendar.startOfDay(for: airDate) <= calendar.startOfDay(for: date)
        }
        if let lastSeason = show.lastAiredSeasonNumber, let lastEpisode = show.lastAiredEpisodeNumber {
            return season < lastSeason || (season == lastSeason && number <= lastEpisode)
        }
        return true
    }

    private static func load() -> PlaybillDatabase {
        if let memoryCache { return memoryCache }
        let url = storeURL()
        guard let data = try? Data(contentsOf: url) else {
            var fresh = PlaybillDatabase()
            ensureSystemLists(in: &fresh)
            memoryCache = fresh
            return fresh
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode(PlaybillDatabase.self, from: data) else {
            var fresh = PlaybillDatabase()
            ensureSystemLists(in: &fresh)
            memoryCache = fresh
            return fresh
        }
        var database = decoded
        let needsMigrationRepair = database.version < PlaybillDatabase.currentVersion
        ensureSystemLists(in: &database)
        // Keep first load cheap — heavy snapshot prune belongs in explicit repair, not every decode.
        let repaired = repairWatchedSeriesTracking(in: &database) + repairTrackedShowStatuses(in: &database)
        database.version = PlaybillDatabase.currentVersion
        memoryCache = database
        if needsMigrationRepair || repaired > 0 {
            save(database, invalidateDerivedCaches: false)
        }
        if !database.pendingWatchResolutions.isEmpty {
            _ = PlaybillConnectivity.shared
        }
        return database
    }

    private static func save(
        _ database: PlaybillDatabase,
        invalidateDerivedCaches: Bool = true,
        pruneWatchlist: Bool = true
    ) {
        var database = database
        ensureSystemLists(in: &database)
        if pruneWatchlist {
            _ = pruneStaleWatchlistItems(in: &database)
        }
        memoryCache = database
        let url = storeURL()
        let encoder = JSONEncoder()
        // Avoid sortedKeys — catastrophic on large Trakt-imported catalogs.
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(database) else { return }
        try? data.write(to: url, options: .atomic)
        if invalidateDerivedCaches {
            PlaybillShowProgress.invalidateWatchedEpisodeCache()
            PlaybillShowFeedBuilder.invalidateRecentWatchedEpisodeCache()
        }
    }

    @discardableResult
    private static func pruneStaleWatchlistItems(in database: inout PlaybillDatabase) -> Int {
        guard let watchlistID = database.lists.first(where: { $0.systemKind == .watchlist })?.id else {
            return 0
        }

        let trackedStatuses = Dictionary(uniqueKeysWithValues: database.trackedShows.map { ($0.targetID, $0.status) })
        let watchedTargetIDs = Set(database.activities.filter { $0.completion == .full }.map(\.targetID))
        let watchedShowIDs = Set(database.activities.compactMap { activity -> String? in
            guard activity.completion == .full,
                  let entry = database.catalog[activity.targetID],
                  entry.kind == .episode else {
                return nil
            }
            return entry.parentShowID ?? CatalogEntry.showID(entry.tmdbID)
        })

        let originalCount = database.listItems.count
        database.listItems.removeAll { item in
            guard item.listID == watchlistID else { return false }
            if watchedTargetIDs.contains(item.targetID) || watchedShowIDs.contains(item.targetID) {
                return true
            }
            if let status = trackedStatuses[item.targetID], status != .planToWatch {
                return true
            }
            return false
        }
        return originalCount - database.listItems.count
    }
}
