import Foundation
import KinemaCore

@MainActor
public enum PendingWatchResolver {
    public static func retryAll() async {
        guard PlaybillPreferencesStore.isConfigured else { return }
        for pending in PlaybillStore.pendingWatchResolutions() {
            guard !Task.isCancelled else { return }
            let result = await retry(pending)
            if result == .needsConfirmation {
                // Present one decision at a time; remaining records stay durable.
                return
            }
        }
    }

    @discardableResult
    public static func retry(_ pending: PendingWatchResolution) async -> PendingWatchRetryResult {
        guard let url = URL(string: pending.mediaLocation) else {
            PlaybillStore.updatePendingWatchAttempt(id: pending.id, error: "The original media location is unavailable.")
            return .unresolved
        }

        switch await PlaybillMatcher.scrobbleResolution(for: url, title: pending.mediaTitle) {
        case .autoLogged(let targetID):
            _ = PlaybillStore.logWatch(
                targetID: targetID,
                watchedAt: pending.watchedAt,
                source: pending.source,
                watchedSeconds: pending.watchedSeconds
            )
            PlaybillStore.removePendingWatch(id: pending.id)
            return .resolved

        case .needsConfirmation(let candidates):
            PlaybillStore.updatePendingWatchAttempt(id: pending.id, error: "Choose the matching title to finish identification.")
            PlaybillPromptCenter.shared.present(PlaybillMatchPrompt(
                mediaURL: url,
                mediaTitle: pending.mediaTitle,
                candidates: candidates,
                watchedSeconds: pending.watchedSeconds,
                sessionKey: "pending-\(pending.id.uuidString)",
                watchedAt: pending.watchedAt,
                pendingResolutionID: pending.id,
                source: pending.source
            ))
            return .needsConfirmation

        case .noMatch:
            let message = PlaybillConnectivity.shared.isOnline
                ? "No confident title match was found."
                : "Connect to identify this watch."
            PlaybillStore.updatePendingWatchAttempt(id: pending.id, error: message)
            return .unresolved
        }
    }
}

public enum PendingWatchRetryResult: Sendable, Equatable {
    case resolved
    case needsConfirmation
    case unresolved
}
