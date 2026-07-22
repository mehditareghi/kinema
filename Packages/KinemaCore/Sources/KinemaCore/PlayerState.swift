import Foundation

/// Playback lifecycle states mirroring IINA's PlayerState machine.
public enum PlayerState: String, Sendable, Equatable {
    case idle
    case loading
    case starting
    case loaded
    case playing
    case paused
    case stopping
    case error
}

public extension PlayerState {
    var isActive: Bool {
        switch self {
        case .loading, .starting, .loaded, .playing, .paused:
            return true
        case .idle, .stopping, .error:
            return false
        }
    }

    var isPlaying: Bool { self == .playing }
}
