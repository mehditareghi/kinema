import SwiftUI
import KinemaCore
import KinemaPlayback
import KinemaMPV
#if os(macOS)
import AppKit
#endif

public enum AppMode: Equatable {
    case library
    case player
}

@MainActor
@Observable
public final class PlayerViewModel {
    public let session: PlayerSession
    public var appMode: AppMode = .library
    public var showControls = false
    public var osdMessage: String?
    public var isMuted = false
    public var showPlaylist = false
    public var showSubtitles = false
    public var showAudio = false
    public var showVideoFilters = false
    public var showChapters = false
    public var showSettings = false
    /// Mirrored from the session so SwiftUI reliably refreshes the Up Next card.
    public private(set) var upNextOffer: UpNextOffer?
    public var librarySection: LibrarySection = .collection
    public let libraryBrowse = LibraryBrowseState()

    private var hideControlsTask: Task<Void, Never>?
    private var osdTask: Task<Void, Never>?
    private var openTask: Task<Void, Never>?
    private var eventBusToken: UUID?
    public private(set) var isOpeningMedia = false

    public init(session: PlayerSession? = nil) {
        self.session = session ?? PlayerSessionPool.sharedSession()
        self.isMuted = PreferencesStore.shared.preferences.isMuted
        self.upNextOffer = self.session.upNextOffer
        NowPlayingController.shared.attach(session: self.session)
        eventBusToken = EventBus.shared.subscribe { [weak self] event in
            Task { @MainActor in
                self?.handleEvent(event)
            }
        }
    }

    public var isInPlayer: Bool { appMode == .player }

    public var isPresentingPlayerSheet: Bool {
        showPlaylist || showSubtitles || showAudio || showVideoFilters || showChapters || showSettings
    }

    public func prepare() {
        try? session.prepare()
    }

    public func enterPlayer() {
        guard appMode != .player else { return }
        withAnimation(.easeInOut(duration: 0.28)) {
            appMode = .player
            showControls = false
        }
    }

    public func exitPlayer() {
        hideControlsTask?.cancel()
        openTask?.cancel()
        showSettings = false
        showAudio = false
        showVideoFilters = false
        showChapters = false
        showSubtitles = false
        showPlaylist = false
        ScreenWakeLock.setPreventSleep(false)
        NowPlayingController.shared.deactivate()
        session.teardownPlayback()
        withAnimation(.easeInOut(duration: 0.28)) {
            appMode = .library
            showControls = false
        }
    }

    public func open(_ url: URL) async {
        await openItems([MediaItem(url: url)])
    }

    public func openItems(_ items: [MediaItem]) async {
        await openItems(items, startingAt: items.first, audioOnly: false)
    }

    public func openItems(_ items: [MediaItem], startingAt first: MediaItem?, audioOnly: Bool = false) async {
        guard let first else { return }

        openTask?.cancel()
        openTask = Task {
            isOpeningMedia = true
            defer { isOpeningMedia = false }

            for item in items {
                guard !Task.isCancelled else { return }
                session.grantFileAccess(to: item.url)
            }
            session.setPlaylist(items, startingAt: first)
            enterPlayer()
            #if os(iOS) || os(tvOS)
            // Let the player view finish appearing before mpv creates the GL surface.
            try? await Task.sleep(for: .milliseconds(150))
            #else
            try? await Task.sleep(for: .milliseconds(200))
            #endif
            guard !Task.isCancelled else { return }

            do {
                try await session.load(first, audioOnly: audioOnly)
                guard !Task.isCancelled else { return }
                scheduleHideControls()
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                NSLog("Kinema: failed to open %@ — %@", first.url.lastPathComponent, error.localizedDescription)
                showOSD("Failed to open: \(error.localizedDescription)")
                exitPlayer()
            }
        }
        await openTask?.value
    }

    public func playNext(_ item: MediaItem) {
        session.playNextInPlaylist([item])
        showOSD("Play next: \(item.title)")
    }

    public func appendToQueue(_ item: MediaItem) {
        session.addToPlaylist([item])
        showOSD("Added to queue: \(item.title)")
    }

