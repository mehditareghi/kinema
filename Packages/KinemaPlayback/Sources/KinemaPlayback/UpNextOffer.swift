import Foundation
import KinemaCore
import KinemaMedia

/// Pending end-of-episode offer before advancing the lineup.
public struct UpNextOffer: Equatable, Identifiable, Sendable {
    public static let defaultCountdown: TimeInterval = 8
    /// Show the card this many seconds before EOF (credits window).
    public static let creditsLeadIn: TimeInterval = 25
    /// Don't float a credits card on very short clips.
    public static let minimumDurationForCreditsLeadIn: TimeInterval = 30

    public var id: String { item.id.uuidString }
    public let item: MediaItem
    /// Set when the next title is a parsed series episode; otherwise a generic lineup advance.
    public let episode: MediaEpisodeIdentity?
    public let countdownSeconds: TimeInterval
    /// Playlist index to load when confirming (may skip unrelated items).
    public let playlistIndex: Int

    public var showTitle: String {
        episode?.showTitle ?? item.title
    }

    public var detailLabel: String {
        if let episode {
            return episode.seasonEpisodeCode
        }
        return item.title
    }

    public var osdLabel: String {
        episode?.displayLabel ?? item.title
    }

    public init(
        item: MediaItem,
        episode: MediaEpisodeIdentity?,
        playlistIndex: Int,
        countdownSeconds: TimeInterval = Self.defaultCountdown
    ) {
        self.item = item
        self.episode = episode
        self.playlistIndex = playlistIndex
        self.countdownSeconds = max(3, countdownSeconds)
    }
}
