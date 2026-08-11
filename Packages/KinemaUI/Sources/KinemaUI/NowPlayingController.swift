import Foundation
import MediaPlayer
import KinemaCore
import KinemaMedia
import KinemaPlayback
#if os(iOS) || os(tvOS)
import AVFoundation
#endif
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Keeps system Now Playing / Lock Screen / Control Center in sync with `PlayerSession`.
@MainActor
final class NowPlayingController {
    static let shared = NowPlayingController()

    private weak var session: PlayerSession?
    private var didConfigureCommands = false
    private var isActive = false
    private var artworkToken: String?
    private var artworkLoadTask: Task<Void, Never>?
    private var lastPublishedElapsed: TimeInterval = -1
    private var lastPublishedDuration: TimeInterval = -1
    private var lastPublishedRate: Double = -1
    private var lastPublishedTitle: String = ""
    private var lastPublishedArtist: String = ""
    private var lastPublishedAlbum: String = ""

    private let seekStep: TimeInterval = 10

    private init() {}

    func attach(session: PlayerSession) {
        self.session = session
        configureRemoteCommandsIfNeeded()
    }

    func activate(for item: MediaItem) {
        configureRemoteCommandsIfNeeded()
        isActive = true
        setRemoteCommandsEnabled(true)
        activateAudioSessionIfNeeded()

        artworkToken = nil
        artworkLoadTask?.cancel()
        lastPublishedElapsed = -1
        lastPublishedDuration = -1
        lastPublishedRate = -1
        lastPublishedTitle = ""
        lastPublishedArtist = ""
        lastPublishedAlbum = ""

        publish(force: true)
        refreshArtwork(for: item.url)
        refreshTrackCommandAvailability()
    }

    func handlePlaybackUpdate() {
        guard isActive else { return }
        publish(force: false)
        refreshTrackCommandAvailability()
    }

    func handleStateChange() {
        guard isActive else { return }
        publish(force: true)
        refreshTrackCommandAvailability()
    }

    func deactivate() {
        guard isActive || didConfigureCommands else {
            clearNowPlayingInfo()
            return
        }
        isActive = false
        artworkLoadTask?.cancel()
        artworkLoadTask = nil
        artworkToken = nil
        setRemoteCommandsEnabled(false)
        clearNowPlayingInfo()
        deactivateAudioSessionIfNeeded()
    }

    // MARK: - Publish

    private func publish(force: Bool) {
        guard isActive, let session else {
            clearNowPlayingInfo()
            return
        }
        guard session.state.isActive, session.currentItem != nil else {
            clearNowPlayingInfo()
            return
        }

        let info = session.info
        let title = displayTitle(for: session)
        let subtitle = displaySubtitle(for: session)
        let rate = session.state == .playing ? max(info.speed, 0.01) : 0
        let elapsed = max(0, info.position)
        let duration = max(0, info.duration)

        let elapsedChanged = abs(elapsed - lastPublishedElapsed) >= 0.45
        let durationChanged = abs(duration - lastPublishedDuration) >= 0.25
        let rateChanged = abs(rate - lastPublishedRate) >= 0.01
        let titleChanged = title != lastPublishedTitle
        let artistChanged = subtitle.artist != lastPublishedArtist
        let albumChanged = subtitle.album != lastPublishedAlbum
        guard force || elapsedChanged || durationChanged || rateChanged || titleChanged
            || artistChanged || albumChanged else { return }

        var nowPlaying: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyPlaybackRate: rate,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: info.speed,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue
        ]

        if let artist = subtitle.artist {
            nowPlaying[MPMediaItemPropertyArtist] = artist
        }
        if let album = subtitle.album {
            nowPlaying[MPMediaItemPropertyAlbumTitle] = album
        }

