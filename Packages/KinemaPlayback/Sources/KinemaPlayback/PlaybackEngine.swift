import Foundation
import KinemaCore
import KinemaMPV

@MainActor
public protocol PlaybackEngine: AnyObject {
    var state: PlayerState { get }
    var info: PlaybackInfo { get }
    var currentItem: MediaItem? { get }
    var playlist: [MediaItem] { get }
    var tracks: [Track] { get }
    var chapters: [Chapter] { get }
    var renderSurface: MPVRenderSurface { get }

    func load(_ item: MediaItem, startPosition: TimeInterval?) async throws
    func play()
    func pause()
    func togglePlayPause()
    func seek(to time: TimeInterval)
    func seekRelative(_ delta: TimeInterval)
    func stop()
    func setVolume(_ volume: Double)
    func setSpeed(_ speed: Double)
    func setMuted(_ muted: Bool)
    func addToPlaylist(_ items: [MediaItem])
    func playNextInPlaylist(_ items: [MediaItem])
    func movePlaylist(fromOffsets: IndexSet, toOffset: Int)
    func playNext()
    func playPrevious()
    func loadSubtitle(url: URL)
    func cycleSubtitle()
    func disableSubtitles()
    func selectSubtitleTrack(id: Int)
    func setSubtitleFontSize(_ size: Int)
    func selectTrack(id: Int, kind: TrackKind)

    var activeSubtitleTrackID: Int? { get }
    var subtitlesAreActive: Bool { get }
    var subtitleTracks: [Track] { get }
}
