import Foundation
import SwiftData
import KinemaCore
import KinemaMPV
import KinemaMedia
import KinemaSubtitles

@MainActor
@Observable
public final class PlayerSession: PlaybackEngine {
    public private(set) var state: PlayerState = .idle
    public private(set) var info = PlaybackInfo()
    public private(set) var currentItem: MediaItem?
    public private(set) var playlist: [MediaItem] = []
    public private(set) var tracks: [Track] = []
    public private(set) var chapters: [Chapter] = []
    public private(set) var activeSubtitleTrackID: Int?

    public var subtitleTracks: [Track] {
        tracks.filter { $0.kind == .subtitle }
    }

    public var embeddedSubtitleTracks: [Track] {
        subtitleTracks.filter { !$0.isExternal }
    }

    public var externalSubtitleTracks: [Track] {
        subtitleTracks.filter { $0.isExternal }
    }

    public var subtitlesAreActive: Bool {
        activeSubtitleTrackID != nil
    }

    public var activeSubtitleTrack: Track? {
        guard let activeSubtitleTrackID else { return nil }
        return subtitleTracks.first(where: { $0.id == activeSubtitleTrackID })
    }

    private let controller = MPVController()
    private let resolver: MediaResolver
    #if os(iOS) || os(tvOS)
    public let renderSurface: MPVRenderSurface = GLESRenderSurface()
    #elseif os(macOS)
    public let renderSurface: MPVRenderSurface = MacOSRenderSurface()
    #endif

    private var playlistIndex = 0
    private var loadGeneration = 0
    private var pendingStartPosition: TimeInterval?
    private var isPrepared = false
    private var positionUpdateTask: Task<Void, Never>?
    private var lastInfoRefresh = Date.distantPast
    private var lastTrackRefresh = Date.distantPast
    private var lastProgressSave = Date.distantPast
    private var securityScopedURLs: [URL] = []
    #if os(iOS) || os(tvOS)
    private var securityScopedMediaIDs = Set<String>()
    private var sandboxCopyCache: [String: URL] = [:]
    private var sessionBookmarks: [String: Data] = [:]
    private var activePlaybackURL: URL?
    private var resumePausedAfterReload = false
    private var skipExtrasOnNextFileLoad = false
    #endif
    public var historyContext: ModelContext?

    public init(resolver: MediaResolver = MediaResolverFactory.makeDefault()) {
        self.resolver = resolver
    }

    public func prepare() throws {
        guard !isPrepared else { return }
        let preferences = PreferencesStore.shared.preferences
        let mpvOptions = PreferencesStore.shared.mpvOptions()
        try controller.initialize(options: mpvOptions)
        controller.attachRenderSurface(renderSurface)
        controller.onEvent = { [weak self] event in
            Task { @MainActor in
                self?.handleMPVEvent(event)
            }
        }
        #if os(macOS)
        controller.setVolume(preferences.volume)
        controller.setSpeed(preferences.speed)
        isPrepared = true
        #endif
    }

    /// Tear down mpv when leaving the player so the next open gets a fresh bind.
    public func teardownPlayback() {
        loadGeneration += 1
        stopPositionUpdates()
        recordHistory()
        endSecurityScopedAccess()
        pendingStartPosition = nil
        currentItem = nil
        tracks = []
        chapters = []
        activeSubtitleTrackID = nil
        info = PlaybackInfo()
        state = .idle
        #if os(iOS) || os(tvOS)
        activePlaybackURL = nil
        #endif
        controller.shutdown()
        isPrepared = false
        EventBus.shared.emit(.stateChanged(state))
    }

    private func finishPrepare() {
        guard !isPrepared else { return }
        let options = PreferencesStore.shared.preferences
        controller.setVolume(options.volume)
        controller.setSpeed(options.speed)
        isPrepared = true
    }

    public func grantFileAccess(to url: URL) {
        #if os(iOS) || os(tvOS)
        beginSecurityScopedAccess(for: url)
        if let bookmark = SecurityScopedBookmark.make(for: url) {
            let mediaID = PlaybackHistoryEntry.mediaID(for: url)
            sessionBookmarks[mediaID] = bookmark
            BookmarkStore.save(bookmark, for: mediaID)
        }
        #else
        beginSecurityScopedAccess(for: url)
        #endif
    }

    public func load(_ item: MediaItem, startPosition: TimeInterval? = nil) async throws {
        try await load(item, startPosition: startPosition, audioOnly: false)
    }

