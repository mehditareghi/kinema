import Foundation

public enum KinemaEvent: Sendable {
    case stateChanged(PlayerState)
    case playbackInfoUpdated(PlaybackInfo)
    case fileLoaded(MediaItem)
    case fileEnded
    case playlistEnded
    case error(String)
    case tracksUpdated([Track])
    case chaptersUpdated([Chapter])
    case upNextOfferChanged
    case osdMessage(String)
    case watchProgressUpdated
    case playbillUpdated
    case playbillMatchPromptRequested
    case resumedFrom(TimeInterval)
    case libraryChanged
}

@MainActor
public final class EventBus {
    public static let shared = EventBus()

    private var handlers: [UUID: (KinemaEvent) -> Void] = [:]

    private init() {}

    public func subscribe(_ handler: @escaping (KinemaEvent) -> Void) -> UUID {
        let id = UUID()
        handlers[id] = handler
        return id
    }

    public func unsubscribe(_ id: UUID) {
        handlers.removeValue(forKey: id)
    }

    public func emit(_ event: KinemaEvent) {
        for handler in handlers.values {
            handler(event)
        }
    }
}
