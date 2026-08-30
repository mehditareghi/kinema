import Foundation
import KinemaCore
import KinemaMedia

/// Unified watch state for a local media file — Playbill is canonical; progress store holds resume position.
public struct MediaWatchSnapshot: Sendable, Equatable {
    public var isWatched: Bool
    public var watchCount: Int
    public var lastWatchedAt: Date?
    public var targetID: String?
    public var progress: WatchProgressEntry?
    public var playbillProgress: TitlePlaybackProgress?

    public var resumePosition: TimeInterval {
        if let progress, progress.duration > 0, progress.lastPosition > 5 {
            return progress.lastPosition
        }
        return playbillProgress?.position ?? 0
    }

    public var resumeDuration: TimeInterval {
        if let progress, progress.duration > 0 {
            return progress.duration
        }
        return playbillProgress?.duration ?? 0
    }

    public var hasPartialResume: Bool {
        if let progress, progress.duration > 0 {
            return !progress.isMostlyFinished && progress.lastPosition > 5
        }
        return playbillProgress?.hasPartialResume == true
    }

    public static let unwatched = MediaWatchSnapshot(
        isWatched: false,
        watchCount: 0,
        lastWatchedAt: nil,
        targetID: nil,
        progress: nil,
        playbillProgress: nil
    )
}

@MainActor
public enum MediaWatchCoordinator {
    public static func snapshot(for url: URL) -> MediaWatchSnapshot {
        let targetID = PlaybillMatcher.inferredTargetID(for: url)
        var progress = WatchProgressStore.entry(for: url)
        let playbillProgress = targetID.flatMap { PlaybillStore.playbackProgress(for: $0) }

        if progress == nil, let playbillProgress, playbillProgress.hasPartialResume {
            seedFileProgress(from: playbillProgress, url: url)
            progress = WatchProgressStore.entry(for: url)
        }

        var watchCount = 0
        var lastWatchedAt: Date?

        if let targetID {
            watchCount = PlaybillStore.watchCount(for: targetID)
            lastWatchedAt = PlaybillStore.activities(for: targetID).first?.watchedAt
        }

        let progressFinished = progress?.isMostlyFinished == true
        let isWatched = watchCount > 0 || progressFinished
        let resolvedCount = max(watchCount, progressFinished ? 1 : 0)

        return MediaWatchSnapshot(
            isWatched: isWatched,
            watchCount: resolvedCount,
            lastWatchedAt: lastWatchedAt ?? progress?.lastPlayedAt ?? playbillProgress?.updatedAt,
            targetID: targetID,
            progress: progress,
            playbillProgress: playbillProgress
        )
    }

    public static func isWatched(_ url: URL) -> Bool {
        snapshot(for: url).isWatched
    }

    public static func areAllWatched(_ urls: [URL]) -> Bool {
        guard !urls.isEmpty else { return false }
        return urls.allSatisfy { isWatched($0) }
    }

    /// Record in-progress playback to the file store and Playbill (when the title is identifiable).
    public static func recordProgress(
        item: MediaItem,
        position: TimeInterval,
        duration: TimeInterval,
        notify: Bool = true
    ) {
        WatchProgressStore.record(
            item: item,
            position: position,
            duration: duration,
            notify: false
        )

        if let targetID = PlaybillMatcher.inferredTargetID(for: item.url) {
            PlaybillStore.updatePlaybackProgress(
                targetID: targetID,
                position: position,
                duration: duration
            )
        }

        if notify {
            EventBus.shared.emit(.watchProgressUpdated)
        }
    }

    /// Mark watched in both Playbill (when identifiable) and the file progress store.
    public static func markWatched(
        item: MediaItem,
        duration: TimeInterval,
        watchedAt: Date = Date(),
        source: WatchSource
    ) async {
        let resolvedDuration = duration > 0 ? duration : 1
        WatchProgressStore.markWatched(item: item, duration: resolvedDuration)

        if let targetID = PlaybillMatcher.inferredTargetID(for: item.url) {
            PlaybillStore.clearPlaybackProgress(for: targetID)
        }

        await PlaybillScrobbler.logExplicitFinish(
            item: item,
            position: resolvedDuration,
            duration: resolvedDuration,
            source: source
        )
        EventBus.shared.emit(.watchProgressUpdated)
        EventBus.shared.emit(.playbillUpdated)
    }

    public static func markUnwatched(url: URL) {
        WatchProgressStore.clearProgress(for: url)
        if let targetID = PlaybillMatcher.inferredTargetID(for: url) {
            PlaybillStore.clearWatches(for: targetID)
            clearProgressForLinkedMedia(targetID: targetID, excluding: url)
        }
        EventBus.shared.emit(.watchProgressUpdated)
        EventBus.shared.emit(.playbillUpdated)
    }

    public static func markAllWatched(_ urls: [URL], watchedAt: Date = Date()) {
        guard !urls.isEmpty else { return }
        WatchProgressStore.markAllWatched(urls)
        Task {
            for url in urls {
                let item = MediaItem(url: url)
                let duration = WatchProgressStore.entry(for: url)?.duration ?? 1
                if let targetID = PlaybillMatcher.inferredTargetID(for: url) {
                    PlaybillStore.clearPlaybackProgress(for: targetID)
                }
                await logPlaybillWatch(for: item, watchedAt: watchedAt, source: .manual, watchedSeconds: duration)
            }
            EventBus.shared.emit(.watchProgressUpdated)
            EventBus.shared.emit(.playbillUpdated)
        }
    }