    public func load(_ item: MediaItem, startPosition: TimeInterval? = nil, audioOnly: Bool) async throws {
        try Task.checkCancellation()
        syncPlaylistIndex(for: item)
        loadGeneration += 1
        let generation = loadGeneration

        state = .loading
        EventBus.shared.emit(.stateChanged(state))

        let resolved = try await resolver.resolve(item.url)
        try Task.checkCancellation()
        guard generation == loadGeneration else { throw CancellationError() }

        let resolvedItem = MediaItem(id: item.id, url: resolved, title: item.title, artworkURL: item.artworkURL)

        #if os(iOS) || os(tvOS)
        let fileURL = resolveFileURLForPlayback(resolvedItem.url)
        beginSecurityScopedAccess(for: fileURL)

        var start = startPosition
        if start == nil, PreferencesStore.shared.preferences.resumePlayback {
            start = WatchProgressStore.resumePosition(for: item.url)
        }
        pendingStartPosition = start

        let playbackURL = try await makePlaybackURL(fileURL)
        try Task.checkCancellation()
        guard generation == loadGeneration else { throw CancellationError() }
        #else
        var start = startPosition
        if start == nil, PreferencesStore.shared.preferences.resumePlayback {
            start = WatchProgressStore.resumePosition(for: item.url)
        }
        pendingStartPosition = start
        beginSecurityScopedAccess(for: resolvedItem.url)
        let playbackURL = try makePlaybackURL(resolvedItem.url)
        #endif

        // Mount the player view before starting playback on iOS.
        currentItem = resolvedItem
        state = .starting
        EventBus.shared.emit(.stateChanged(state))

        #if os(iOS) || os(tvOS)
        requestRenderSurfaceLayout()
        try? await Task.sleep(for: .milliseconds(120))
        try Task.checkCancellation()
        guard generation == loadGeneration else { throw CancellationError() }
        try prepare()
        finishPrepare()
        #else
        try prepare()
        #endif

        guard generation == loadGeneration else { throw CancellationError() }
        #if os(iOS) || os(tvOS)
        activePlaybackURL = playbackURL
        #endif
        controller.setVideoEnabled(!audioOnly)
        controller.loadFile(playbackURL)
    }

    #if os(iOS) || os(tvOS)
    public func requestRenderSurfaceLayout() {
        (renderSurface as? GLESRenderSurface)?.requestLayoutUpdate()
    }
    #endif

    public func setPlaylist(_ items: [MediaItem], startingAt first: MediaItem) {
        playlist = items
        playlistIndex = playlistIndex(for: first.url, in: items) ?? 0
    }

    private func playlistIndex(for url: URL, in items: [MediaItem]) -> Int? {
        items.firstIndex { playlistURLsEqual($0.url, url) }
    }

    private func playlistURLsEqual(_ lhs: URL, _ rhs: URL) -> Bool {
        if lhs == rhs { return true }
        guard lhs.isFileURL, rhs.isFileURL else { return false }
        return lhs.standardizedFileURL == rhs.standardizedFileURL
    }

    private func syncPlaylistIndex(for item: MediaItem) {
        if let index = playlistIndex(for: item.url, in: playlist) {
            playlistIndex = index
        }
    }

    #if os(iOS) || os(tvOS)
    private func resolveFileURLForPlayback(_ url: URL) -> URL {
        if url.isFileURL, FileManager.default.isReadableFile(atPath: url.path) {
            return url
        }

        let mediaID = PlaybackHistoryEntry.mediaID(for: url)
        if FileManager.default.isReadableFile(atPath: mediaID) {
            return URL(fileURLWithPath: mediaID)
        }

        let privatePath = "/private" + mediaID
        if FileManager.default.isReadableFile(atPath: privatePath) {
            return URL(fileURLWithPath: privatePath)
        }

        if let data = sessionBookmarks[mediaID], let resolved = SecurityScopedBookmark.resolve(data) {
            return resolved
        }

        if let data = BookmarkStore.load(for: mediaID), let resolved = SecurityScopedBookmark.resolve(data) {
            return resolved
        }

        return url
    }
    #endif

