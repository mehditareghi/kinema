import Foundation

public struct MediaItem: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var url: URL
    public var title: String
    public var artworkURL: URL?

    public init(id: UUID = UUID(), url: URL, title: String? = nil, artworkURL: URL? = nil) {
        self.id = id
        self.url = url
        self.title = title ?? url.deletingPathExtension().lastPathComponent
        self.artworkURL = artworkURL
    }
}

public struct Track: Identifiable, Hashable, Sendable {
    public let id: Int
    public let kind: TrackKind
    public let title: String
    public let language: String?
    public let isSelected: Bool
    public let isExternal: Bool
    public let isDefault: Bool
    public let isForced: Bool

    public init(
        id: Int,
        kind: TrackKind,
        title: String,
        language: String? = nil,
        isSelected: Bool = false,
        isExternal: Bool = false,
        isDefault: Bool = false,
        isForced: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.language = language
        self.isSelected = isSelected
        self.isExternal = isExternal
        self.isDefault = isDefault
        self.isForced = isForced
    }
}

public enum TrackKind: String, Sendable {
    case video
    case audio
    case subtitle
}

public struct Chapter: Identifiable, Hashable, Sendable {
    public let id: Int
    public let title: String
    public let time: TimeInterval

    public init(id: Int, title: String, time: TimeInterval) {
        self.id = id
        self.title = title
        self.time = time
    }
}

public struct PlaybackInfo: Sendable, Equatable {
    public var position: TimeInterval
    public var duration: TimeInterval
    public var isPaused: Bool
    public var volume: Double
    public var speed: Double
    public var title: String

    public init(
        position: TimeInterval = 0,
        duration: TimeInterval = 0,
        isPaused: Bool = true,
        volume: Double = 100,
        speed: Double = 1,
        title: String = ""
    ) {
        self.position = position
        self.duration = duration
        self.isPaused = isPaused
        self.volume = volume
        self.speed = speed
        self.title = title
    }
}
