import Foundation
import MediaPlayer
import KinemaCore
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

        publish(force: true)
        refreshArtwork(for: item.url)
    }

    func handlePlaybackUpdate() {
        guard isActive else { return }
        publish(force: false)
    }

    func handleStateChange() {
        guard isActive else { return }
        publish(force: true)
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
        let rate = session.state == .playing ? max(info.speed, 0.01) : 0
        let elapsed = max(0, info.position)
        let duration = max(0, info.duration)

        let elapsedChanged = abs(elapsed - lastPublishedElapsed) >= 0.45
        let durationChanged = abs(duration - lastPublishedDuration) >= 0.25
        let rateChanged = abs(rate - lastPublishedRate) >= 0.01
        let titleChanged = title != lastPublishedTitle
        guard force || elapsedChanged || durationChanged || rateChanged || titleChanged else { return }

        var nowPlaying: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyPlaybackRate: rate,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: info.speed,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue
        ]

        if let existing = MPNowPlayingInfoCenter.default().nowPlayingInfo,
           let artwork = existing[MPMediaItemPropertyArtwork] {
            nowPlaying[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlaying
        lastPublishedElapsed = elapsed
        lastPublishedDuration = duration
        lastPublishedRate = rate
        lastPublishedTitle = title
    }

    private func displayTitle(for session: PlayerSession) -> String {
        if let itemTitle = session.currentItem?.title.trimmingCharacters(in: .whitespacesAndNewlines),
           !itemTitle.isEmpty {
            return itemTitle
        }
        let infoTitle = session.info.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return infoTitle.isEmpty ? "Kinema" : infoTitle
    }

    private func clearNowPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        lastPublishedElapsed = -1
        lastPublishedDuration = -1
        lastPublishedRate = -1
        lastPublishedTitle = ""
    }

    // MARK: - Artwork

    private func refreshArtwork(for url: URL) {
        let token = url.path
        artworkToken = token

        if let image = VideoThumbnailLoader.cachedPreview(for: url)?.image {
            applyArtwork(image, token: token)
            return
        }

        // Graceful: only generate when missing; never block transport metadata.
        artworkLoadTask?.cancel()
        artworkLoadTask = Task { [weak self] in
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

        // Avoid dead previous/next affordances until lineup remotes are intentional.
        center.nextTrackCommand.isEnabled = false
        center.previousTrackCommand.isEnabled = false
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
    }

    private func performOnSession(_ body: @MainActor (PlayerSession) -> Void) -> MPRemoteCommandHandlerStatus {
        // Remote handlers may arrive off the main actor; hop synchronously for a real status.
        if Thread.isMainThread {
            guard isActive, let session else { return .noActionableNowPlayingItem }
            body(session)
            publish(force: true)
            return .success
        }
        var status: MPRemoteCommandHandlerStatus = .commandFailed
        DispatchQueue.main.sync {
            guard isActive, let session else {
                status = .noActionableNowPlayingItem
                return
            }
            body(session)
            publish(force: true)
            status = .success
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