    #if os(iOS) || os(tvOS)
    private func makePlaybackURL(_ url: URL) async throws -> URL {
        guard url.isFileURL else { return url }

        if !needsSandboxCopy(url) {
            NSLog("Kinema: playing directly from %@", url.path)
            return url
        }

        let mediaID = PlaybackHistoryEntry.mediaID(for: url)
        if let cached = sandboxCopyCache[mediaID],
           FileManager.default.fileExists(atPath: cached.path) {
            NSLog("Kinema: using cached sandbox copy for %@", url.lastPathComponent)
            return cached
        }

        NSLog("Kinema: copying %@ to sandbox…", url.lastPathComponent)
        let destination = sandboxCacheURL(for: url)

        let copied = try await Task.detached(priority: .userInitiated) {
            var coordinationError: NSError?
            var copyError: Error?

            let coordinator = NSFileCoordinator()
            coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { readURL in
                do {
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.copyItem(at: readURL, to: destination)
                } catch {
                    copyError = error
                }
            }

            if let coordinationError {
                throw coordinationError
            }
            if let copyError {
                throw copyError
            }

            NSLog("Kinema: copied media to %@", destination.path)
            return destination
        }.value

        sandboxCopyCache[mediaID] = copied
        return copied
    }

    private func sandboxCacheURL(for url: URL) -> URL {
        let mediaID = PlaybackHistoryEntry.mediaID(for: url)
        let key = stableCacheKey(mediaID)
        let ext = url.pathExtension.isEmpty ? "mp4" : url.pathExtension
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("kinema-cache-\(key).\(ext)")
    }

    private func stableCacheKey(_ value: String) -> String {
        var hash: UInt64 = 5381
        for byte in value.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return String(hash, radix: 16)
    }

    private func needsSandboxCopy(_ url: URL) -> Bool {
        guard let dataRoot = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .deletingLastPathComponent().deletingLastPathComponent().path
        else { return true }
        let path = url.standardizedFileURL.path
        if path.contains("File Provider Storage") { return true }
        return !path.hasPrefix(dataRoot)
    }
    #else
    private func makePlaybackURL(_ url: URL) throws -> URL { url }
    #endif

    public func play() {
        controller.play()
        state = .playing
        refreshInfo(force: true)
        startPositionUpdates()
        EventBus.shared.emit(.stateChanged(state))
    }

    public func pause() {
        controller.pause()
        state = .paused
        refreshInfo(force: true)
        stopPositionUpdates()
        recordHistory()
        EventBus.shared.emit(.stateChanged(state))
    }

    public func togglePlayPause() {
        controller.togglePause()
        refreshInfo(force: true)
        state = info.isPaused ? .paused : .playing
        if info.isPaused {
            stopPositionUpdates()
        } else {
            startPositionUpdates()
        }
        EventBus.shared.emit(.stateChanged(state))
    }

    public func seek(to time: TimeInterval) {
        controller.seek(to: time)
        refreshInfo(force: true)
    }

    public func seekRelative(_ delta: TimeInterval) {
        controller.seek(to: delta, relative: true)
        refreshInfo(force: true)
    }

    public func stop() {
        loadGeneration += 1
        state = .stopping
        recordHistory()
        stopPositionUpdates()
        controller.stop()
        state = .idle
        currentItem = nil
        EventBus.shared.emit(.stateChanged(state))
    }

    public func setVolume(_ volume: Double) {
        controller.setVolume(volume)
        PreferencesStore.shared.preferences.volume = volume
        refreshInfo(force: true)
    }

    public func setSpeed(_ speed: Double) {
        controller.setSpeed(speed)
        PreferencesStore.shared.preferences.speed = speed
        refreshInfo(force: true)
    }

    public func setMuted(_ muted: Bool) {
        controller.setMute(muted)
        refreshInfo(force: true)
    }

    public func addToPlaylist(_ items: [MediaItem]) {
        playlist.append(contentsOf: items)
    }

    public func playNextInPlaylist(_ items: [MediaItem]) {
        let insertIndex = playlist.isEmpty ? 0 : min(playlistIndex + 1, playlist.count)
        playlist.insert(contentsOf: items, at: insertIndex)
    }

    public func movePlaylist(fromOffsets: IndexSet, toOffset: Int) {
        playlist.move(fromOffsets: fromOffsets, toOffset: toOffset)
    }

    public func playNext() {
        guard playlistIndex + 1 < playlist.count else { return }
        playlistIndex += 1
        Task {
            try? await load(playlist[playlistIndex])
            play()
        }
    }

