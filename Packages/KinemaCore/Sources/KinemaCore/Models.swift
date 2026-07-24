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
    public let codec: String?
    public let isHearingImpaired: Bool
    public let isSecondarySelected: Bool
    /// ffmpeg/libav stream index when available (for embedded extract).
    public let ffIndex: Int?
    /// Absolute path when this is an external file track.
    public let externalFilename: String?

    public init(
        id: Int,
        kind: TrackKind,
        title: String,
        language: String? = nil,
        isSelected: Bool = false,
        isExternal: Bool = false,
        isDefault: Bool = false,
        isForced: Bool = false,
        codec: String? = nil,
        isHearingImpaired: Bool = false,
        isSecondarySelected: Bool = false,
        ffIndex: Int? = nil,
        externalFilename: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.language = language
        self.isSelected = isSelected
        self.isExternal = isExternal
        self.isDefault = isDefault
        self.isForced = isForced
        self.codec = codec
        self.isHearingImpaired = isHearingImpaired
        self.isSecondarySelected = isSecondarySelected
        self.ffIndex = ffIndex
        self.externalFilename = externalFilename
    }

    public var isLikelySDH: Bool {
        if isHearingImpaired { return true }
        let haystack = "\(title) \(language ?? "")".uppercased()
        return haystack.contains("SDH") || haystack.contains("CC") || haystack.contains("HI")
            || haystack.contains("HEARING")
    }

    public var codecBadge: String? {
        guard let codec, !codec.isEmpty else { return nil }
        let lower = codec.lowercased()
        if lower.contains("pgs") || lower.contains("hdmv") { return "PGS" }
        if lower.contains("vobsub") || lower.contains("dvd_subtitle") { return "VobSub" }
        if lower.contains("dvb") { return "DVB" }
        if lower.contains("teletext") || lower.contains("ttxt") { return "Teletext" }
        if lower.contains("ass") || lower.contains("ssa") { return "ASS" }
        if lower.contains("webvtt") || lower.contains("vtt") { return "VTT" }
        if lower.contains("subrip") || lower.contains("srt") { return "SRT" }
        if lower.contains("sami") || lower.contains("smi") { return "SAMI" }
        return codec.uppercased()
    }
}

public enum TrackKind: String, Sendable {
    case video
    case audio
    case subtitle
}

public enum SubtitleSyncTarget: String, CaseIterable, Identifiable, Sendable {
    case primary
    case secondary
    case both

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .primary: return "Primary"
        case .secondary: return "Secondary"
        case .both: return "Both"
        }
    }
}

public enum SubtitleHorizontalAlign: String, CaseIterable, Identifiable, Sendable {
    case left
    case center
    case right

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .left: return "Left"
        case .center: return "Center"
        case .right: return "Right"
        }
    }
}

public enum SubtitleVerticalAlign: String, CaseIterable, Identifiable, Sendable {
    case top
    case center
    case bottom

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .top: return "Top"
        case .center: return "Middle"
        case .bottom: return "Bottom"
        }
    }
}

/// Screen anchor for a subtitle track (3×3 grid).
public enum SubtitlePlacementAnchor: String, CaseIterable, Identifiable, Sendable {
    case topLeft
    case topCenter
    case topRight
    case centerLeft
    case center
    case centerRight
    case bottomLeft
    case bottomCenter
    case bottomRight

    public var id: String { rawValue }

    public var alignX: SubtitleHorizontalAlign {
        switch self {
        case .topLeft, .centerLeft, .bottomLeft: return .left
        case .topCenter, .center, .bottomCenter: return .center
        case .topRight, .centerRight, .bottomRight: return .right
        }
    }

    public var alignY: SubtitleVerticalAlign {
        switch self {
        case .topLeft, .topCenter, .topRight: return .top
        case .centerLeft, .center, .centerRight: return .center
        case .bottomLeft, .bottomCenter, .bottomRight: return .bottom
        }
    }

    /// Default vertical `sub-pos` / `secondary-sub-pos` for this anchor.
    public var verticalPos: Int {
        switch alignY {
        case .top: return 8
        case .center: return 50
        case .bottom: return 100
        }
    }

    /// ASS numpad alignment (1–9) for libass force-style.
    public var assAlignment: Int {
        switch self {
        case .bottomLeft: return 1
        case .bottomCenter: return 2
        case .bottomRight: return 3
        case .centerLeft: return 4
        case .center: return 5
        case .centerRight: return 6
        case .topLeft: return 7
        case .topCenter: return 8
        case .topRight: return 9
        }
    }

    public var accessibilityLabel: String {
        "\(alignY.displayName) \(alignX.displayName)"
    }

    public static func nearest(alignX: SubtitleHorizontalAlign, verticalPos: Int) -> SubtitlePlacementAnchor {
        let alignY: SubtitleVerticalAlign
        switch verticalPos {
        case ...33: alignY = .top
        case 34...66: alignY = .center
        default: alignY = .bottom
        }
        switch (alignY, alignX) {
        case (.top, .left): return .topLeft
        case (.top, .center): return .topCenter
        case (.top, .right): return .topRight
        case (.center, .left): return .centerLeft
        case (.center, .center): return .center
        case (.center, .right): return .centerRight
        case (.bottom, .left): return .bottomLeft
        case (.bottom, .center): return .bottomCenter
        case (.bottom, .right): return .bottomRight
        }
    }
}

public enum SubtitleASSOverrideMode: String, CaseIterable, Identifiable, Sendable {
    case no
    case scale
    case force
    case yes

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .no: return "Preserve ASS styles"
        case .scale: return "Scale ASS only"
        case .force: return "Force style overrides"
        case .yes: return "Apply text styles"
        }
    }
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
