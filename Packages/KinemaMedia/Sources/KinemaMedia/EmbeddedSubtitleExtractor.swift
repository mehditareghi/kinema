import Foundation
import FFmpegKit

/// Extracts a text subtitle stream from a container into a temp `.srt` / `.ass` file.
public enum EmbeddedSubtitleExtractor {
    public enum ExtractError: Error {
        case openFailed
        case streamNotFound
        case unsupportedCodec
        case writeFailed
    }

    /// - Parameter streamIndex: ffmpeg/libav stream index (`ff-index` from mpv).
    public static func extract(
        from mediaURL: URL,
        streamIndex: Int,
        preferredName: String = "embedded"
    ) throws -> URL {
        let format: AVFormatContext
        do {
            format = try AVFormatContext(url: mediaURL.path)
            try format.findStreamInfo()
        } catch {
            throw ExtractError.openFailed
        }

        guard streamIndex >= 0, streamIndex < format.streamCount else {
            throw ExtractError.streamNotFound
        }

        let stream = format.streams[streamIndex]
        let params = stream.codecParameters
        guard params.mediaType == .subtitle else {
            throw ExtractError.streamNotFound
        }

        let codecID = params.codecId
        let codecName = "\(codecID)".lowercased()
        let isASS = codecName == "ass" || codecName == "ssa"
        let isText = isASS
            || codecName == "srt"
            || codecName == "subrip"
            || codecName == "webvtt"
            || codecName == "mov_text"
            || codecName == "text"
        guard isText else { throw ExtractError.unsupportedCodec }

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("KinemaExtractedSubs", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let ext = isASS ? "ass" : "srt"
        let safeName = preferredName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let outURL = folder.appendingPathComponent("\(safeName)-\(streamIndex)-\(UUID().uuidString).\(ext)")

        var lines: [String] = []
        var index = 1
        let timebase = stream.timebase

        if isASS {
            if let extra = params.extradata, params.extradataSize > 0 {
                let header = String(
                    bytes: UnsafeBufferPointer(start: extra, count: params.extradataSize),
                    encoding: .utf8
                ) ?? ""
                if !header.isEmpty {
                    lines.append(header.trimmingCharacters(in: .newlines))
                    if !header.contains("[Events]") {
                        lines.append("")
                        lines.append("[Events]")
                        lines.append("Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text")
                    }
                } else {
                    lines.append(assPreamble())
                }
            } else {
                lines.append(assPreamble())
            }
        }

        let packet = AVPacket()
        while true {
            do {
                try format.readFrame(into: packet)
            } catch let error as AVError where error == .eof {
                break
            } catch {
                break
            }
            defer { packet.unref() }

            guard packet.streamIndex == streamIndex else { continue }
            guard packet.size > 0, let data = packet.data else { continue }

            let payload = String(
                bytes: UnsafeBufferPointer(start: data, count: packet.size),
                encoding: .utf8
            ) ?? ""
            let text = payload.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            let pts = packet.pts != AVTimestamp.noPTS ? packet.pts : packet.dts
            let start = ptsToSeconds(pts, timeBase: timebase)
            let end = packet.duration > 0
                ? ptsToSeconds(pts + packet.duration, timeBase: timebase)
                : start + 2.5

            if isASS {
                if text.hasPrefix("Dialogue:") {
                    lines.append(text)
                } else {
                    lines.append(
                        "Dialogue: 0,\(formatASS(start)),\(formatASS(end)),Default,,0,0,0,,\(text.replacingOccurrences(of: "\n", with: "\\N"))"
                    )
                }
            } else {
                lines.append("\(index)")
                lines.append("\(formatSRT(start)) --> \(formatSRT(end))")
                lines.append(text)
                lines.append("")
                index += 1
            }
        }

        guard !lines.isEmpty else { throw ExtractError.writeFailed }
        let body = lines.joined(separator: "\n")
        guard let data = body.data(using: .utf8) else { throw ExtractError.writeFailed }
        try data.write(to: outURL)
        return outURL
    }

    private static func assPreamble() -> String {
        """
        [Script Info]
        ScriptType: v4.00+
        PlayResX: 1920
        PlayResY: 1080

        [V4+ Styles]
        Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
        Style: Default,Arial,48,&H00FFFFFF,&H000000FF,&H00000000,&H80000000,-1,0,0,0,100,100,0,0,1,2,1,2,20,20,40,1

        [Events]
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
        """
    }

    private static func ptsToSeconds(_ pts: Int64, timeBase: AVRational) -> Double {
        guard pts != AVTimestamp.noPTS else { return 0 }
        return Double(pts) * timeBase.toDouble
    }

    private static func formatSRT(_ seconds: Double) -> String {
        let total = max(0, seconds)
        let h = Int(total) / 3600
        let m = (Int(total) % 3600) / 60
        let s = Int(total) % 60
        let ms = Int((total - floor(total)) * 1000)
        return String(format: "%02d:%02d:%02d,%03d", h, m, s, ms)
    }

    private static func formatASS(_ seconds: Double) -> String {
        let total = max(0, seconds)
        let h = Int(total) / 3600
        let m = (Int(total) % 3600) / 60
        let s = Int(total) % 60
        let cs = Int((total - floor(total)) * 100)
        return String(format: "%d:%02d:%02d.%02d", h, m, s, cs)
    }
}
