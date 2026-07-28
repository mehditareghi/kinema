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
    public private(set) var activeSecondarySubtitleTrackID: Int?

    /// Runtime sync values (not persisted globally — per-track where possible).
    public private(set) var subtitleDelay: Double = 0
    public private(set) var secondarySubtitleDelay: Double = 0
    public private(set) var audioDelay: Double = 0
    public private(set) var subtitleSpeed: Double = 1
    public var bookmarkAudioMark: TimeInterval?
    public var bookmarkSubtitleMark: TimeInterval?
    public var syncTarget: SubtitleSyncTarget = .primary

    public private(set) var rememberedSubtitles: [ManualSubtitleAssociation] = []

    /// Source file for each loaded external track id.
    private var externalSourceByTrackID: [Int: URL] = [:]
    private var pendingExternalSourceURL: URL?

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

    public var activeSecondarySubtitleTrack: Track? {
        guard let activeSecondarySubtitleTrackID else { return nil }
        return subtitleTracks.first(where: { $0.id == activeSecondarySubtitleTrackID })
    }

    public func isPrimaryTrackSelected(_ trackID: Int) -> Bool {
        activeSubtitleTrackID == trackID
    }

    public func isSecondaryTrackSelected(_ trackID: Int) -> Bool {
        activeSecondarySubtitleTrackID == trackID
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
        activeSecondarySubtitleTrackID = nil
        subtitleDelay = 0
        secondarySubtitleDelay = 0
        audioDelay = 0
        subtitleSpeed = 1
        bookmarkAudioMark = nil
        bookmarkSubtitleMark = nil
        syncTarget = .primary
        rememberedSubtitles = []
        externalSourceByTrackID = [:]
        pendingExternalSourceURL = nil
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
        tracks = []
        chapters = []
        activeSubtitleTrackID = nil
        activeSecondarySubtitleTrackID = nil
        externalSourceByTrackID = [:]
        pendingExternalSourceURL = nil
        subtitleDelay = 0
        secondarySubtitleDelay = 0
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
        let next = playlist[playlistIndex]
        Task {
            do {
                try await load(next)
                play()
            } catch {
                NSLog(
                    "Kinema: failed to play next %@ — %@",
                    next.url.lastPathComponent,
                    error.localizedDescription
                )
                // Skip a bad title and keep walking the folder playlist.
                if playlistIndex + 1 < playlist.count {
                    playNext()
                } else {
                    state = .idle
                    EventBus.shared.emit(.playlistEnded)
                }
            }
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

    public func loadExternalSubtitle(url: URL, encodingID: String? = nil, remember: Bool = false) {
        if let encodingID {
            setSubtitleEncoding(encodingID)
        }
        pendingExternalSourceURL = url
        controller.addSubtitle(url: url)
        if remember, let media = currentItem?.url {
            _ = SubtitleAssociationStore.add(
                for: media,
                subtitleURL: url,
                encodingID: encodingID ?? PreferencesStore.shared.preferences.subtitleEncodingID
            )
            refreshRememberedSubtitles()
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            refreshTracks(force: true)
            applyStoredDelayIfNeeded(for: url)
            if let track = activeSubtitleTrack {
                controller.showOSD("Subtitles: \(SubtitleLabels.displayName(for: track))")
            } else {
                controller.showOSD("Subtitles loaded")
            }
            persistSubtitleSession()
        }
    }

    public func loadExternalSubtitles(urls: [URL], encodingID: String? = nil, remember: Bool = true) {
        for url in urls {
            loadExternalSubtitle(url: url, encodingID: encodingID, remember: remember)
        }
    }

    public func removeRememberedSubtitle(_ association: ManualSubtitleAssociation) {
        guard let media = currentItem?.url else { return }
        SubtitleAssociationStore.remove(for: media, associationID: association.id)
        refreshRememberedSubtitles()

        if let trackID = externalSourceByTrackID.first(where: { $0.value.path == association.path })?.key {
            if activeSubtitleTrackID == trackID { disableSubtitles() }
            if activeSecondarySubtitleTrackID == trackID { disableSecondarySubtitles() }
            controller.removeSubtitle(id: trackID)
            externalSourceByTrackID.removeValue(forKey: trackID)
        }
        refreshTracks(force: true)
        controller.showOSD("Removed \(association.displayName)")
    }

    public func refreshRememberedSubtitles() {
        guard let media = currentItem?.url else {
            rememberedSubtitles = []
            return
        }
        rememberedSubtitles = SubtitleAssociationStore.associations(for: media)
    }

    private func applyStoredDelayIfNeeded(for url: URL) {
        guard let media = currentItem?.url else { return }
        if let match = SubtitleAssociationStore.associations(for: media).first(where: { $0.path == url.path }),
           abs(match.delay) > 0.001 {
            // Apply after track settles as primary delay if this became primary.
            subtitleDelay = match.delay
            controller.setSubtitleDelay(match.delay)
        }
    }

    public func selectSubtitleTrack(id: Int) {
        controller.selectTrack(id: id, kind: .subtitle)
        refreshTracks(force: true)
        if let track = activeSubtitleTrack {
            controller.showOSD("Subtitles: \(SubtitleLabels.displayName(for: track))")
        }
        persistSubtitleSession()
    }

    public func selectSecondarySubtitleTrack(id: Int) {
        controller.selectSecondarySubtitleTrack(id: id)
        controller.setSecondarySubtitleVisible(true)
        refreshTracks(force: true)
        refreshStackedSubtitlePositions()
        if let track = activeSecondarySubtitleTrack {
            controller.showOSD("Secondary: \(SubtitleLabels.displayName(for: track))")
        }
        persistSubtitleSession()
    }

    public func disableSubtitles() {
        controller.disableSubtitles()
        refreshTracks(force: true)
        persistSubtitleSession()
        controller.showOSD("Subtitles off")
    }

    public func disableSecondarySubtitles() {
        controller.disableSecondarySubtitles()
        refreshTracks(force: true)
        // Dual fit may have lifted primary — put it back to the user's placement.
        refreshStackedSubtitlePositions()
        persistSubtitleSession()
        controller.showOSD("Secondary subtitles off")
    }

    public func setSubtitleFontSize(_ size: Int) {
        controller.setSubtitleFontSize(size)
        PreferencesStore.shared.preferences.subtitleFontSize = size
        refreshASSForceStyle()
    }

    public func setSubtitleFontID(_ fontID: String) {
        PreferencesStore.shared.preferences.subtitleFontID = fontID
        let font = SubtitleFontRegistry.resolveStoredFontSelection(fontID)
        if !font.mpvFontName.isEmpty {
            controller.setSubtitleFont(font.mpvFontName)
        }
        refreshASSForceStyle()
    }

    public func setSubtitleColorHex(_ hex: String) {
        let normalized = normalizedSubtitleColorHex(hex)
        PreferencesStore.shared.preferences.subtitleColorHex = normalized
        controller.setSubtitleColor(normalized)
        refreshASSForceStyle()
    }

    public func setSubtitleEncoding(_ encodingID: String) {
        PreferencesStore.shared.preferences.subtitleEncodingID = encodingID
        controller.setSubtitleCodepage(SubtitlePreferenceCatalog.encoding(id: encodingID).id)
    }

    public func setSubtitleBorderSize(_ size: Double) {
        PreferencesStore.shared.preferences.subtitleBorderSize = size
        controller.setSubtitleBorderSize(size)
        refreshASSForceStyle()
    }

    public func setSubtitleBorderColorHex(_ hex: String) {
        let normalized = normalizedSubtitleColorHex(hex)
        PreferencesStore.shared.preferences.subtitleBorderColorHex = normalized
        controller.setSubtitleBorderColor(normalized)
        refreshASSForceStyle()
    }

    public func setSubtitleShadowOffset(_ offset: Double) {
        PreferencesStore.shared.preferences.subtitleShadowOffset = offset
        controller.setSubtitleShadowOffset(offset)
        refreshASSForceStyle()
    }

    public func setSubtitleShadowColorHex(_ hex: String) {
        let normalized = normalizedSubtitleColorHex(hex)
        PreferencesStore.shared.preferences.subtitleShadowColorHex = normalized
        controller.setSubtitleShadowColor(normalized)
        refreshASSForceStyle()
    }

    public func setSubtitleBackColorHex(_ hex: String) {
        let normalized = normalizedSubtitleColorHex(hex)
        PreferencesStore.shared.preferences.subtitleBackColorHex = normalized
        controller.setSubtitleBackColor(normalized)
        refreshASSForceStyle()
    }

    public func setSubtitleBold(_ bold: Bool) {
        PreferencesStore.shared.preferences.subtitleBold = bold
        controller.setSubtitleBold(bold)
        refreshASSForceStyle()
    }

    public func setSubtitleItalic(_ italic: Bool) {
        PreferencesStore.shared.preferences.subtitleItalic = italic
        controller.setSubtitleItalic(italic)
        refreshASSForceStyle()
    }

    public func setSubtitlePos(_ pos: Int) {
        PreferencesStore.shared.preferences.subtitlePos = pos
        controller.setSubtitlePos(pos)
        refreshStackedSubtitlePositions()
        persistSubtitleSession()
    }

    public func setSecondarySubtitlePos(_ pos: Int) {
        // Dual subs are auto-stacked from primary placement; keep API for callers/prefs sync.
        PreferencesStore.shared.preferences.secondarySubtitlePos = pos
        controller.setSecondarySubtitlePos(pos)
        persistSubtitleSession()
    }

    public func setSubtitleAlignX(_ align: SubtitleHorizontalAlign) {
        PreferencesStore.shared.preferences.subtitleAlignX = align
        PreferencesStore.shared.preferences.secondarySubtitleAlignX = align
        controller.setSubtitleAlignX(align)
        persistSubtitleSession()
    }

    public func setSubtitleAlignY(_ align: SubtitleVerticalAlign) {
        PreferencesStore.shared.preferences.subtitleAlignY = align
        controller.setSubtitleAlignY(align)
        persistSubtitleSession()
    }

    public func setSecondarySubtitleAlignX(_ align: SubtitleHorizontalAlign) {
        // Dual subs share horizontal align in libmpv; keep prefs in sync.
        PreferencesStore.shared.preferences.secondarySubtitleAlignX = align
        PreferencesStore.shared.preferences.subtitleAlignX = align
        controller.setSubtitleAlignX(align)
        persistSubtitleSession()
    }

    public func setSubtitlePlacement(_ anchor: SubtitlePlacementAnchor) {
        PreferencesStore.shared.preferences.subtitleAlignX = anchor.alignX
        PreferencesStore.shared.preferences.subtitleAlignY = anchor.alignY
        PreferencesStore.shared.preferences.subtitlePos = anchor.verticalPos
        PreferencesStore.shared.preferences.secondarySubtitleAlignX = anchor.alignX
        controller.setSubtitleAlignX(anchor.alignX)
        controller.setSubtitleAlignY(anchor.alignY)
        controller.setSubtitlePos(anchor.verticalPos)
        refreshStackedSubtitlePositions()
        persistSubtitleSession()
    }

    public func setSecondarySubtitlePlacement(_ anchor: SubtitlePlacementAnchor) {
        // Same stack band — secondary only adjusts vertical stack slot via pos.
        setSubtitlePlacement(anchor)
    }

    public func setSubtitleDelay(_ delay: Double) {
        applyDelay(delay, to: syncTarget)
    }

    public func adjustSubtitleDelay(by delta: Double) {
        switch syncTarget {
        case .primary:
            applyDelay(subtitleDelay + delta, to: .primary)
        case .secondary:
            applyDelay(secondarySubtitleDelay + delta, to: .secondary)
        case .both:
            applyDelay(subtitleDelay + delta, to: .primary)
            applyDelay(secondarySubtitleDelay + delta, to: .secondary)
        }
    }

    public func setSecondarySubtitleDelay(_ delay: Double) {
        applyDelay(delay, to: .secondary)
    }

    private func applyDelay(_ delay: Double, to target: SubtitleSyncTarget) {
        switch target {
        case .primary:
            subtitleDelay = delay
            if let id = activeSubtitleTrackID {
                persistDelay(delay, for: externalSourceByTrackID[id])
            }
            controller.setSubtitleDelay(delay)
            persistSubtitleSession()
            controller.showOSD(String(format: "Primary delay: %+.2fs", delay))
        case .secondary:
            secondarySubtitleDelay = delay
            if let id = activeSecondarySubtitleTrackID {
                persistDelay(delay, for: externalSourceByTrackID[id])
            }
            controller.setSecondarySubtitleDelay(delay)
            persistSubtitleSession()
            controller.showOSD(String(format: "Secondary delay: %+.2fs", delay))
        case .both:
            applyDelay(delay, to: .primary)
            applyDelay(delay, to: .secondary)
        }
    }

    private func persistDelay(_ delay: Double, for source: URL?) {
        guard let source, let media = currentItem?.url else { return }
        if let match = SubtitleAssociationStore.associations(for: media).first(where: { $0.path == source.path }) {
            SubtitleAssociationStore.updateDelay(for: media, associationID: match.id, delay: delay)
            refreshRememberedSubtitles()
        }
    }

    public func applyBookmarkSync() {
        guard let audio = bookmarkAudioMark, let sub = bookmarkSubtitleMark else {
            controller.showOSD("Mark audio and subtitle first")
            return
        }
        let delta = audio - sub
        adjustSubtitleDelay(by: delta)
        bookmarkAudioMark = nil
        bookmarkSubtitleMark = nil
    }

    public func setSubtitleASSOverride(_ mode: SubtitleASSOverrideMode) {
        PreferencesStore.shared.preferences.subtitleASSOverride = mode
        controller.setSubtitleASSOverride(mode)
        refreshASSForceStyle()
    }

    public func setSubtitleFadeOut(_ enabled: Bool) {
        PreferencesStore.shared.preferences.subtitleFadeOut = enabled
        refreshASSForceStyle()
    }

    public func setAudioDelay(_ delay: Double) {
        audioDelay = delay
        controller.setAudioDelay(delay)
        controller.showOSD(String(format: "Audio delay: %+.2fs", delay))
    }

    public func adjustAudioDelay(by delta: Double) {
        setAudioDelay(audioDelay + delta)
    }

    public func setSubtitleSpeed(_ speed: Double) {
        let clamped = max(0.25, min(4, speed))
        subtitleSpeed = clamped
        controller.setSubtitleSpeed(clamped)
        controller.showOSD(String(format: "Sub speed: %.2fx", clamped))
    }

    public func markBookmarkAudio() {
        bookmarkAudioMark = info.position
        controller.showOSD("Audio sync mark")
    }

    public func markBookmarkSubtitle() {
        bookmarkSubtitleMark = info.position
        controller.showOSD("Subtitle sync mark")
    }

    public func applyLiveSubtitlePreferences() {
        let p = PreferencesStore.shared.preferences
        let font = SubtitleFontRegistry.resolveStoredFontSelection(p.subtitleFontID)
        controller.setSubtitleFontSize(p.subtitleFontSize)
        if !font.mpvFontName.isEmpty {
            controller.setSubtitleFont(font.mpvFontName)
        }
        controller.setSubtitleColor(normalizedSubtitleColorHex(p.subtitleColorHex))
        controller.setSubtitleCodepage(SubtitlePreferenceCatalog.encoding(id: p.subtitleEncodingID).id)
        controller.setSubtitleBorderSize(p.subtitleBorderSize)
        controller.setSubtitleBorderColor(normalizedSubtitleColorHex(p.subtitleBorderColorHex))
        controller.setSubtitleShadowOffset(p.subtitleShadowOffset)
        controller.setSubtitleShadowColor(normalizedSubtitleColorHex(p.subtitleShadowColorHex))
        controller.setSubtitleBackColor(normalizedSubtitleColorHex(p.subtitleBackColorHex))
        controller.setSubtitleBold(p.subtitleBold)
        controller.setSubtitleItalic(p.subtitleItalic)
        controller.setSubtitleAlignX(p.subtitleAlignX)
        controller.setSubtitleAlignY(p.subtitleAlignY)
        let primaryOverride = p.subtitleASSOverride == .force ? SubtitleASSOverrideMode.scale : p.subtitleASSOverride
        controller.setSubtitleASSOverride(primaryOverride)
        refreshASSForceStyle()
        refreshStackedSubtitlePositions()
        if activeSecondarySubtitleTrackID != nil {
            controller.setSecondarySubtitleVisible(true)
        }
    }

    private func refreshASSForceStyle() {
        let style = SubtitleASSForceStyleBuilder.build(from: PreferencesStore.shared.preferences)
        controller.setSubtitleASSForceStyle(style ?? "")
    }

    /// Single track: exact user placement. Dual: secondary below primary; only then shift up to stay on-screen.
    private func refreshStackedSubtitlePositions() {
        let preferredPrimary = min(
            Self.subtitlePosMax,
            max(Self.subtitlePosMin, PreferencesStore.shared.preferences.subtitlePos)
        )

        guard activeSecondarySubtitleTrackID != nil else {
            controller.setSubtitlePos(preferredPrimary)
            return
        }

        let fitted = Self.fittedDualStackPositions(preferredPrimary: preferredPrimary)
        controller.setSubtitlePos(fitted.primary)
        controller.setSecondarySubtitlePos(fitted.secondary)

        let prefs = PreferencesStore.shared.preferences
        if prefs.secondarySubtitlePos != fitted.secondary {
            PreferencesStore.shared.preferences.secondarySubtitlePos = fitted.secondary
        }
        if prefs.secondarySubtitleAlignX != prefs.subtitleAlignX {
            PreferencesStore.shared.preferences.secondarySubtitleAlignX = prefs.subtitleAlignX
        }
    }

    private static let dualSubtitleStackGap = 12
    /// Keep stack inside the visible band (`sub-pos` > 100 sits past the bottom edge).
    private static let subtitlePosMin = 0
    private static let subtitlePosMax = 100

    /// Secondary below primary. If that would clip past the bottom, shift the whole stack up.
    private static func fittedDualStackPositions(preferredPrimary: Int) -> (primary: Int, secondary: Int) {
        let preferred = min(subtitlePosMax, max(subtitlePosMin, preferredPrimary))
        var primary = preferred
        var secondary = primary + dualSubtitleStackGap
        if secondary > subtitlePosMax {
            secondary = subtitlePosMax
            primary = max(subtitlePosMin, secondary - dualSubtitleStackGap)
        }
        return (primary, secondary)
    }

    private static func stackedSecondaryPos(primaryPos: Int) -> Int {
        fittedDualStackPositions(preferredPrimary: primaryPos).secondary
    }

    private func persistSubtitleSession() {
        guard let media = currentItem?.url else { return }
        let prefs = PreferencesStore.shared.preferences
        let primaryKey = activeSubtitleTrack.map {
            SubtitleSessionStore.trackKey(for: $0, sourceURL: externalSourceByTrackID[$0.id])
        }
        let secondaryKey = activeSecondarySubtitleTrack.map {
            SubtitleSessionStore.trackKey(for: $0, sourceURL: externalSourceByTrackID[$0.id])
        }
        let state = SubtitleSessionState(
            primaryKey: primaryKey,
            secondaryKey: secondaryKey,
            primaryAlignX: prefs.subtitleAlignX.rawValue,
            primaryAlignY: prefs.subtitleAlignY.rawValue,
            primaryPos: prefs.subtitlePos,
            secondaryAlignX: prefs.secondarySubtitleAlignX.rawValue,
            secondaryPos: prefs.secondarySubtitlePos,
            primaryDelay: subtitleDelay,
            secondaryDelay: secondarySubtitleDelay,
            audioDelay: audioDelay,
            syncTarget: syncTarget.rawValue,
            usingBakedLayout: false
        )
        SubtitleSessionStore.save(state, for: media)
    }

    private func restoreSubtitleSession(for item: MediaItem) async {
        refreshRememberedSubtitles()

        guard let state = SubtitleSessionStore.load(for: item.url) else {
            if !rememberedSubtitles.isEmpty {
                await restoreRememberedSubtitlesOnly(for: item)
            } else {
                applyAutomaticSubtitles(for: item)
            }
            return
        }

        PreferencesStore.shared.preferences.subtitleAlignX =
            SubtitleHorizontalAlign(rawValue: state.primaryAlignX) ?? .center
        PreferencesStore.shared.preferences.subtitleAlignY =
            SubtitleVerticalAlign(rawValue: state.primaryAlignY) ?? .bottom
        PreferencesStore.shared.preferences.subtitlePos = state.primaryPos
        PreferencesStore.shared.preferences.secondarySubtitleAlignX =
            PreferencesStore.shared.preferences.subtitleAlignX
        PreferencesStore.shared.preferences.secondarySubtitlePos = Self.stackedSecondaryPos(
            primaryPos: state.primaryPos
        )
        syncTarget = SubtitleSyncTarget(rawValue: state.syncTarget) ?? .primary
        subtitleDelay = state.primaryDelay
        secondarySubtitleDelay = state.secondaryDelay
        audioDelay = state.audioDelay
        controller.setAudioDelay(state.audioDelay)

        await restoreRememberedSubtitlesOnly(for: item)
        refreshTracks(force: true)
        applyLiveSubtitlePreferences()

        if let primaryKey = state.primaryKey,
           let primaryID = await resolveTrackID(forKey: primaryKey) {
            controller.selectTrack(id: primaryID, kind: .subtitle)
            refreshTracks(force: true)
        } else if state.primaryKey == nil {
            controller.disableSubtitles()
        }

        if let secondaryKey = state.secondaryKey,
           let secondaryID = await resolveTrackID(forKey: secondaryKey) {
            controller.selectSecondarySubtitleTrack(id: secondaryID)
            controller.setSecondarySubtitleVisible(true)
            refreshTracks(force: true)
        } else {
            controller.disableSecondarySubtitles()
        }

        controller.setSubtitleDelay(state.primaryDelay)
        controller.setSecondarySubtitleDelay(state.secondaryDelay)
        controller.setSubtitlePlacement(
            SubtitlePlacementAnchor.nearest(
                alignX: PreferencesStore.shared.preferences.subtitleAlignX,
                verticalPos: state.primaryPos
            )
        )
        refreshStackedSubtitlePositions()
        persistSubtitleSession()
        controller.showOSD("Restored subtitle layout")
    }

    private func restoreRememberedSubtitlesOnly(for item: MediaItem) async {
        let associations = SubtitleAssociationStore.associations(for: item.url)
        rememberedSubtitles = associations
        for association in associations {
            guard let url = SubtitleAssociationStore.resolveURL(association) else { continue }
            if externalSourceByTrackID.values.contains(where: { $0.path == url.path }) { continue }
            grantFileAccess(to: url)
            pendingExternalSourceURL = url
            if association.encodingID != PreferencesStore.shared.preferences.subtitleEncodingID {
                setSubtitleEncoding(association.encodingID)
            }
            controller.addSubtitle(url: url)
            try? await Task.sleep(for: .milliseconds(250))
            refreshTracks(force: true)
        }
    }

    private func urlFromExternalKey(_ key: String) -> URL? {
        guard key.hasPrefix("external:") else { return nil }
        let path = String(key.dropFirst("external:".count))
        let url = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func resolveTrackID(forKey key: String) async -> Int? {
        refreshTracks(force: true)
        if key.hasPrefix("external:") {
            let path = String(key.dropFirst("external:".count))
            if let id = externalSourceByTrackID.first(where: { $0.value.path == path })?.key {
                return id
            }
            if let track = subtitleTracks.first(where: { $0.externalFilename == path }) {
                return track.id
            }
            return nil
        }

        if let track = subtitleTracks.first(where: {
            SubtitleSessionStore.trackKey(for: $0, sourceURL: externalSourceByTrackID[$0.id]) == key
        }) {
            return track.id
        }

        let parts = key.split(separator: ":").map(String.init)
        if parts.count >= 2, parts[0] == "embedded", let ff = Int(parts[1]),
           let track = subtitleTracks.first(where: { $0.ffIndex == ff }) {
            return track.id
        }
        return nil
    }

    public func refreshCaptionTracks() {
        refreshTracks(force: true)
        syncTimingFromEngine()
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
            #if os(iOS) || os(tvOS)
            if resumePausedAfterReload {
                resumePausedAfterReload = false
                controller.pause()
                state = .paused
                EventBus.shared.emit(.stateChanged(state))
            } else {
                play()
            }
            #else
            play()
            #endif
            if let item = currentItem {
                EventBus.shared.emit(.fileLoaded(item))
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    refreshTracks(force: true)
                    applyLiveSubtitlePreferences()
                    await restoreSubtitleSession(for: item)
                }
            }
            #if os(iOS) || os(tvOS)
            skipExtrasOnNextFileLoad = false
            #endif
        case .endFile(let reason, let error):
            handleEndFile(reason: reason, error: error)
        case .propertyChanged:
            refreshInfo()
            refreshTracks()
            // With keep-open=yes, EOF often does not unload the file, so END_FILE may
            // never arrive — advance the playlist from eof-reached instead.
            if controller.hasReachedEOF {
                handlePlaybackFinished()
            }
        }
    }

    private func applyAutomaticSubtitles(for item: MediaItem) {
        #if os(iOS) || os(tvOS)
        guard !skipExtrasOnNextFileLoad else { return }
        #endif
        guard !subtitlesAreActive else { return }

        let prefs = PreferencesStore.shared.preferences
        var candidates = embeddedSubtitleTracks
        if prefs.forcedSubtitlesOnly {
            let forced = candidates.filter(\.isForced)
            if !forced.isEmpty { candidates = forced }
        }
        if prefs.preferSDHSubtitles {
            let sdh = candidates.filter(\.isLikelySDH)
            if !sdh.isEmpty { candidates = sdh }
        }

        let preferred = prefs.preferredSubtitleLanguage.lowercased()
        let embedded = candidates.first(where: {
            ($0.language ?? "").lowercased().hasPrefix(preferred) && !preferred.isEmpty
        })
            ?? candidates.first(where: \.isDefault)
            ?? candidates.first

        if let embedded {
            selectSubtitleTrack(id: embedded.id)
            return
        }

        guard prefs.autoLoadSubtitles, item.url.isFileURL else { return }
        let matches = SubtitleFileMatcher.findLocalSubtitles(for: item.url)
        if let match = SubtitleFileMatcher.preferredMatch(
            from: matches,
            preferredLanguage: prefs.preferredSubtitleLanguage
        ) {
            loadExternalSubtitle(url: match.url)
        }
    }

    private func refreshTracks(force: Bool = false) {
        guard state.isActive || state == .loaded else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastTrackRefresh) >= 0.35 else { return }
        lastTrackRefresh = now

        let previousSecondaryID = activeSecondarySubtitleTrackID
        let snapshot = controller.trackSnapshot()
        tracks = snapshot.tracks
        activeSubtitleTrackID = snapshot.activeSubtitleTrackID
        activeSecondarySubtitleTrackID = snapshot.activeSecondarySubtitleTrackID

        if let pending = pendingExternalSourceURL {
            let known = Set(externalSourceByTrackID.keys)
            if let newest = snapshot.externalSubtitleTracks
                .map(\.id)
                .filter({ !known.contains($0) })
                .max() {
                externalSourceByTrackID[newest] = pending
            }
            pendingExternalSourceURL = nil
        }

        if let secondaryID = activeSecondarySubtitleTrackID {
            controller.setSecondarySubtitleVisible(true)
            if previousSecondaryID != secondaryID {
                refreshStackedSubtitlePositions()
            }
        } else if previousSecondaryID != nil {
            // Secondary just cleared — restore primary to its normal placement.
            refreshStackedSubtitlePositions()
        }

        syncTimingFromEngine()
        EventBus.shared.emit(.tracksUpdated(tracks))
    }

    private func syncTimingFromEngine() {
        subtitleDelay = controller.subtitleDelay()
        secondarySubtitleDelay = controller.secondarySubtitleDelay()
        audioDelay = controller.audioDelay()
        subtitleSpeed = controller.subtitleSpeed()
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
        if controller.hasReachedEOF {
            handlePlaybackFinished()
            return
        }
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
        // Silent + async — notifying the library UI / writing JSON on the main
        // thread was hitching playback every save interval.
        WatchProgressStore.record(
            item: item,
            position: info.position,
            duration: info.duration,
            notify: false
        )
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