    public static func markAllUnwatched(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        WatchProgressStore.markAllUnwatched(urls)
        var clearedTargets = Set<String>()
        for url in urls {
            if let targetID = PlaybillMatcher.inferredTargetID(for: url),
               clearedTargets.insert(targetID).inserted {
                PlaybillStore.clearWatches(for: targetID)
            }
        }
        EventBus.shared.emit(.watchProgressUpdated)
        EventBus.shared.emit(.playbillUpdated)
    }

    /// After Playbill logs a player watch, mirror completion into the file progress store.
    public static func syncFileProgressAfterPlaybillWatch(
        url: URL,
        title: String,
        duration: TimeInterval,
        watchedAt: Date = Date()
    ) {
        let resolvedDuration = duration > 0 ? duration : 1
        WatchProgressStore.markWatched(
            item: MediaItem(url: url, title: title),
            duration: resolvedDuration
        )
        if let targetID = PlaybillMatcher.inferredTargetID(for: url) {
            PlaybillStore.clearPlaybackProgress(for: targetID)
        }
        EventBus.shared.emit(.watchProgressUpdated)
    }

    public static func syncAfterPlaybillActivityChange(targetID: String) {
        let count = PlaybillStore.watchCount(for: targetID)
        if count == 0 {
            if PlaybillStore.playbackProgress(for: targetID) == nil {
                clearProgressForLinkedMedia(targetID: targetID, excluding: nil)
            }
        } else {
            mirrorPlaybillCompletionToLinkedFiles(targetID: targetID)
        }
        EventBus.shared.emit(.watchProgressUpdated)
    }

    /// Apply Playbill title progress to a newly discovered local file.
    public static func applyPlaybillProgress(to url: URL, targetID: String) {
        guard let playbillProgress = PlaybillStore.playbackProgress(for: targetID),
              playbillProgress.hasPartialResume else { return }
        seedFileProgress(from: playbillProgress, url: url)
    }

    /// Copy an existing file's resume position into Playbill when a link is created.
    public static func backfillPlaybillProgress(forMediaID mediaID: String, targetID: String) {
        if let entry = WatchProgressStore.entry(forMediaID: mediaID),
           entry.lastPosition > 5,
           !entry.isMostlyFinished {
            PlaybillStore.updatePlaybackProgress(
                targetID: targetID,
                position: entry.lastPosition,
                duration: entry.duration
            )
            return
        }
        if let url = PlaybackHistoryEntry.recoverFileURL(fromStoredPathOrURL: mediaID),
           let entry = WatchProgressStore.entry(for: url),
           entry.lastPosition > 5,
           !entry.isMostlyFinished {
            PlaybillStore.updatePlaybackProgress(
                targetID: targetID,
                position: entry.lastPosition,
                duration: entry.duration
            )
        }
    }

    private static func seedFileProgress(from playbill: TitlePlaybackProgress, url: URL) {
        guard WatchProgressStore.entry(for: url) == nil else { return }
        WatchProgressStore.record(
            item: MediaItem(url: url),
            position: playbill.position,
            duration: playbill.duration,
            notify: false
        )
    }

    private static func mirrorPlaybillCompletionToLinkedFiles(targetID: String) {
        for link in PlaybillStore.mediaLinks(for: targetID) {
            guard let entry = WatchProgressStore.entry(forMediaID: link.mediaID),
                  let url = entry.url,
                  !entry.isMostlyFinished else { continue }
            let duration = entry.duration > 0 ? entry.duration : 1
            WatchProgressStore.markWatched(
                item: MediaItem(url: url, title: entry.title),
                duration: duration
            )
        }
    }

    private static func logPlaybillWatch(
        for item: MediaItem,
        watchedAt: Date,
        source: WatchSource,
        watchedSeconds: TimeInterval
    ) async {
        switch await PlaybillMatcher.scrobbleResolution(for: item.url, title: item.title) {
        case .autoLogged(let targetID):
            _ = PlaybillStore.logWatch(
                targetID: targetID,
                watchedAt: watchedAt,
                source: source,
                watchedSeconds: watchedSeconds
            )

        case .needsConfirmation(let candidates):
            let pending = PlaybillStore.enqueuePendingWatch(
                mediaID: WatchProgressStore.mediaID(for: item.url),
                mediaURL: item.url,
                mediaTitle: item.title,
                watchedAt: watchedAt,
                source: source,
                watchedSeconds: watchedSeconds
            )
            PlaybillPromptCenter.shared.present(PlaybillMatchPrompt(
                mediaURL: item.url,
                mediaTitle: item.title,
                candidates: candidates,
                watchedSeconds: watchedSeconds,
                sessionKey: "pending-\(pending.id.uuidString)",
                watchedAt: watchedAt,
                pendingResolutionID: pending.id,
                source: source
            ))

        case .noMatch:
            _ = PlaybillStore.enqueuePendingWatch(
                mediaID: WatchProgressStore.mediaID(for: item.url),
                mediaURL: item.url,
                mediaTitle: item.title,
                watchedAt: watchedAt,
                source: source,
                watchedSeconds: watchedSeconds
            )
        }
    }

    private static func clearProgressForLinkedMedia(targetID: String, excluding: URL?) {
        for link in PlaybillStore.mediaLinks(for: targetID) {
            if let entry = WatchProgressStore.entry(forMediaID: link.mediaID),
               let url = entry.url {
                if let excluding, url.standardizedFileURL == excluding.standardizedFileURL { continue }
                WatchProgressStore.clearProgress(for: url)
            }
        }
    }
}
