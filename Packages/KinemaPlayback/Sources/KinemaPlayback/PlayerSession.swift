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
    /// End-of-episode series offer (credits lead-in or EOF).
    public private(set) var upNextOffer: UpNextOffer?
    /// A–B loop start; `nil` means unset (`ab-loop-a=no`).
    public private(set) var abLoopA: TimeInterval?
    /// A–B loop end; `nil` means unset (`ab-loop-b=no`).
    public private(set) var abLoopB: TimeInterval?
    /// True when the loaded video looks like HDR (PQ/HLG / BT.2020 peak).
    public private(set) var isHDRContent = false
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

    public var audioTracks: [Track] {
        tracks.filter { $0.kind == .audio }
    }

    public var activeAudioTrack: Track? {
        audioTracks.first(where: \.isSelected)
    }

    public var embeddedSubtitleTracks: [Track] {
        subtitleTracks.filter { !$0.isExternal }
    }

    public var externalSubtitleTracks: [Track] {
        subtitleTracks.filter { $0.isExternal }
    }

    /// Absolute paths of external subtitle files currently attached to the player.
    public var loadedExternalSubtitlePaths: Set<String> {
        var paths = Set(externalSourceByTrackID.values.map { $0.standardizedFileURL.path })
        for track in externalSubtitleTracks {
            if let filename = track.externalFilename, !filename.isEmpty {
                paths.insert(URL(fileURLWithPath: filename).standardizedFileURL.path)
            }
        }
        return paths
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
    private var lastChapterRefresh = Date.distantPast
    private var lastProgressSave = Date.distantPast
    /// After "Not now", don't re-offer Up Next for this media until a new title loads.
    private var upNextSuppressedForMediaID: String?
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
        controller.setMute(preferences.isMuted)
        applyAudioPipeline()
        applyHDRToneMappingPreferences()
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
        setUpNextOffer(nil)
        upNextSuppressedForMediaID = nil
        clearABLoopState(applyToEngine: false)
        isHDRContent = false
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
        controller.setMute(options.isMuted)
        applyAudioPipeline()
        applyHDRToneMappingPreferences()
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
        setUpNextOffer(nil)
        upNextSuppressedForMediaID = nil
        clearABLoopState(applyToEngine: isPrepared)
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

    /// Index of the chapter that contains the current playhead, if any.
    public var currentChapterIndex: Int? {
        guard !chapters.isEmpty else { return nil }
        let position = info.position
        var result = 0
        for (index, chapter) in chapters.enumerated() {
            if chapter.time <= position + 0.05 {
                result = index
            } else {
                break
            }
        }
        return result
    }

    public var currentChapter: Chapter? {
        guard let currentChapterIndex else { return nil }
        return chapters[currentChapterIndex]
    }

    public var hasChapters: Bool { !chapters.isEmpty }

    public func seekToChapter(_ chapter: Chapter) {
        seek(to: max(0, chapter.time))
    }

    public func seekToChapter(at index: Int) {
        guard chapters.indices.contains(index) else { return }
        seekToChapter(chapters[index])
    }

    /// Previous chapter, or restart the current chapter if more than ~2s into it.
    public func playPreviousChapter() {
        guard !chapters.isEmpty else { return }
        guard let index = currentChapterIndex else {
            seekToChapter(chapters[0])
            return
        }
        let chapter = chapters[index]
        if info.position - chapter.time > 2 {
            seekToChapter(chapter)
        } else if index > 0 {
            seekToChapter(chapters[index - 1])
        } else {
            seek(to: 0)
        }
    }

    public func playNextChapter() {
        guard let index = currentChapterIndex, index + 1 < chapters.count else { return }
        seekToChapter(chapters[index + 1])
    }

    public var hasABLoopA: Bool { abLoopA != nil }
    public var hasABLoopB: Bool { abLoopB != nil }
    public var isABLooping: Bool { abLoopA != nil && abLoopB != nil }

    /// mpv-style cycle: set A → set B → clear.
    @discardableResult
    public func cycleABLoop() -> String {
        if isABLooping {
            clearABLoop()
            return "A–B loop cleared"
        }
        if let start = abLoopA {
            var end = info.position
            var resolvedStart = start
            if end < resolvedStart {
                swap(&resolvedStart, &end)
            }
            // Avoid a zero-length loop from a double-tap.
            if abs(end - resolvedStart) < 0.15 {
                end = resolvedStart + 0.15
            }
            abLoopA = resolvedStart
            abLoopB = end
            controller.setABLoopA(resolvedStart)
            controller.setABLoopB(end)
            seek(to: resolvedStart)
            return "A–B loop \(formatABLoopOSD(start: resolvedStart, end: end))"
        }

        let point = info.position
        abLoopA = point
        abLoopB = nil
        controller.setABLoopA(point)
        controller.setABLoopB(nil)
        return "Loop A · \(formatTimeCode(point))"
    }

    public func clearABLoop() {
        clearABLoopState(applyToEngine: true)
    }

    private func clearABLoopState(applyToEngine: Bool) {
        abLoopA = nil
        abLoopB = nil
        if applyToEngine {
            controller.clearABLoop()
        }
    }

    private func formatABLoopOSD(start: TimeInterval, end: TimeInterval) -> String {
        "\(formatTimeCode(start)) → \(formatTimeCode(end))"
    }

    private func formatTimeCode(_ interval: TimeInterval) -> String {
        guard interval.isFinite, interval >= 0 else { return "0:00" }
        let total = Int(interval.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
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
        let clamped = min(KinemaPreferences.volumeMax, max(0, volume))
        controller.setVolume(clamped)
        PreferencesStore.shared.preferences.volume = clamped
        refreshInfo(force: true)
    }

    public func setSpeed(_ speed: Double) {
        controller.setSpeed(speed)
        PreferencesStore.shared.preferences.speed = speed
        refreshInfo(force: true)
    }

    public func setMuted(_ muted: Bool) {
        controller.setMute(muted)
        PreferencesStore.shared.preferences.isMuted = muted
        refreshInfo(force: true)
    }

    public func applyAudioPipeline() {
        guard isPrepared || controller.isReady else { return }
        let prefs = PreferencesStore.shared.preferences
        controller.setAudioFilters(AudioFilterGraph.build(from: prefs))
        controller.setReplayGain(prefs.replayGain.mpvValue)
        let device = prefs.audioOutputDeviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        controller.setAudioDevice(device.isEmpty ? "auto" : device)
    }

    public func applyHDRToneMappingPreferences() {
        guard isPrepared || controller.isReady else { return }
        let prefs = PreferencesStore.shared.preferences
        let peak = KinemaPreferences.clampHDRTargetPeak(prefs.hdrTargetPeak)
        controller.applyHDRToneMapping(
            mode: prefs.hdrToneMappingMode.mpvToneMapping,
            computePeak: prefs.hdrToneMappingMode.mpvHDRComputePeak,
            targetPeak: peak
        )
    }

    public struct AudioOutputDevice: Identifiable, Hashable, Sendable {
        public let id: String
        public let description: String
    }

    public func audioOutputDevices() -> [AudioOutputDevice] {
        controller.audioDeviceList().map {
            AudioOutputDevice(id: $0.id, description: $0.description)
        }
    }

    public func selectAudioTrack(id: Int?) {
        if let id {
            controller.selectTrack(id: id, kind: .audio)
            let label = audioTracks.first(where: { $0.id == id }).map(Self.audioTrackLabel) ?? "Audio \(id)"
            controller.showOSD(label)
        } else {
            controller.disableAudioTrack()
            controller.showOSD("Audio off")
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            refreshTracks(force: true)
        }
    }

    public func cycleAudio() {
        controller.cycleAudio()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            refreshTracks(force: true)
            if let track = activeAudioTrack {
                controller.showOSD(Self.audioTrackLabel(track))
            }
        }
    }

    public static func audioTrackLabel(_ track: Track) -> String {
        var parts: [String] = []
        if let language = track.language, !language.isEmpty {
            parts.append(language.uppercased())
        }
        if !track.title.isEmpty {
            parts.append(track.title)
        }
        if parts.isEmpty {
            parts.append("Audio \(track.id)")
        }
        return parts.joined(separator: " · ")
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
        playNext(startFromBeginning: false)
    }

    public func playNext(startFromBeginning: Bool) {
        guard playlistIndex + 1 < playlist.count else { return }
        playPlaylistItem(at: playlistIndex + 1, startFromBeginning: startFromBeginning)
    }

    public func playPrevious() {
        guard !playlist.isEmpty else { return }
        playPlaylistItem(at: max(playlistIndex - 1, 0), startFromBeginning: false)
    }

    /// Peek the upcoming Up Next title when a credits card would apply (thumbnail warm-up).
    public func peekSeriesUpNext() -> (item: MediaItem, episode: MediaEpisodeIdentity?)? {
        guard PreferencesStore.shared.preferences.seriesUpNextEnabled else { return nil }
        guard let candidate = nextUpNextCandidate() else { return nil }
        return (candidate.item, candidate.episode)
    }

    public func confirmUpNext() {
        guard let offer = upNextOffer else { return }
        markCurrentItemWatched()
        setUpNextOffer(nil)
        playPlaylistItem(at: offer.playlistIndex, startFromBeginning: true)
    }

    /// Dismiss the card; credits keep playing (or stay on the finished frame).
    public func dismissUpNext() {
        guard upNextOffer != nil else { return }
        if let current = currentItem {
            upNextSuppressedForMediaID = WatchProgressStore.mediaID(for: current.url)
        }
        setUpNextOffer(nil)
    }

    private func setUpNextOffer(_ offer: UpNextOffer?) {
        guard upNextOffer != offer else { return }
        upNextOffer = offer
        EventBus.shared.emit(.upNextOfferChanged)
    }

    private func markCurrentItemWatched() {
        guard let item = currentItem else { return }
        let duration = max(info.duration, info.position, 1)
        WatchProgressStore.markWatched(item: item, duration: duration)
        if let context = historyContext {
            HistoryStore.recordPlayback(
                context: context,
                item: item,
                position: duration,
                duration: duration
            )
        }
    }

    private struct UpNextCandidate {
        let item: MediaItem
        let episode: MediaEpisodeIdentity?
        let playlistIndex: Int
    }

    /// Prefer the next series file of the same show (part-aware: E00 → E00.Part2 → E01);
    /// otherwise the immediate next playlist item (folder / multi-select play).
    private func nextUpNextCandidate() -> UpNextCandidate? {
        guard let current = currentItem, !playlist.isEmpty else { return nil }
        let start = min(playlistIndex + 1, playlist.count)
        guard start < playlist.count else { return nil }

        let remaining = Array(playlist[start...])
        let remainingURLs = remaining.map(\.url)

        if let series = MediaSeriesOrganizer.nextEpisode(after: current.url, in: remainingURLs),
           let index = playlistIndex(for: series.url, in: playlist) {
            return UpNextCandidate(item: playlist[index], episode: series.identity, playlistIndex: index)
        }

        let immediate = playlist[start]
        if let identity = MediaSeriesOrganizer.seriesContinuation(from: current.url, to: immediate.url) {
            return UpNextCandidate(item: immediate, episode: identity, playlistIndex: start)
        }

        return UpNextCandidate(item: immediate, episode: nil, playlistIndex: start)
    }

    private func presentUpNextIfPossible() -> Bool {
        guard PreferencesStore.shared.preferences.seriesUpNextEnabled else { return false }
        guard let current = currentItem else { return false }
        let mediaID = WatchProgressStore.mediaID(for: current.url)
        guard upNextSuppressedForMediaID != mediaID else { return false }
        guard let candidate = nextUpNextCandidate() else { return false }
        setUpNextOffer(
            UpNextOffer(
                item: candidate.item,
                episode: candidate.episode,
                playlistIndex: candidate.playlistIndex
            )
        )
        return true
    }

    /// Netflix-style: float the card during the credits window while playback continues.
    private func considerCreditsUpNextOffer() {
        guard upNextOffer == nil else { return }
        guard state == .playing else { return }
        guard PreferencesStore.shared.preferences.seriesUpNextEnabled else { return }
        guard let current = currentItem else { return }
        let mediaID = WatchProgressStore.mediaID(for: current.url)
        guard upNextSuppressedForMediaID != mediaID else { return }

        let duration = info.duration
        let position = info.position
        guard duration >= UpNextOffer.minimumDurationForCreditsLeadIn else { return }
        let remaining = duration - position
        guard remaining > 0.35, remaining <= UpNextOffer.creditsLeadIn else { return }
        _ = presentUpNextIfPossible()
    }

    private func playPlaylistItem(at index: Int, startFromBeginning: Bool) {
        guard playlist.indices.contains(index) else { return }
        setUpNextOffer(nil)
        playlistIndex = index
        let item = playlist[index]
        Task {
            do {
                try await load(item, startPosition: startFromBeginning ? 0 : nil)
                play()
            } catch {
                NSLog(
                    "Kinema: failed to play up-next %@ — %@",
                    item.url.lastPathComponent,
                    error.localizedDescription
                )
                if index + 1 < playlist.count {
                    playPlaylistItem(at: index + 1, startFromBeginning: startFromBeginning)
                } else {
                    state = .idle
                    EventBus.shared.emit(.playlistEnded)
                }
            }
        }
    }

    public func loadSubtitle(url: URL) {
        loadExternalSubtitle(url: url)
    }

    public func loadExternalSubtitle(url: URL, encodingID: String? = nil, remember: Bool = false) {
        if let encodingID {
            setSubtitleEncoding(encodingID)
        }
        if isExternalSubtitleAlreadyLoaded(url) {
            if remember, let media = currentItem?.url {
                _ = SubtitleAssociationStore.add(
                    for: media,
                    subtitleURL: url,
                    encodingID: encodingID ?? PreferencesStore.shared.preferences.subtitleEncodingID
                )
                refreshRememberedSubtitles()
            }
            return
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
        SubtitleAssociationStore.pruneSidecarAssociations(for: media)
        rememberedSubtitles = SubtitleAssociationStore.associations(for: media)
    }

    private func isExternalSubtitleAlreadyLoaded(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        if externalSourceByTrackID.values.contains(where: { $0.standardizedFileURL.path == path }) {
            return true
        }
        return subtitleTracks.contains { track in
            guard track.isExternal, let external = track.externalFilename else { return false }
            return URL(fileURLWithPath: external).standardizedFileURL.path == path
        }
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
        SubtitleAssociationStore.pruneSidecarAssociations(for: item.url)
        let associations = SubtitleAssociationStore.associations(for: item.url)
        rememberedSubtitles = associations
        refreshTracks(force: true)
        for association in associations {
            guard let url = SubtitleAssociationStore.resolveURL(association) else { continue }
            if isExternalSubtitleAlreadyLoaded(url) { continue }
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
                    refreshChapters(force: true)
                    applyLiveSubtitlePreferences()
                    applyAudioPipeline()
                    applyPreferredAudioLanguage()
                    refreshHDRContentFlag()
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
            refreshChapters()
            // With keep-open=yes, EOF often does not unload the file, so END_FILE may
            // never arrive — advance the playlist from eof-reached instead.
            if controller.hasReachedEOF {
                handlePlaybackFinished()
            }
        }
    }

    private func applyPreferredAudioLanguage() {
        let preferred = PreferencesStore.shared.preferences.preferredAudioLanguage
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !preferred.isEmpty else { return }
        let candidates = audioTracks
        guard !candidates.isEmpty else { return }

        // If a track is already selected and matches preference, keep it.
        if let active = activeAudioTrack,
           (active.language ?? "").lowercased().hasPrefix(preferred) {
            return
        }

        let match = candidates.first(where: {
            ($0.language ?? "").lowercased().hasPrefix(preferred)
        }) ?? candidates.first(where: \.isDefault)

        if let match, !match.isSelected {
            controller.selectTrack(id: match.id, kind: .audio)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                refreshTracks(force: true)
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

    private func refreshChapters(force: Bool = false) {
        guard state.isActive || state == .loaded else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastChapterRefresh) >= 0.5 else { return }
        lastChapterRefresh = now

        let parsed = controller.chapterSnapshot()
        guard parsed != chapters else { return }
        chapters = parsed
        EventBus.shared.emit(.chaptersUpdated(chapters))
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
        markCurrentItemWatched()

        // Credits card already visible — freeze on the last frame until Play Now / Not now.
        if upNextOffer != nil {
            controller.pause()
            state = .paused
            info.isPaused = true
            EventBus.shared.emit(.stateChanged(state))
            EventBus.shared.emit(.playbackInfoUpdated(info))
            return
        }

        if let candidate = nextUpNextCandidate() {
            if presentUpNextIfPossible() {
                controller.pause()
                state = .paused
                info.isPaused = true
                EventBus.shared.emit(.stateChanged(state))
                EventBus.shared.emit(.playbackInfoUpdated(info))
                return
            }

            // Pref off / suppressed — still advance to the part-aware next candidate.
            state = .loading
            EventBus.shared.emit(.stateChanged(state))
            playPlaylistItem(at: candidate.playlistIndex, startFromBeginning: true)
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
        let changed = abs(updated.position - info.position) > 0.05
            || updated.isPaused != info.isPaused
            || abs(updated.duration - info.duration) > 0.5
            || (info.duration <= 0 && updated.duration > 0)

        if changed {
            info = updated
            if state == .loaded || state == .playing || state == .paused {
                state = updated.isPaused ? .paused : .playing
            }
            maybeSaveWatchProgress()
            EventBus.shared.emit(.playbackInfoUpdated(info))
        }

        // Evaluate credits Up Next even when the position delta was tiny.
        if !updated.isPaused {
            if !changed, updated.duration > 0 {
                info.position = updated.position
                info.duration = updated.duration
            }
            considerCreditsUpNextOffer()
        }
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
        if force {
            refreshHDRContentFlag()
        }
        EventBus.shared.emit(.playbackInfoUpdated(info))
    }

    private func refreshHDRContentFlag() {
        let detected = controller.isHDRContent()
        guard detected != isHDRContent else { return }
        isHDRContent = detected
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