    public func playPrevious() {
        guard !playlist.isEmpty else { return }
        playlistIndex = max(playlistIndex - 1, 0)
        Task {
            try? await load(playlist[playlistIndex])
            play()
        }
    }

    public func loadSubtitle(url: URL) {
        loadExternalSubtitle(url: url)
    }

    public func loadExternalSubtitle(url: URL) {
        controller.addSubtitle(url: url)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            refreshTracks(force: true)
            if let track = activeSubtitleTrack {
                controller.showOSD("Subtitles: \(SubtitleLabels.displayName(for: track))")
            } else {
                controller.showOSD("Subtitles loaded")
            }
        }
    }

    public func disableSubtitles() {
        controller.disableSubtitles()
        refreshTracks(force: true)
        controller.showOSD("Subtitles off")
    }

    public func selectSubtitleTrack(id: Int) {
        controller.selectTrack(id: id, kind: .subtitle)
        refreshTracks(force: true)
        if let track = activeSubtitleTrack {
            controller.showOSD("Subtitles: \(SubtitleLabels.displayName(for: track))")
        }
    }

    public func setSubtitleFontSize(_ size: Int) {
        controller.setSubtitleFontSize(size)
        PreferencesStore.shared.preferences.subtitleFontSize = size
    }

    public func refreshCaptionTracks() {
        refreshTracks(force: true)
    }

    public func cycleSubtitle() {
        controller.cycleSubtitle()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            refreshTracks(force: true)
        }
    }

    public func selectTrack(id: Int, kind: TrackKind) {
        controller.selectTrack(id: id, kind: kind)
    }

    public func shutdown() {
        stopPositionUpdates()
        recordHistory()
        endSecurityScopedAccess()
        controller.shutdown()
        state = .idle
    }

    #if os(iOS) || os(tvOS)
    private func beginSecurityScopedAccess(for url: URL) {
        guard url.isFileURL else { return }
        let mediaID = PlaybackHistoryEntry.mediaID(for: url)
        if securityScopedMediaIDs.contains(mediaID) { return }

        if FileManager.default.isReadableFile(atPath: url.path),
           url.path.contains(FileManager.default.temporaryDirectory.path) {
            return
        }

        guard url.startAccessingSecurityScopedResource() else { return }
        securityScopedMediaIDs.insert(mediaID)
        if !securityScopedURLs.contains(url) {
            securityScopedURLs.append(url)
        }
    }

    private func endSecurityScopedAccess() {
        for url in securityScopedURLs {
            url.stopAccessingSecurityScopedResource()
        }
        securityScopedURLs.removeAll()
        securityScopedMediaIDs.removeAll()
    }
    #else
    private func beginSecurityScopedAccess(for url: URL) {
        guard url.isFileURL else { return }
        if securityScopedURLs.contains(url) { return }
        guard url.startAccessingSecurityScopedResource() else { return }
        securityScopedURLs.append(url)
    }

    private func endSecurityScopedAccess() {
        for url in securityScopedURLs {
            url.stopAccessingSecurityScopedResource()
        }
        securityScopedURLs.removeAll()
    }
    #endif

    private func handleMPVEvent(_ event: MPVClientEvent) {
        switch event {
        case .fileLoaded:
            state = .loaded
            if let start = pendingStartPosition, start > 0 {
                controller.seek(to: start)
                EventBus.shared.emit(.resumedFrom(start))
                pendingStartPosition = nil
            }
            refreshInfo(force: true)
            if resumePausedAfterReload {
                resumePausedAfterReload = false
                controller.pause()
                state = .paused
                EventBus.shared.emit(.stateChanged(state))
            } else {
                play()
            }
            if let item = currentItem {
                EventBus.shared.emit(.fileLoaded(item))
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    refreshTracks(force: true)
                    applyAutomaticSubtitles(for: item)
                }
            }
            skipExtrasOnNextFileLoad = false
        case .endFile(let reason, let error):
            handleEndFile(reason: reason, error: error)
        case .propertyChanged:
            refreshInfo()
            refreshTracks()
        }
    }

    private func applyAutomaticSubtitles(for item: MediaItem) {
        guard !skipExtrasOnNextFileLoad else { return }
        guard !subtitlesAreActive else { return }

        if let embedded = embeddedSubtitleTracks.first(where: { $0.isDefault }) ?? embeddedSubtitleTracks.first {
            selectSubtitleTrack(id: embedded.id)
            return
        }

        guard PreferencesStore.shared.preferences.autoLoadSubtitles, item.url.isFileURL else { return }
        let matches = SubtitleFileMatcher.findLocalSubtitles(for: item.url)
        if let match = SubtitleFileMatcher.preferredMatch(from: matches) {
            loadExternalSubtitle(url: match.url)
        }
    }

    private func refreshTracks(force: Bool = false) {
        guard state.isActive || state == .loaded else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastTrackRefresh) >= 0.35 else { return }
        lastTrackRefresh = now

        let snapshot = controller.trackSnapshot()
        tracks = snapshot.tracks
        activeSubtitleTrackID = snapshot.activeSubtitleTrackID
        EventBus.shared.emit(.tracksUpdated(tracks))
    }

    private func handleEndFile(reason: MPVEndFileReason, error: Int32) {
        switch reason {
        case .stop, .quit, .redirect:
            return
        case .error:
            guard state == .loading || state == .starting || state == .playing
                || state == .paused || state == .loaded else { return }
            NSLog("Kinema: mpv playback error %d", error)
            stopPositionUpdates()
            // Only keep Continue progress if this title actually started.
            // Invalid / dead stream links should not appear in recent.
            if WatchProgressStore.hasEstablishedPlayback(position: info.position, duration: info.duration) {
                recordHistory()
            }
            state = .idle
            EventBus.shared.emit(.error("Playback failed (\(error))"))
        case .eof:
            handlePlaybackFinished()
        }
    }

    private var isHandlingPlaybackFinish = false

    private func handlePlaybackFinished() {
        guard !isHandlingPlaybackFinish else { return }
        guard state == .playing || state == .paused || state == .loaded else { return }
        isHandlingPlaybackFinish = true
        defer { isHandlingPlaybackFinish = false }

        stopPositionUpdates()
        recordHistory()

        if playlistIndex + 1 < playlist.count {
            state = .loading
            EventBus.shared.emit(.stateChanged(state))
            playNext()
        } else {
            state = .idle
            EventBus.shared.emit(.playlistEnded)
        }
    }

    private func startPositionUpdates() {
        positionUpdateTask?.cancel()
        positionUpdateTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, let self else { return }
                guard self.state == .playing || self.state == .paused else { return }
                self.refreshPosition()
            }
        }
    }

    private func stopPositionUpdates() {
        positionUpdateTask?.cancel()
        positionUpdateTask = nil
    }

    private func refreshPosition() {
        let updated = controller.playbackInfo()
        guard abs(updated.position - info.position) > 0.05
            || updated.isPaused != info.isPaused
            || abs(updated.duration - info.duration) > 0.5 else { return }
        info = updated
        if state == .loaded || state == .playing || state == .paused {
            state = updated.isPaused ? .paused : .playing
        }
        maybeSaveWatchProgress()
        EventBus.shared.emit(.playbackInfoUpdated(info))
    }

    private func maybeSaveWatchProgress() {
        guard let item = currentItem, state.isActive else { return }
        let now = Date()
        guard now.timeIntervalSince(lastProgressSave) >= 15 else { return }
        lastProgressSave = now
        WatchProgressStore.record(item: item, position: info.position, duration: info.duration)
    }

    private func refreshInfo(force: Bool = false) {
        let now = Date()
        guard force || now.timeIntervalSince(lastInfoRefresh) >= 0.15 else { return }
        lastInfoRefresh = now
        info = controller.playbackInfo()
        if state == .loaded || state == .playing || state == .paused {
            state = info.isPaused ? .paused : .playing
        }
        EventBus.shared.emit(.playbackInfoUpdated(info))
    }

    private func recordHistory() {
        guard let item = currentItem else { return }
        guard WatchProgressStore.hasEstablishedPlayback(position: info.position, duration: info.duration) else {
            return
        }
        WatchProgressStore.record(item: item, position: info.position, duration: info.duration)
        if let context = historyContext {
            HistoryStore.recordPlayback(
                context: context,
                item: item,
                position: info.position,
                duration: info.duration
            )
        }
    }
}

@MainActor
public enum PlayerSessionPool {
    private static var sessions: [PlayerSession] = []

    public static func sharedSession() -> PlayerSession {
        if let idle = sessions.first(where: { $0.state == .idle }) {
            return idle
        }
        let session = PlayerSession()
        sessions.append(session)
        return session
    }

    public static func createSession() -> PlayerSession {
        let session = PlayerSession()
        sessions.append(session)
        return session
    }
}
