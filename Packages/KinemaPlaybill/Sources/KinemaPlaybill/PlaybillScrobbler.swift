import Foundation
import KinemaCore

@MainActor
public enum PlaybillScrobbler {
    private static var scrobbledSessionKeys = Set<String>()
    private static var declinedSessionKeys = Set<String>()
    private static var pendingPromptSessionKeys = Set<String>()
    private static var preparedSessionKeys = Set<String>()

    public static func resetSession(for url: URL) {
        let mediaID = WatchProgressStore.mediaID(for: url)
        scrobbledSessionKeys = scrobbledSessionKeys.filter { !$0.hasPrefix("\(mediaID)-") }
        declinedSessionKeys = declinedSessionKeys.filter { !$0.hasPrefix("\(mediaID)-") }
        pendingPromptSessionKeys = pendingPromptSessionKeys.filter { !$0.hasPrefix("\(mediaID)-") }
        preparedSessionKeys = preparedSessionKeys.filter { !$0.hasPrefix("\(mediaID)-") }
    }

    /// Identify a newly played title as soon as playback is established, rather than
    /// waiting until it is complete. Confident matches are added automatically;
    /// ambiguous matches ask once at playback start.
    public static func preparePlayback(
        item: MediaItem,
        position: TimeInterval,
        duration: TimeInterval
    ) async {
        guard PlaybillPreferencesStore.autoScrobbleEnabled else { return }
        if item.url.isFileURL == false, !PlaybillPreferencesStore.scrobbleStreams {
            return
        }
        guard position > 5 else { return }

        let sessionKey = sessionKey(for: item.url, duration: duration)
        guard preparedSessionKeys.insert(sessionKey).inserted else { return }

        switch await PlaybillMatcher.scrobbleResolution(
            for: item.url,
            title: item.title
        ) {
        case .autoLogged(let targetID):
            PlaybillStore.beginPlayback(
                targetID: targetID,
                position: position,
                duration: duration
            )
        case .needsConfirmation(let candidates):
            pendingPromptSessionKeys.insert(sessionKey)
            PlaybillPromptCenter.shared.present(PlaybillMatchPrompt(
                mediaURL: item.url,
                mediaTitle: item.title,
                candidates: candidates,
                watchedSeconds: position,
                sessionKey: sessionKey,
                purpose: .identifyPlayback
            ))
        case .noMatch:
            break
        }
    }

    public static func evaluate(item: MediaItem, position: TimeInterval, duration: TimeInterval) async {
        guard PlaybillPreferencesStore.autoScrobbleEnabled else { return }

        if item.url.isFileURL == false, !PlaybillPreferencesStore.scrobbleStreams {
            return
        }

        guard duration > 0 else { return }
        let progress = position / duration
        let threshold = PlaybillPreferencesStore.completionThreshold

        guard progress >= threshold else { return }

        let sessionKey = sessionKey(for: item.url, duration: duration)
        guard !scrobbledSessionKeys.contains(sessionKey) else { return }
        guard !declinedSessionKeys.contains(sessionKey) else { return }
        guard !pendingPromptSessionKeys.contains(sessionKey) else { return }

        let watchedSeconds = max(position, duration * threshold)

        switch await PlaybillMatcher.scrobbleResolution(for: item.url, title: item.title) {
        case .autoLogged(let targetID):
            scrobbledSessionKeys.insert(sessionKey)
            if PlaybillStore.logWatch(
                targetID: targetID,
                source: .player,
                completion: .full,
                watchedSeconds: watchedSeconds
            ) != nil {
                MediaWatchCoordinator.syncFileProgressAfterPlaybillWatch(
                    url: item.url,
                    title: item.title,
                    duration: duration
                )
            }

        case .needsConfirmation(let candidates):
            pendingPromptSessionKeys.insert(sessionKey)
            let pending = PlaybillStore.enqueuePendingWatch(
                mediaID: WatchProgressStore.mediaID(for: item.url),
                mediaURL: item.url,
                mediaTitle: item.title,
                watchedAt: Date(),
                source: .player,
                watchedSeconds: watchedSeconds
            )
            PlaybillPromptCenter.shared.present(
                PlaybillMatchPrompt(
                    mediaURL: item.url,
                    mediaTitle: item.title,
                    candidates: candidates,
                    watchedSeconds: watchedSeconds,
                    sessionKey: sessionKey,
                    pendingResolutionID: pending.id
                )
            )

        case .noMatch:
            _ = PlaybillStore.enqueuePendingWatch(
                mediaID: WatchProgressStore.mediaID(for: item.url),
                mediaURL: item.url,
                mediaTitle: item.title,
                watchedAt: Date(),
                source: .player,
                watchedSeconds: watchedSeconds
            )
            scrobbledSessionKeys.insert(sessionKey)
        }
    }

