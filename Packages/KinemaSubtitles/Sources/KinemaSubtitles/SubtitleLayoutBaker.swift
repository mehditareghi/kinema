import Foundation
import KinemaCore

/// Builds a dual-track ASS whose **only** job is independent Alignment (L/R/corners).
/// Look (font, color, outline, …) stays on libmpv via `sub-ass-force-style` + `sub-ass-override=scale`.
public enum SubtitleLayoutBaker {
    public struct Cue: Sendable {
        public var start: Double
        public var end: Double
        public var text: String
    }

    public static func parseCues(from url: URL) -> [Cue] {
        guard let data = try? Data(contentsOf: url),
              let raw = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
            return []
        }
        let ext = url.pathExtension.lowercased()
        if ext == "ass" || ext == "ssa" {
            return parseASS(raw)
        }
        if ext == "vtt" {
            return parseVTT(raw)
        }
        return parseSRT(raw)
    }

    /// Dual-track ASS: two styles that differ only by Alignment (+ delays in timestamps).
    public static func bakeDual(
        primarySource: URL,
        primaryAnchor: SubtitlePlacementAnchor,
        primaryDelay: Double,
        secondarySource: URL,
        secondaryAnchor: SubtitlePlacementAnchor,
        secondaryDelay: Double
    ) -> URL? {
        let primaryCues = parseCues(from: primarySource)
        let secondaryCues = parseCues(from: secondarySource)
        guard !primaryCues.isEmpty || !secondaryCues.isEmpty else { return nil }
        return writeASS(
            tracks: [
                (style: "Primary", alignment: primaryAnchor.assAlignment, delay: primaryDelay, cues: primaryCues),
                (style: "Secondary", alignment: secondaryAnchor.assAlignment, delay: secondaryDelay, cues: secondaryCues)
            ],
            title: "Kinema Dual Layout"
        )
    }

    private static func writeASS(
        tracks: [(style: String, alignment: Int, delay: Double, cues: [Cue])],
        title: String
    ) -> URL? {
        var styles: [String] = []
        var events: [String] = []

        // Neutral placeholders — mpv force-style owns the real look.
        for track in tracks {
            styles.append(
                "Style: \(track.style),Arial,55,&H00FFFFFF,&H000000FF,&H00000000,&H80000000,"
                    + "-1,0,0,0,100,100,0,0,1,2,1,\(track.alignment),40,40,40,1"
            )
            for cue in track.cues {
                let start = max(0, cue.start + track.delay)
                let end = max(start + 0.05, cue.end + track.delay)
                let text = stripOverrideTags(cue.text)
                    .replacingOccurrences(of: "\r\n", with: "\\N")
                    .replacingOccurrences(of: "\n", with: "\\N")
                    .replacingOccurrences(of: ",", with: "，")
                events.append(
                    "Dialogue: 0,\(formatASS(start)),\(formatASS(end)),\(track.style),,0,0,0,,\(text)"
                )
            }
        }

        let body = """
        [Script Info]
        Title: \(title)
        ScriptType: v4.00+
        WrapStyle: 0
        ScaledBorderAndShadow: yes
        YCbCr Matrix: None
        PlayResX: 1920
        PlayResY: 1080

        [V4+ Styles]
        Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
        \(styles.joined(separator: "\n"))

        [Events]
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
        \(events.joined(separator: "\n"))
        """

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("KinemaLayout", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("layout-\(UUID().uuidString).ass")
        do {
            try body.data(using: .utf8)?.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    /// mpv hex `#AARRGGBB` → ASS `&HAABBGGRR`.
    public static func assColor(from hex: String) -> String {
        var value = normalizedSubtitleColorHex(hex)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 8 else { return "&H00FFFFFF" }
        let aa = String(value.prefix(2))
        let rr = String(value.dropFirst(2).prefix(2))
        let gg = String(value.dropFirst(4).prefix(2))
        let bb = String(value.dropFirst(6).prefix(2))
        return "&H\(aa)\(bb)\(gg)\(rr)"
    }

    private static func stripOverrideTags(_ text: String) -> String {
        guard text.contains("{") else { return text }
        var result = ""
        var inTag = false
        for ch in text {
            if ch == "{" {
                inTag = true
                continue
            }
            if ch == "}" {
                inTag = false
                continue
            }
            if !inTag {
                result.append(ch)
            }
        }
        return result
    }

    private static func formatASS(_ seconds: Double) -> String {
        let total = max(0, seconds)
        let h = Int(total) / 3600
        let m = (Int(total) % 3600) / 60
        let s = Int(total) % 60
        let cs = Int((total - floor(total)) * 100)
        return String(format: "%d:%02d:%02d.%02d", h, m, s, cs)
    }

    private static func parseSRT(_ raw: String) -> [Cue] {
        let blocks = raw.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
        var cues: [Cue] = []
        for block in blocks {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard let timeLine = lines.first(where: { $0.contains("-->") }) else { continue }
            let parts = timeLine.components(separatedBy: "-->")
            guard parts.count == 2,
                  let start = parseTimestamp(parts[0]),
                  let end = parseTimestamp(parts[1]) else { continue }
            let textLines = lines.drop(while: { !$0.contains("-->") }).dropFirst()
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            guard !textLines.isEmpty else { continue }
            cues.append(Cue(start: start, end: end, text: textLines.joined(separator: "\n")))
        }
        return cues
    }

    private static func parseVTT(_ raw: String) -> [Cue] {
        var normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
        if let range = normalized.range(of: "WEBVTT") {
            normalized.removeSubrange(range)
        }
        let pattern = #"(\d{2}:\d{2}:\d{2})\.(\d{3})"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(normalized.startIndex..., in: normalized)
            normalized = regex.stringByReplacingMatches(
                in: normalized,
                range: range,
                withTemplate: "$1,$2"
            )
        }
        return parseSRT(normalized)
    }

    private static func parseASS(_ raw: String) -> [Cue] {
        var cues: [Cue] = []
        for line in raw.components(separatedBy: .newlines) {
            guard line.hasPrefix("Dialogue:") else { continue }
            let payload = String(line.dropFirst("Dialogue:".count))
            let fields = splitASSFields(payload)
            guard fields.count >= 10,
                  let start = parseASSTime(fields[1]),
                  let end = parseASSTime(fields[2]) else { continue }
            let text = fields[9...]
                .joined(separator: ",")
                .replacingOccurrences(of: "\\N", with: "\n")
                .replacingOccurrences(of: "\\n", with: "\n")
            cues.append(Cue(start: start, end: end, text: text))
        }
        return cues
    }

    private static func splitASSFields(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var commas = 0
        for ch in line {
            if ch == "," && commas < 9 {
                fields.append(current)
                current = ""
                commas += 1
            } else {
                current.append(ch)
            }
        }
        fields.append(current)
        return fields.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func parseTimestamp(_ raw: String) -> Double? {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        let parts = cleaned.split(separator: ":")
        guard parts.count == 3,
              let h = Double(parts[0]),
              let m = Double(parts[1]),
              let s = Double(parts[2]) else { return nil }
        return h * 3600 + m * 60 + s
    }

    private static func parseASSTime(_ raw: String) -> Double? {
        let parts = raw.split(separator: ":")
        guard parts.count == 3,
              let h = Double(parts[0]),
              let m = Double(parts[1]) else { return nil }
        let secParts = parts[2].split(separator: ".")
        guard let s = Double(secParts[0]) else { return nil }
        let cs = secParts.count > 1 ? (Double(secParts[1]) ?? 0) / 100 : 0
        return h * 3600 + m * 60 + s + cs
    }
}
