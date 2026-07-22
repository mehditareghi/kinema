import CoreGraphics
import Foundation
import ImageIO
import LibMPV

/// VLC-style thumbnail extraction: dedicated mpv instance, seek to a meaningful
/// position, skip the first few frames (often black/keyframe junk), capture later.
public enum MPVThumbnailExtractor {
    private static let snapshotPosition: Double = 0.3
    private static let minimumFramesBeforeCapture = 4
    private static let timeout: TimeInterval = 14

    public static func extractImage(from url: URL, at time: TimeInterval) async -> CGImage? {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return await Task.detached(priority: .utility) {
            var coordinationError: NSError?
            var image: CGImage?

            let coordinator = NSFileCoordinator()
            coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { readURL in
                image = extractImageSync(from: readURL, at: time)
            }

            if image == nil {
                image = extractImageSync(from: url, at: time)
            }

            return image
        }.value
    }

    public static func extractImageSync(from url: URL, at time: TimeInterval) -> CGImage? {
        extractImageSync(from: url, at: time, durationHint: nil)
    }

    public static func extractImageSync(
        from url: URL,
        at time: TimeInterval,
        durationHint: TimeInterval?
    ) -> CGImage? {
        guard let mpv = mpv_create() else { return nil }
        defer { mpv_terminate_destroy(mpv) }

        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kinema-mpv-thumb-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDirectory) }

        var options: [(String, String)] = [
            ("vo", "image"),
            ("ao", "null"),
            ("vid", "yes"),
            ("audio", "no"),
            ("pause", "yes"),
            ("keep-open", "no"),
            ("idle", "no"),
            ("osc", "no"),
            ("osd-level", "0"),
            ("input-default-bindings", "no"),
            ("input-vo-keyboard", "no"),
            ("vo-image-format", "jpg"),
            ("vo-image-outdir", outputDirectory.path),
            ("vo-image-jpeg-quality", "86"),
            ("demuxer-lavf-analyzeduration", "1"),
            ("hr-seek", "yes"),
            ("frames", "8"),
        ]
        #if os(iOS) || os(tvOS)
        options.append(("hwdec", "no"))
        #else
        options.append(("hwdec", "no"))
        #endif

        for (name, value) in options {
            _ = mpv_set_option_string(mpv, name, value)
        }

        guard mpv_initialize(mpv) >= 0 else { return nil }

        guard runCommand(mpv, ["loadfile", url.path, "replace"]) >= 0 else { return nil }

        var didSeek = false
        var targetSeconds = max(0, time)
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if let image = representativeJPEG(in: outputDirectory) {
                return loadCGImage(from: image)
            }

            guard let event = mpv_wait_event(mpv, 0.25) else { continue }
            if event.pointee.event_id == MPV_EVENT_NONE { continue }

            switch event.pointee.event_id {
            case MPV_EVENT_FILE_LOADED:
                if !didSeek {
                    var duration = durationHint ?? 0
                    if duration <= 0 {
                        var nativeDuration = Double(0)
                        if mpv_get_property(mpv, "duration", MPV_FORMAT_DOUBLE, &nativeDuration) >= 0 {
                            duration = nativeDuration
                        }
                    }

                    if targetSeconds <= 0, duration > 0 {
                        targetSeconds = max(1, duration * snapshotPosition)
                    } else if targetSeconds <= 0 {
                        targetSeconds = 10
                    }

                    if duration > 0 {
                        targetSeconds = min(targetSeconds, max(0, duration - 0.5))
                    }

                    _ = runCommand(mpv, ["seek", String(format: "%.3f", targetSeconds), "absolute"])
                    didSeek = true
                    unpause(mpv)
                }

            case MPV_EVENT_PLAYBACK_RESTART:
                if didSeek, let image = representativeJPEG(in: outputDirectory) {
                    return loadCGImage(from: image)
                }

            case MPV_EVENT_END_FILE, MPV_EVENT_SHUTDOWN:
                if let image = representativeJPEG(in: outputDirectory) {
                    return loadCGImage(from: image)
                }
                return nil

            default:
                break
            }
        }

        guard let imageURL = representativeJPEG(in: outputDirectory) else { return nil }
        return loadCGImage(from: imageURL)
    }

    private static func unpause(_ mpv: OpaquePointer) {
        var paused: Int32 = 0
        _ = mpv_set_property(mpv, "pause", MPV_FORMAT_FLAG, &paused)
    }

    private static func runCommand(_ mpv: OpaquePointer, _ args: [String]) -> Int32 {
        var cargs: [UnsafePointer<CChar>?] = args.map { arg in
            strdup(arg).map { UnsafePointer($0) }
        }
        cargs.append(nil)
        defer {
            for ptr in cargs where ptr != nil {
                free(UnsafeMutableRawPointer(mutating: ptr!))
            }
        }
        return mpv_command(mpv, &cargs)
    }

    /// VLC ignores the first few frames; prefer a later written JPEG.
    private static func representativeJPEG(in directory: URL) -> URL? {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return nil }

        let frames = urls
            .filter { ["jpg", "jpeg"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard !frames.isEmpty else { return nil }
        if frames.count >= minimumFramesBeforeCapture {
            return frames[minimumFramesBeforeCapture - 1]
        }
        return frames.last
    }

    private static func loadCGImage(from url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