    public func toggleControls() {
        guard isInPlayer, session.currentItem != nil, upNextOffer == nil else { return }
        hideControlsTask?.cancel()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            showControls.toggle()
        }
        if showControls {
            scheduleHideControls()
        }
    }

    public func scheduleHideControls(after seconds: TimeInterval = 6) {
        guard isInPlayer, !showSettings, !showAudio, !showVideoFilters, !showChapters, !showSubtitles, !showPlaylist else { return }
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            guard !showSettings, !showAudio, !showVideoFilters, !showChapters, !showSubtitles, !showPlaylist else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                showControls = false
            }
        }
    }

    public func cancelAutoHideControls() {
        hideControlsTask?.cancel()
    }

    public func showOSD(_ message: String) {
        osdMessage = message
        osdTask?.cancel()
        osdTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            osdMessage = nil
        }
    }

    public func confirmUpNext() {
        guard session.upNextOffer != nil else { return }
        showControls = false
        let label = session.upNextOffer?.osdLabel
        session.confirmUpNext()
        upNextOffer = session.upNextOffer
        if let label {
            showOSD(label)
        }
    }

    public func dismissUpNext() {
        guard session.upNextOffer != nil else { return }
        session.dismissUpNext()
        upNextOffer = session.upNextOffer
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            showControls = true
        }
    }

    public func prefetchUpNextIfNeeded(position: TimeInterval) {
        let duration = session.info.duration
        guard duration > 30, position > duration - 60 else { return }
        guard let peek = session.peekSeriesUpNext() else { return }
        let url = peek.item.url
        Task(priority: .utility) {
            if VideoThumbnailLoader.cachedPreview(for: url) != nil { return }
            _ = await VideoThumbnailLoader.loadPreview(
                url: url,
                at: VideoThumbnailLoader.preferredTime(for: WatchProgressStore.entry(for: url))
            )
        }
    }

    public func handleKey(_ key: String) {
        guard let binding = KeyBindingStore.shared.bindingMatchingKey(key) else { return }
        switch binding.action {
        case "play-pause": session.togglePlayPause()
        case "seek-back-5": session.seekRelative(-5)
        case "seek-forward-5": session.seekRelative(5)
        case "pause": session.pause()
        case "volume-up": session.setVolume(min(KinemaPreferences.volumeMax, session.info.volume + 5))
        case "volume-down": session.setVolume(max(0, session.info.volume - 5))
        case "mute":
            isMuted.toggle()
            session.setMuted(isMuted)
        case "speed-up": session.setSpeed(min(4, session.info.speed + 0.25))
        case "speed-down": session.setSpeed(max(0.25, session.info.speed - 0.25))
        case "subtitle-cycle": session.cycleSubtitle()
        case "audio-cycle": session.cycleAudio()
        case "chapter-prev":
            guard session.hasChapters else { return }
            session.playPreviousChapter()
            showOSD(session.currentChapter?.displayTitle ?? binding.description)
            scheduleHideControls()
            return
        case "chapter-next":
            guard session.hasChapters else { return }
            session.playNextChapter()
            showOSD(session.currentChapter?.displayTitle ?? binding.description)
            scheduleHideControls()
            return
        case "ab-loop":
            let message = session.cycleABLoop()
            showOSD(message)
            scheduleHideControls()
            return
        case "subtitle-delay-down": session.adjustSubtitleDelay(by: -0.1)
        case "subtitle-delay-up": session.adjustSubtitleDelay(by: 0.1)
        case "subtitle-bookmark-audio": session.markBookmarkAudio()
        case "subtitle-bookmark-sub": session.markBookmarkSubtitle()
        case "subtitle-bookmark-apply": session.applyBookmarkSync()
        #if os(macOS)
        case "fullscreen": toggleFullscreen()
        #endif
        default: break
        }
        showOSD(binding.description)
        scheduleHideControls()
    }

    #if os(macOS)
    public func toggleFullscreen() {
        NSApp.keyWindow?.toggleFullScreen(nil)
    }
    #endif

    public func handlesKey(_ key: String) -> Bool {
        KeyBindingStore.shared.handlesKey(key)
    }

    private func handleEvent(_ event: KinemaEvent) {
        switch event {
        case .fileLoaded(let item):
            NowPlayingController.shared.activate(for: item)
        case .playbackInfoUpdated:
            NowPlayingController.shared.handlePlaybackUpdate()
        case .stateChanged:
            NowPlayingController.shared.handleStateChange()
        case .playlistEnded:
            exitPlayer()
        case .error(let message):
            showOSD(message)
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                showControls = true
            }
        case .resumedFrom(let position):
            showOSD("Resuming from \(formatTime(position))")
        case .upNextOfferChanged:
            let offer = session.upNextOffer
            withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
                upNextOffer = offer
            }
            if offer != nil {
                cancelAutoHideControls()
                showControls = false
            }
        default:
            break
        }
    }
}

public enum LibrarySection: String, CaseIterable, Identifiable {
    case collection = "Collection"
    case continueWatching = "Continue"
    case stream = "Stream"

    public var id: String { rawValue }

    /// Sidebar primary rows (Stream lives under Open there).
    public static var primaryCases: [LibrarySection] { [.collection, .continueWatching] }

    /// Compact tab bar destinations, Apple order: browse → open stream → resume.
    public static var tabCases: [LibrarySection] { [.collection, .stream, .continueWatching] }

    public var icon: String {
        switch self {
        case .collection: return "film.stack.fill"
        case .continueWatching: return "play.circle.fill"
        case .stream: return "link"
        }
    }

    public var tabTitle: String {
        switch self {
        case .collection: return KinemaCopy.collection
        case .continueWatching: return KinemaCopy.continue
        case .stream: return KinemaCopy.openStreamTitle
        }
    }
}
