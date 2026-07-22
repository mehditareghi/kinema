import Foundation
import KinemaCore

public struct SubtitleMatch: Sendable, Identifiable {
    public let id: URL
    public let url: URL
    public let label: String
    public let languageCode: String?

    public init(url: URL, label: String, languageCode: String? = nil) {
        self.id = url
        self.url = url
        self.label = label
        self.languageCode = languageCode
    }
}

public enum SubtitleFileMatcher {
    private static let extensions = ["srt", "ass", "ssa", "vtt", "sub"]

    public static func findLocalSubtitles(for mediaURL: URL) -> [SubtitleMatch] {
        let directory = mediaURL.deletingLastPathComponent()
        let baseName = mediaURL.deletingPathExtension().lastPathComponent
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return [] }

        return files.compactMap { fileURL in
            guard SubtitleFileMatcher.extensions.contains(fileURL.pathExtension.lowercased()) else {
                return nil
            }
            let name = fileURL.deletingPathExtension().lastPathComponent
            guard name == baseName || name.hasPrefix(baseName + ".") || name.hasPrefix(baseName + "_") else {
                return nil
            }
            let lang = extractLanguage(from: name, base: baseName)
            return SubtitleMatch(url: fileURL, label: fileURL.lastPathComponent, languageCode: lang)
        }
    }

    private static func extractLanguage(from name: String, base: String) -> String? {
        let remainder = name.dropFirst(base.count).trimmingCharacters(in: CharacterSet(charactersIn: "._"))
        return remainder.isEmpty ? nil : String(remainder)
    }

    public static func preferredMatch(from matches: [SubtitleMatch]) -> SubtitleMatch? {
        guard !matches.isEmpty else { return nil }
        if let english = matches.first(where: { ($0.languageCode ?? "").lowercased().hasPrefix("en") }) {
            return english
        }
        return matches.first
    }
}

public enum SubtitleLabels {
    public static func displayName(for track: Track) -> String {
        var parts: [String] = []

        if !track.title.isEmpty {
            parts.append(track.title)
        } else if let language = track.language, !language.isEmpty {
            parts.append(languageDisplayName(language))
        } else {
            parts.append("Track \(track.id)")
        }

        var badges: [String] = []
        if track.isDefault { badges.append("Default") }
        if track.isForced { badges.append("Forced") }
        if track.isExternal { badges.append("External") } else if track.kind == .subtitle {
            badges.append("Embedded")
        }

        if badges.isEmpty {
            return parts.joined(separator: " · ")
        }
        return "\(parts[0]) · \(badges.joined(separator: ", "))"
    }

    public static func displayName(for match: SubtitleMatch) -> String {
        if let language = match.languageCode, !language.isEmpty {
            return "\(match.label) · \(languageDisplayName(language))"
        }
        return match.label
    }

    public static func languageDisplayName(_ code: String) -> String {
        let normalized = code.replacingOccurrences(of: "_", with: "-")
        let locale = Locale.current
        if let name = locale.localizedString(forLanguageCode: normalized) {
            return name.capitalized
        }
        return normalized.uppercased()
    }

    public static func shortStatus(activeTrack: Track?) -> String {
        guard let activeTrack else { return "Off" }
        return displayName(for: activeTrack)
    }
}

public struct OpenSubtitlesResult: Codable, Sendable, Identifiable {
    public var id: String { fileID }
    public let fileID: String
    public let fileName: String
    public let language: String

    enum CodingKeys: String, CodingKey {
        case fileID = "file_id"
        case fileName = "file_name"
        case language
    }
}

public actor OpenSubtitlesClient {
    private let apiKey: String?
    private let session: URLSession

    public init(apiKey: String? = nil, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    public func search(query: String, language: String = "en") async throws -> [OpenSubtitlesResult] {
        var components = URLComponents(string: "https://rest.opensubtitles.org/search/")!
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "sublanguageid", value: language)
        ]
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.setValue("Kinema v1.0", forHTTPHeaderField: "User-Agent")
        if let apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "Api-Key")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return []
        }

        struct Wrapper: Codable {
            let data: [OpenSubtitlesResult]
        }
        if let wrapped = try? JSONDecoder().decode(Wrapper.self, from: data) {
            return wrapped.data
        }
        return try JSONDecoder().decode([OpenSubtitlesResult].self, from: data)
    }
}

public enum SubtitleStyling {
    public static func mpvOptions(
        fontSize: Int,
        fontName: String = "",
        colorHex: String = SubtitlePreferenceCatalog.defaultColorHex,
        encodingID: String = SubtitlePreferenceCatalog.defaultEncodingID,
        fontsDirectory: URL? = SubtitleFontRegistry.prepare()
    ) -> [String: String] {
        var options: [String: String] = [
            "sub-font-size": "\(fontSize)",
            "sub-border-size": "2",
            "sub-shadow-offset": "1",
            "sub-color": normalizedSubtitleColorHex(colorHex),
            "sub-border-color": "#000000",
            "sub-codepage": SubtitlePreferenceCatalog.encoding(id: encodingID).id
        ]
        if let fontsDirectory {
            options["sub-fonts-dir"] = fontsDirectory.path
        }
        if !fontName.isEmpty {
            options["sub-font"] = fontName
        }
        return options
    }
}