    /// Log a completed watch when the user finishes via Up Next, EOF, or manual mark.
    /// Ignores the completion threshold — skipping ahead during credits still counts.
    public static func logExplicitFinish(
        item: MediaItem,
        position: TimeInterval,
        duration: TimeInterval,
        source: WatchSource = .player
    ) async {
        if source == .player {
            guard PlaybillPreferencesStore.autoScrobbleEnabled else { return }
        }

        if item.url.isFileURL == false, !PlaybillPreferencesStore.scrobbleStreams {
            return
        }

        guard duration > 0 else { return }

        let sessionKey = sessionKey(for: item.url, duration: duration)
        guard !scrobbledSessionKeys.contains(sessionKey) else { return }

        let watchedSeconds = max(position, duration)

        switch await PlaybillMatcher.scrobbleResolution(for: item.url, title: item.title) {
        case .autoLogged(let targetID):
            scrobbledSessionKeys.insert(sessionKey)
            if PlaybillStore.logWatch(
                targetID: targetID,
                source: source,
                completion: .full,
                watchedSeconds: watchedSeconds
            ) != nil {
                MediaWatchCoordinator.syncFileProgressAfterPlaybillWatch(
                    url: item.url,
                    title: item.title,
                    duration: duration
                )
            }

        case .needsConfirmation(let candidates):
            scrobbledSessionKeys.insert(sessionKey)
            let pending = PlaybillStore.enqueuePendingWatch(
                mediaID: WatchProgressStore.mediaID(for: item.url),
                mediaURL: item.url,
                mediaTitle: item.title,
                watchedAt: Date(),
                source: source,
                watchedSeconds: watchedSeconds
            )
            PlaybillPromptCenter.shared.present(PlaybillMatchPrompt(
                mediaURL: item.url,
                mediaTitle: item.title,
                candidates: candidates,
                watchedSeconds: watchedSeconds,
                sessionKey: sessionKey,
                pendingResolutionID: pending.id,
                source: source
            ))

        case .noMatch:
            _ = PlaybillStore.enqueuePendingWatch(
                mediaID: WatchProgressStore.mediaID(for: item.url),
                mediaURL: item.url,
                mediaTitle: item.title,
                watchedAt: Date(),
                source: source,
                watchedSeconds: watchedSeconds
            )
            scrobbledSessionKeys.insert(sessionKey)
        }
    }

    public static func confirm(_ prompt: PlaybillMatchPrompt, candidate: PlaybillMatchCandidate) async {
        defer {
            pendingPromptSessionKeys.remove(prompt.sessionKey)
            PlaybillPromptCenter.shared.clear()
        }

        do {
            let entry = try await PlaybillMatcher.confirmCandidate(url: prompt.mediaURL, candidate: candidate)
            switch prompt.purpose {
            case .identifyPlayback:
                PlaybillStore.beginPlayback(
                    targetID: entry.id,
                    position: prompt.watchedSeconds,
                    duration: WatchProgressStore.entry(for: prompt.mediaURL)?.duration ?? 0
                )
            case .logCompletedWatch:
                scrobbledSessionKeys.insert(prompt.sessionKey)
                if PlaybillStore.logWatch(
                    targetID: entry.id,
                    watchedAt: prompt.watchedAt,
                    source: prompt.source,
                    completion: .full,
                    watchedSeconds: prompt.watchedSeconds
                ) != nil {
                    MediaWatchCoordinator.syncFileProgressAfterPlaybillWatch(
                        url: prompt.mediaURL,
                        title: prompt.mediaTitle,
                        duration: prompt.watchedSeconds
                    )
                }
            }
            if let pendingID = prompt.pendingResolutionID {
                PlaybillStore.removePendingWatch(id: pendingID)
            }
        } catch {
            if let pendingID = prompt.pendingResolutionID {
                PlaybillStore.updatePendingWatchAttempt(id: pendingID, error: error.localizedDescription)
            } else if prompt.purpose == .logCompletedWatch {
                scrobbledSessionKeys.insert(prompt.sessionKey)
            }
        }
    }

    public static func decline(_ prompt: PlaybillMatchPrompt) {
        pendingPromptSessionKeys.remove(prompt.sessionKey)
        declinedSessionKeys.insert(prompt.sessionKey)
        if let pendingID = prompt.pendingResolutionID {
            PlaybillStore.updatePendingWatchAttempt(
                id: pendingID,
                error: "Identification was postponed."
            )
        }
        PlaybillPromptCenter.shared.clear()
    }

    public static func logManual(
        result: PlaybillSearchResult,
        watchedAt: Date = Date()
    ) async throws {
        let entry = try await TMDBClient.catalogEntry(from: result)
        _ = PlaybillStore.upsertCatalog(entry)
        _ = PlaybillStore.logWatch(targetID: entry.id, watchedAt: watchedAt, source: .manual)
    }

    private static func sessionKey(for url: URL, duration: TimeInterval) -> String {
        "\(WatchProgressStore.mediaID(for: url))-\(Int(duration))"
    }
}
