import Foundation

public struct KinemaDeepLink: Sendable, Equatable {
    public enum Action: String, Sendable {
        case open
        case weblink
    }

    public let action: Action
    public let mediaURL: URL?
    public let newWindow: Bool
    public let pip: Bool
    public let fullScreen: Bool
    public let enqueue: Bool
    public let mpvOptions: [String: String]

    public init(
        action: Action,
        mediaURL: URL?,
        newWindow: Bool = false,
        pip: Bool = false,
        fullScreen: Bool = false,
        enqueue: Bool = false,
        mpvOptions: [String: String] = [:]
    ) {
        self.action = action
        self.mediaURL = mediaURL
        self.newWindow = newWindow
        self.pip = pip
        self.fullScreen = fullScreen
        self.enqueue = enqueue
        self.mpvOptions = mpvOptions
    }
}

public enum DeepLinkParser {
  public static func parse(_ url: URL) -> KinemaDeepLink? {
        guard url.scheme?.lowercased() == "kinema" else { return nil }

        let action: KinemaDeepLink.Action
        switch url.host?.lowercased() {
        case "open", "weblink":
            action = url.host?.lowercased() == "weblink" ? .weblink : .open
        default:
            return nil
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        var mediaURL: URL?
        var newWindow = false
        var pip = false
        var fullScreen = false
        var enqueue = false
        var mpvOptions: [String: String] = [:]

        for item in components.queryItems ?? [] {
            switch item.name.lowercased() {
            case "url":
                if let value = item.value {
                    mediaURL = URL(string: value) ?? URL(fileURLWithPath: value)
                }
            case "new_window":
                newWindow = item.value == "1" || item.value?.lowercased() == "true"
            case "pip":
                pip = item.value == "1" || item.value?.lowercased() == "true"
            case "full_screen":
                fullScreen = item.value == "1" || item.value?.lowercased() == "true"
            case "enqueue":
                enqueue = item.value == "1" || item.value?.lowercased() == "true"
            default:
                if item.name.hasPrefix("mpv_"), let value = item.value {
                    let key = String(item.name.dropFirst(4)).replacingOccurrences(of: "_", with: "-")
                    mpvOptions[key] = value
                }
            }
        }

        return KinemaDeepLink(
            action: action,
            mediaURL: mediaURL,
            newWindow: newWindow,
            pip: pip,
            fullScreen: fullScreen,
            enqueue: enqueue,
            mpvOptions: mpvOptions
        )
    }

    /// Builds an open link for parameters the app currently applies.
    /// Reserved query keys (`pip`, `full_screen`, `enqueue`, `mpv_*`) are parsed
    /// but not emitted here until their handlers ship.
    public static func buildOpenURL(
        mediaURL: URL,
        newWindow: Bool = false
    ) -> URL? {
        var components = URLComponents()
        components.scheme = "kinema"
        components.host = "open"
        var items = [
            URLQueryItem(name: "url", value: mediaURL.absoluteString)
        ]
        if newWindow {
            items.append(URLQueryItem(name: "new_window", value: "1"))
        }
        components.queryItems = items
        return components.url
    }
}