        if let existing = MPNowPlayingInfoCenter.default().nowPlayingInfo,
           let artwork = existing[MPMediaItemPropertyArtwork] {
            nowPlaying[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlaying
        lastPublishedElapsed = elapsed
        lastPublishedDuration = duration
        lastPublishedRate = rate
        lastPublishedTitle = title
        lastPublishedArtist = subtitle.artist ?? ""
        lastPublishedAlbum = subtitle.album ?? ""
    }

    private func displayTitle(for session: PlayerSession) -> String {
        if let itemTitle = session.currentItem?.title.trimmingCharacters(in: .whitespacesAndNewlines),
           !itemTitle.isEmpty {
            return itemTitle
        }
        let infoTitle = session.info.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return infoTitle.isEmpty ? "Kinema" : infoTitle
    }

    /// Lock Screen second line: chapter when present, else SxxExx / show.
    private func displaySubtitle(for session: PlayerSession) -> (artist: String?, album: String?) {
        let episode = session.currentItem.flatMap { MediaSeriesOrganizer.episodeIdentity(from: $0.url) }
        let chapterTitle = session.currentChapter?.displayTitle
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let chapterTitle, !chapterTitle.isEmpty {
            let album = episode.map { "\($0.showTitle) · \($0.seasonEpisodeCode)" }
            return (chapterTitle, album)
        }

        if let episode {
            return (episode.seasonEpisodeCode, episode.showTitle)
        }

        return (nil, nil)
    }

    private func clearNowPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        lastPublishedElapsed = -1
        lastPublishedDuration = -1
        lastPublishedRate = -1
        lastPublishedTitle = ""
        lastPublishedArtist = ""
        lastPublishedAlbum = ""
    }

    // MARK: - Artwork

    private func refreshArtwork(for url: URL) {
        let token = url.path
        artworkToken = token
        artworkLoadTask?.cancel()

        // Prefer embedded/sidecar cover; fall back to library poster cache / generate.
        artworkLoadTask = Task { [weak self] in
            if let cover = await MediaCoverArt.loadImage(for: url) {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, self.artworkToken == token else { return }
                    self.applyArtwork(Self.makePlatformImage(from: cover), token: token)
                }
                return
            }

            if let cached = VideoThumbnailLoader.cachedPreview(for: url)?.image {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, self.artworkToken == token else { return }
                    self.applyArtwork(cached, token: token)
                }
                return
            }

