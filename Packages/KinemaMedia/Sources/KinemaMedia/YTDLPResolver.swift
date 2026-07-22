#if os(macOS)
import Foundation
import KinemaCore

/// Resolves streaming URLs via yt-dlp on macOS (direct distribution).
public struct YTDLPResolver: MediaResolver {
    private let ytdlpPath: String

    public init(ytdlpPath: String? = nil) {
        if let ytdlpPath {
            self.ytdlpPath = ytdlpPath
        } else if let bundled = Bundle.main.url(forAuxiliaryExecutable: "yt-dlp") {
            self.ytdlpPath = bundled.path
        } else {
            self.ytdlpPath = "/opt/homebrew/bin/yt-dlp"
        }
    }

    public func canResolve(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let streamingHosts = [
            "youtube.com", "www.youtube.com", "youtu.be", "m.youtube.com",
            "vimeo.com", "twitch.tv", "www.twitch.tv",
            "twitter.com", "x.com", "soundcloud.com"
        ]
        return streamingHosts.contains(where: { host.contains($0) })
    }

    public func resolve(_ url: URL) async throws -> URL {
        guard FileManager.default.isExecutableFile(atPath: ytdlpPath) else {
            throw YTDLPError.binaryNotFound(ytdlpPath)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ytdlpPath)
        process.arguments = ["-g", "--no-playlist", url.absoluteString]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw YTDLPError.extractionFailed
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines).first,
              let streamURL = URL(string: output) else {
            throw YTDLPError.invalidOutput
        }
        return streamURL
    }
}

public enum YTDLPError: Error, LocalizedError {
    case binaryNotFound(String)
    case extractionFailed
    case invalidOutput

    public var errorDescription: String? {
        switch self {
        case .binaryNotFound(let path): return "yt-dlp not found at \(path). Install via: brew install yt-dlp"
        case .extractionFailed: return "yt-dlp failed to extract stream URL"
        case .invalidOutput: return "yt-dlp returned invalid output"
        }
    }
}
#endif
