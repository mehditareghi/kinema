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
        db.trackedShows.removeAll { $0.targetID == targetID }
        let tracked = TrackedShow(targetID: targetID, status: status)
        db.trackedShows.append(tracked)
        if let trackingListID = db.lists.first(where: { $0.systemKind == .tracking })?.id {
            db.listItems.removeAll { $0.listID == trackingListID && $0.targetID == targetID }
            db.listItems.append(PlaybillListItem(listID: trackingListID, targetID: targetID))
        }
        if status == .planToWatch,
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

    public static func updateTrackedShowStatus(targetID: String, status: TrackedShowStatus) {
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
        save(db)
        EventBus.shared.emit(.playbillUpdated)
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

    public static func updateActivity(id: UUID, watchedAt: Date) {
        var db = load()
        guard let index = db.activities.firstIndex(where: { $0.id == id }) else { return }
        db.activities[index].watchedAt = watchedAt
        let targetID = db.activities[index].targetID
        save(db)
        EventBus.shared.emit(.playbillUpdated)
        MediaWatchCoordinator.syncAfterPlaybillActivityChange(targetID: targetID)
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
        db.catalog[entry.id] = entry
        save(db)
        return entry
    }

    @discardableResult
    public static func logWatch(
        targetID: String,
        watchedAt: Date = Date(),
        source: WatchSource,
        completion: WatchCompletion = .full,
        watchedSeconds: TimeInterval? = nil
    ) -> WatchActivity? {
        var db = load()
        guard let entry = db.catalog[targetID] else { return nil }
        guard entry.kind != .tvShow else { return nil }

        // Avoid duplicate player scrobbles within the same minute for the same title.
        if source == .player, completion == .full {
            let recentCutoff = watchedAt.addingTimeInterval(-60)
            if db.activities.contains(where: {
                $0.targetID == targetID &&
                $0.source == .player &&
                $0.completion == .full &&
                $0.watchedAt >= recentCutoff
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
        guard !targetIDs.isEmpty else { return 0 }

        var db = load()
        var logged = 0
        var loggedIDs: [String] = []

        for targetID in targetIDs {
            guard let entry = db.catalog[targetID], entry.kind != .tvShow else { continue }
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

    public static func removeActivity(id: UUID) {
        var db = load()
        guard let removed = db.activities.first(where: { $0.id == id }) else { return }
        let original = db.activities.count
        db.activities.removeAll { $0.id == id }
        guard db.activities.count != original else { return }
        save(db)
        EventBus.shared.emit(.playbillUpdated)
        MediaWatchCoordinator.syncAfterPlaybillActivityChange(targetID: removed.targetID)
    }

    public static func clearWatches(for targetID: String) {
        var db = load()
        let hadActivities = db.activities.contains { $0.targetID == targetID }
        let hadProgress = db.playbackProgress[targetID] != nil
        guard hadActivities || hadProgress else { return }

        db.activities.removeAll { $0.targetID == targetID }
        db.playbackProgress.removeValue(forKey: targetID)
        save(db)
        EventBus.shared.emit(.playbillUpdated)
        MediaWatchCoordinator.syncAfterPlaybillActivityChange(targetID: targetID)
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
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
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
        ensureSystemLists(in: &database)
        if database.version < PlaybillDatabase.currentVersion {
            database.version = PlaybillDatabase.currentVersion
        }
        memoryCache = database
        if !database.pendingWatchResolutions.isEmpty {
            _ = PlaybillConnectivity.shared
        }
        return database
    }

    private static func save(_ database: PlaybillDatabase) {
        var database = database
        ensureSystemLists(in: &database)
        memoryCache = database
        let url = storeURL()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(database) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