            let progress = WatchProgressStore.entry(for: url)
            let time = VideoThumbnailLoader.preferredTime(for: progress)
            let preview = await VideoThumbnailLoader.loadPreview(url: url, at: time, priority: .background)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.artworkToken == token, let image = preview.image else { return }
                self.applyArtwork(image, token: token)
            }
        }
    }

    private func applyArtwork(_ image: PlatformImage, token: String) {
        guard artworkToken == token, isActive else { return }
        let size = artworkSize(for: image)
        let artwork = MPMediaItemArtwork(boundsSize: size) { _ in image }
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyArtwork] = artwork
        // Keep transport fields fresh when art arrives late.
        if let session, session.state.isActive {
            let playback = session.info
            info[MPMediaItemPropertyTitle] = displayTitle(for: session)
            let subtitle = displaySubtitle(for: session)
            if let artist = subtitle.artist {
                info[MPMediaItemPropertyArtist] = artist
            } else {
                info.removeValue(forKey: MPMediaItemPropertyArtist)
            }
            if let album = subtitle.album {
                info[MPMediaItemPropertyAlbumTitle] = album
            } else {
                info.removeValue(forKey: MPMediaItemPropertyAlbumTitle)
            }
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = max(0, playback.position)
            info[MPMediaItemPropertyPlaybackDuration] = max(0, playback.duration)
            info[MPNowPlayingInfoPropertyPlaybackRate] = session.state == .playing ? max(playback.speed, 0.01) : 0
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func artworkSize(for image: PlatformImage) -> CGSize {
        #if os(macOS)
        let size = image.size
        return CGSize(width: max(size.width, 1), height: max(size.height, 1))
        #else
        let size = image.size
        return CGSize(width: max(size.width, 1), height: max(size.height, 1))
        #endif
    }

    private static func makePlatformImage(from cgImage: CGImage) -> PlatformImage {
        #if os(macOS)
        let size = NSSize(width: cgImage.width, height: cgImage.height)
        return NSImage(cgImage: cgImage, size: size)
        #else
        return UIImage(cgImage: cgImage)
        #endif
    }

    // MARK: - Remote commands

    private func configureRemoteCommandsIfNeeded() {
        guard !didConfigureCommands else { return }
        didConfigureCommands = true

        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            self?.performOnSession { $0.play() } ?? .commandFailed
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.performOnSession { $0.pause() } ?? .commandFailed
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.performOnSession { $0.togglePlayPause() } ?? .commandFailed
        }
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: seekStep)]
        center.skipForwardCommand.addTarget { [weak self] _ in
            self?.performOnSession { $0.seekRelative(10) } ?? .commandFailed
        }
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: seekStep)]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            self?.performOnSession { $0.seekRelative(-10) } ?? .commandFailed
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self,
                  let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            return self.performOnSession { session in
                session.seek(to: positionEvent.positionTime)
            }
        }

        center.nextTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            return self.performLineupCommand { session in
                guard session.canPlayNextInLineup else { return .noSuchContent }
                session.playNext(startFromBeginning: true)
                return .success
            }
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            return self.performLineupCommand { session in
                session.playPreviousFromRemote()
                return .success
            }
        }

        center.seekForwardCommand.isEnabled = false
        center.seekBackwardCommand.isEnabled = false

        setRemoteCommandsEnabled(false)
    }

    private func setRemoteCommandsEnabled(_ enabled: Bool) {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = enabled
        center.pauseCommand.isEnabled = enabled
        center.togglePlayPauseCommand.isEnabled = enabled
        center.skipForwardCommand.isEnabled = enabled
        center.skipBackwardCommand.isEnabled = enabled
        center.changePlaybackPositionCommand.isEnabled = enabled
        if enabled {
            refreshTrackCommandAvailability()
        } else {
            center.nextTrackCommand.isEnabled = false
            center.previousTrackCommand.isEnabled = false
        }
    }

    private func refreshTrackCommandAvailability() {
        let center = MPRemoteCommandCenter.shared()
        guard isActive, let session, session.state.isActive else {
            center.nextTrackCommand.isEnabled = false
            center.previousTrackCommand.isEnabled = false
            return
        }
        // Previous stays on so headset users can restart the current title.
        center.nextTrackCommand.isEnabled = session.canPlayNextInLineup
        center.previousTrackCommand.isEnabled = true
    }

    private func performOnSession(_ body: @MainActor (PlayerSession) -> Void) -> MPRemoteCommandHandlerStatus {
        performLineupCommand { session in
            body(session)
            return .success
        }
    }

    private func performLineupCommand(
        _ body: @MainActor (PlayerSession) -> MPRemoteCommandHandlerStatus
    ) -> MPRemoteCommandHandlerStatus {
        if Thread.isMainThread {
            guard isActive, let session else { return .noActionableNowPlayingItem }
            let status = body(session)
            publish(force: true)
            refreshTrackCommandAvailability()
            return status
        }
        var status: MPRemoteCommandHandlerStatus = .commandFailed
        DispatchQueue.main.sync {
            guard isActive, let session else {
                status = .noActionableNowPlayingItem
                return
            }
            status = body(session)
            publish(force: true)
            refreshTrackCommandAvailability()
        }
        return status
    }

    // MARK: - Audio session

    private func activateAudioSessionIfNeeded() {
        #if os(iOS) || os(tvOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true)
        } catch {
            NSLog("Kinema: AVAudioSession activate failed: \(error.localizedDescription)")
        }
        #endif
    }

    private func deactivateAudioSessionIfNeeded() {
        #if os(iOS) || os(tvOS)
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // Leaving player while another route holds audio — ignore.
        }
        #endif
    }
}
