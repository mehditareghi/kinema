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
    /// Sidecar extensions Kinema treats as first-class subtitle files.
    public static let extensions = [
        "srt", "ass", "ssa", "vtt", "sub", "idx",
        "smi", "sami", "mpl", "txt", "pjs", "aqt", "jss", "rt", "sup"
    ]

    public static func isSubtitleURL(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }

    public static func findLocalSubtitles(for mediaURL: URL) -> [SubtitleMatch] {
        let directory = mediaURL.deletingLastPathComponent()
        let baseName = mediaURL.deletingPathExtension().lastPathComponent
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return [] }

        return files.compactMap { fileURL in
            let ext = fileURL.pathExtension.lowercased()
            guard extensions.contains(ext) else { return nil }
            // Prefer .idx for VobSub pairs; skip lone .sub when matching .idx exists.
            if ext == "sub" {
                let idx = fileURL.deletingPathExtension().appendingPathExtension("idx")
                if files.contains(idx) { return nil }
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

    public static func preferredMatch(
        from matches: [SubtitleMatch],
        preferredLanguage: String
    ) -> SubtitleMatch? {
        guard !matches.isEmpty else { return nil }
        let preferred = preferredLanguage.lowercased()
        if !preferred.isEmpty,
           let match = matches.first(where: {
               ($0.languageCode ?? "").lowercased().hasPrefix(preferred)
           }) {
            return match
        }
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
        if let codecBadge = track.codecBadge { badges.append(codecBadge) }
        if track.isDefault { badges.append("Default") }
        if track.isForced { badges.append("Forced") }
        if track.isLikelySDH { badges.append("SDH/CC") }
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
    public let downloadURL: String?

    enum CodingKeys: String, CodingKey {
        case fileID = "file_id"
        case fileName = "file_name"
        case language
        case downloadURL = "url"
        case attributes
        case files
        case id
    }

    public init(fileID: String, fileName: String, language: String, downloadURL: String? = nil) {
        self.fileID = fileID
        self.fileName = fileName
        self.language = language
        self.downloadURL = downloadURL
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let fileID = try container.decodeIfPresent(String.self, forKey: .fileID) {
            self.fileID = fileID
            self.fileName = try container.decodeIfPresent(String.self, forKey: .fileName) ?? "subtitle.srt"
            self.language = try container.decodeIfPresent(String.self, forKey: .language) ?? "en"
            self.downloadURL = try container.decodeIfPresent(String.self, forKey: .downloadURL)
            return
        }

        // OpenSubtitles.com API v1 nested attributes shape (best-effort).
        if let id = try container.decodeIfPresent(Int.self, forKey: .id) {
            self.fileID = "\(id)"
        } else {
            self.fileID = UUID().uuidString
        }
        self.fileName = try container.decodeIfPresent(String.self, forKey: .fileName) ?? "subtitle.srt"
        self.language = try container.decodeIfPresent(String.self, forKey: .language) ?? "en"
        self.downloadURL = try container.decodeIfPresent(String.self, forKey: .downloadURL)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fileID, forKey: .fileID)
        try container.encode(fileName, forKey: .fileName)
        try container.encode(language, forKey: .language)
        try container.encodeIfPresent(downloadURL, forKey: .downloadURL)
    }
}

public enum OpenSubtitlesError: Error, LocalizedError {
    case missingAPIKey
    case invalidResponse
    case downloadFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add an OpenSubtitles API key in Preferences to download subtitles."
        case .invalidResponse:
            return "OpenSubtitles returned an unexpected response."
        case .downloadFailed(let message):
            return message
        }
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
        if let apiKey, !apiKey.isEmpty {
            if let modern = try? await searchModern(query: query, language: language, apiKey: apiKey), !modern.isEmpty {
                return modern
            }
        }
        return try await searchLegacy(query: query, language: language)
    }

    public func download(_ result: OpenSubtitlesResult) async throws -> URL {
        if let direct = result.downloadURL, let url = URL(string: direct) {
            return try await downloadFile(from: url, suggestedName: result.fileName)
        }

        guard let apiKey, !apiKey.isEmpty else {
            throw OpenSubtitlesError.missingAPIKey
        }

        var request = URLRequest(url: URL(string: "https://api.opensubtitles.com/api/v1/download")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Kinema v1.0", forHTTPHeaderField: "User-Agent")
        request.setValue(apiKey, forHTTPHeaderField: "Api-Key")
        let body: [String: Any] = ["file_id": Int(result.fileID) ?? result.fileID]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw OpenSubtitlesError.downloadFailed("Download request failed.")
        }

        struct DownloadResponse: Decodable {
            let link: String?
            let file_name: String?
        }
        let decoded = try JSONDecoder().decode(DownloadResponse.self, from: data)
        guard let link = decoded.link, let downloadURL = URL(string: link) else {
            throw OpenSubtitlesError.invalidResponse
        }
        return try await downloadFile(from: downloadURL, suggestedName: decoded.file_name ?? result.fileName)
    }

    private func searchLegacy(query: String, language: String) async throws -> [OpenSubtitlesResult] {
        var components = URLComponents(string: "https://rest.opensubtitles.org/search/")!
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "sublanguageid", value: language)
        ]
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.setValue("Kinema v1.0", forHTTPHeaderField: "User-Agent")
        if let apiKey, !apiKey.isEmpty {
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
        return (try? JSONDecoder().decode([OpenSubtitlesResult].self, from: data)) ?? []
    }

    private func searchModern(query: String, language: String, apiKey: String) async throws -> [OpenSubtitlesResult] {
        var components = URLComponents(string: "https://api.opensubtitles.com/api/v1/subtitles")!
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "languages", value: language)
        ]
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Kinema v1.0", forHTTPHeaderField: "User-Agent")
        request.setValue(apiKey, forHTTPHeaderField: "Api-Key")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return []
        }

        struct ModernFile: Decodable {
            let file_id: Int?
            let file_name: String?
        }
        struct ModernAttributes: Decodable {
            let language: String?
            let files: [ModernFile]?
            let feature_details: FeatureDetails?
            struct FeatureDetails: Decodable {
                let title: String?
            }
        }
        struct ModernItem: Decodable {
            let id: String?
            let attributes: ModernAttributes?
        }
        struct ModernWrapper: Decodable {
            let data: [ModernItem]?
        }

        let wrapper = try JSONDecoder().decode(ModernWrapper.self, from: data)
        return (wrapper.data ?? []).compactMap { item in
            guard let file = item.attributes?.files?.first, let fileID = file.file_id else { return nil }
            let name = file.file_name
                ?? item.attributes?.feature_details?.title
                ?? "subtitle-\(fileID).srt"
            return OpenSubtitlesResult(
                fileID: "\(fileID)",
                fileName: name,
                language: item.attributes?.language ?? language
            )
        }
    }

    private func downloadFile(from url: URL, suggestedName: String) async throws -> URL {
        let (tempURL, response) = try await session.download(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw OpenSubtitlesError.downloadFailed("Could not download subtitle file.")
        }
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = caches.appendingPathComponent("KinemaSubtitles", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let safeName = suggestedName.isEmpty ? "download.srt" : suggestedName
        let destination = folder.appendingPathComponent(safeName)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)
        return destination
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
            "sub-border-color": "#FF000000",
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
