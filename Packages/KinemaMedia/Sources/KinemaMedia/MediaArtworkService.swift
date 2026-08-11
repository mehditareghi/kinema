import CoreGraphics
import FFmpegKit
import Foundation
import KinemaCore
import KinemaMPV

public struct MediaPreview: Sendable {
    public let duration: TimeInterval?
    public let width: Int?
    public let height: Int?
    public let image: CGImage?

    public var qualityLabel: String? {
        guard let width, let height else { return nil }
        return MediaQualityLabel.make(width: width, height: height)
    }

    public init(duration: TimeInterval?, width: Int?, height: Int?, image: CGImage?) {
        self.duration = duration
        self.width = width
        self.height = height
        self.image = image
    }
}

public enum MediaArtworkService {
    /// VLC default snapshot position (~30%).
    private static let snapshotPosition: Double = 0.3
    /// VLC uses ~150s start-time for longer files before falling back to position seeks.
    private static let longFileSnapshotSeconds: TimeInterval = 150
    /// Analyze a short batch after the seek and keep the best scene frame (FFmpeg thumbnail idea).
    private static let analysisBatchSize = 12
    /// After a keyframe seek, wait for an I-frame before scoring candidates.
    private static let maxFramesWaitingForKeyframe = 48
    /// Only stop probing alternate seeks once we have a clearly good scene frame.
    private static let strongSceneScore: Double = 0.32
    /// Early exit inside a batch when we already have a strong frame.
    private static let earlyBatchScore: Double = 0.38

    public static func loadPreview(
        for url: URL,
        at time: TimeInterval,
        priority: ThumbnailPipeline.Priority = .visible
    ) async -> MediaPreview {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return await ThumbnailPipeline.shared.loadPreview(for: url, at: time, priority: priority)
    }

    /// Single-frame extract for scrubber previews — reuses a warm demuxer/decoder.
    public static func extractScrubFrame(from url: URL, at time: TimeInterval) async -> CGImage? {
        await ScrubFrameExtractor.shared.frame(at: time, url: url)
    }

    /// Lightweight RGBA convert used by the scrub extractor (smaller than library thumbs).
    static func makeScrubCGImage(from frame: AVFrame) -> CGImage? {
        makeCGImage(from: frame, maxWidth: 240, flags: .fastBilinear)
    }

    static func extractPreview(from url: URL, at time: TimeInterval) -> MediaPreview {
        // Skip stubs / in-progress USB copies — probing them is expensive and can
        // conflict with Finder’s AFC writer (device disconnects mid-transfer).
        guard LibraryMediaPaths.isStableMediaFile(url) else {
            return MediaPreview(duration: nil, width: nil, height: nil, image: nil)
        }

        // Files inside our shared Documents library: read directly.
        // NSFileCoordinator against an active Finder copy is a known disconnect trigger.
        if LibraryMediaPaths.isInsideBuiltInLibrary(url) {
            return extractPreviewCoordinated(from: url, at: time)
        }

        var coordinationError: NSError?
        var preview = MediaPreview(duration: nil, width: nil, height: nil, image: nil)

        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { readURL in
            preview = extractPreviewCoordinated(from: readURL, at: time)
        }

        if preview.image == nil {
            preview = extractPreviewCoordinated(from: url, at: time)
        }

        return preview
    }

    private static func extractPreviewCoordinated(from url: URL, at time: TimeInterval) -> MediaPreview {
        let metadata = probeMetadata(from: url)

        // Prefer FFmpeg — much lighter than spinning up mpv per tile.
        if let ffmpeg = extractFFmpegPreview(from: url, at: time, metadata: metadata),
           let image = ffmpeg.image,
           FrameValidator.isAcceptable(image) {
            return MediaPreview(
                duration: ffmpeg.duration ?? metadata.duration,
                width: ffmpeg.width ?? metadata.width,
                height: ffmpeg.height ?? metadata.height,
                image: image
            )
        }

        if let image = MPVThumbnailExtractor.extractImageSync(
            from: url,
            at: resolvedSeekTime(requested: time, duration: metadata.duration),
            durationHint: metadata.duration
        ), FrameValidator.isAcceptable(image) {
            return MediaPreview(
                duration: metadata.duration,
                width: metadata.width,
                height: metadata.height,
                image: image
            )
        }

        // Last FFmpeg pass may return a weak/nil image — only keep if it still passes.
        if let ffmpeg = extractFFmpegPreview(from: url, at: time, metadata: metadata),
           let image = ffmpeg.image,
           FrameValidator.isAcceptable(image) {
            return MediaPreview(
                duration: ffmpeg.duration ?? metadata.duration,
                width: ffmpeg.width ?? metadata.width,
                height: ffmpeg.height ?? metadata.height,
                image: image
            )
        }

        return MediaPreview(
            duration: metadata.duration,
            width: metadata.width,
            height: metadata.height,
            image: nil
        )
    }

    private static func resolvedSeekTime(requested: TimeInterval, duration: TimeInterval?) -> TimeInterval {
        if requested > 0 {
            return clampedSeekTime(requested, duration: duration)
        }
        if let duration, duration > 0 {
            // Short clips (e.g. 1s HDR samples): never seek to EOF — that can hang extractors.
            let fraction = duration < 3 ? 0.35 : snapshotPosition
            return clampedSeekTime(duration * fraction, duration: duration)
        }
        return 10
    }

    private static func clampedSeekTime(_ time: TimeInterval, duration: TimeInterval?) -> TimeInterval {
        guard let duration, duration > 0 else { return max(0, time) }
        let upper = max(0, duration - 0.05)
        return min(max(0, time), upper)
    }

    private struct FFmpegPreview {
        let duration: TimeInterval?
        let width: Int?
        let height: Int?
        let image: CGImage?
    }

    private static func probeMetadata(from url: URL) -> (duration: TimeInterval?, width: Int?, height: Int?) {
        do {
            let format = try AVFormatContext(url: url.path)
            try format.findStreamInfo()

            let duration = probeDuration(format: format)
            if let streamIndex = format.streamIndex(for: .video) {
                let params = format.streams[streamIndex].codecParameters
                return (duration, params.width, params.height)
            }
            return (duration, nil, nil)
        } catch {
            return (nil, nil, nil)
        }
    }

    private static func extractFFmpegPreview(
        from url: URL,
        at time: TimeInterval,
        metadata: (duration: TimeInterval?, width: Int?, height: Int?)
    ) -> FFmpegPreview? {
        do {
            let format = try AVFormatContext(url: url.path)
            try format.findStreamInfo()

            let duration = probeDuration(format: format) ?? metadata.duration
            guard let streamIndex = format.findBestStream(type: .video) else {
                return FFmpegPreview(duration: duration, width: metadata.width, height: metadata.height, image: nil)
            }

            let stream = format.streams[streamIndex]
            let width = stream.codecParameters.width
            let height = stream.codecParameters.height

            guard let codec = AVCodec.findDecoderById(stream.codecParameters.codecId) else {
                return FFmpegPreview(duration: duration, width: width, height: height, image: nil)
            }

            let codecContext = AVCodecContext(codec: codec)
            codecContext.setParameters(stream.codecParameters)
            try codecContext.openCodec(codec)

            let frame = AVFrame()
            let seekTimes = seekCandidates(
                requested: time,
                duration: duration,
                stream: stream
            )

            var bestImage: CGImage?
            var bestScore = -Double.greatestFiniteMagnitude

            for seekTime in seekTimes {
                let didSeek = seekTime > 0.25 && seek(
                    to: seekTime,
                    format: format,
                    streamIndex: streamIndex,
                    stream: stream
                )
                // Flush after seek so leftover P/B references can't paint gray macroblocks.
                codecContext.flush()

                guard let image = decodeRepresentativeFrame(
                    format: format,
                    codecContext: codecContext,
                    streamIndex: streamIndex,
                    frame: frame,
                    fromBeginning: !didSeek
                ), let score = FrameValidator.qualityScore(for: image) else {
                    continue
                }

                if score > bestScore {
                    bestScore = score
                    bestImage = image
                }

                // Strong scene frame — no need to probe alternate seeks.
                if score >= strongSceneScore {
                    break
                }
            }

            // Never keep a weak/gray-ish "best of a bad batch".
            if bestScore < MediaFrameValidator.minimumAcceptableScore {
                bestImage = nil
            }

            return FFmpegPreview(
                duration: duration,
                width: width,
                height: height,
                image: bestImage
            )
        } catch {
            return nil
        }
    }

    private static func probeDuration(format: AVFormatContext) -> TimeInterval? {
        if format.duration > 0, format.duration != AVTimestamp.noPTS {
            return Double(format.duration) / Double(AVTimestamp.timebase)
        }

        if let streamIndex = format.streamIndex(for: .video) {
            let stream = format.streams[streamIndex]
            if stream.duration > 0, stream.duration != AVTimestamp.noPTS {
                return Double(stream.duration) * stream.timebase.toDouble
            }
        }

        return nil
    }

    private static func seekCandidates(
        requested: TimeInterval,
        duration: TimeInterval?,
        stream _: AVStream
    ) -> [TimeInterval] {
        let resolved = resolvedSeekTime(requested: requested, duration: duration)
        var candidates = [resolved, 10, 30, 1]
        if let duration, duration > 0 {
            candidates.append(duration * snapshotPosition)
            // VLC-style: for long media prefer ~150s over a random early keyframe.
            if duration > longFileSnapshotSeconds * 1.5 {
                candidates.insert(longFileSnapshotSeconds, at: min(1, candidates.count))
            }
            if duration > 3 {
                candidates.append(max(1, duration - 2))
            }
            // Spread more mid-film alternatives when the primary seek is flat/gray.
            if duration > 90 {
                candidates.append(contentsOf: [
                    duration * 0.12,
                    duration * 0.22,
                    duration * 0.38,
                    duration * 0.55
                ])
            }
            candidates = candidates.map { clampedSeekTime($0, duration: duration) }
        }

        var seen = Set<Int>()
        return candidates.filter { value in
            seen.insert(Int(value * 1000)).inserted
        }
    }

    private static func seek(
        to seconds: TimeInterval,
        format: AVFormatContext,
        streamIndex: Int,
        stream: AVStream
    ) -> Bool {
        let avTime = Int64(max(0, seconds) * Double(AVTimestamp.timebase))
        let timestamp = AVMath.rescale(
            avTime,
            AVTimestamp.timebaseQ,
            stream.timebase,
            rounding: .down
        )
        // Keyframe-only seek. `.any` lands on P/B frames and produces gray macroblock junk.
        do {
            try format.seekFrame(
                to: timestamp,
                streamIndex: streamIndex,
                flags: [.backward]
            )
            return true
        } catch {
            // Some containers reject strict keyframe seeks — fall back, but decoder
            // still waits for an I-frame before accepting a candidate.
            do {
                try format.seekFrame(
                    to: timestamp,
                    streamIndex: streamIndex,
                    flags: [.backward, .any]
                )
                return true
            } catch {
                return false
            }
        }
    }

    private static func decodeRepresentativeFrame(
        format: AVFormatContext,
        codecContext: AVCodecContext,
        streamIndex: Int,
        frame: AVFrame,
        fromBeginning: Bool,
        maxPackets: Int = 1800
    ) -> CGImage? {
        if fromBeginning {
            do {
                try format.seekFrame(to: 0, streamIndex: streamIndex, flags: [.backward])
            } catch {
                // Continue from current read position.
            }
            codecContext.flush()
        }

        let packet = AVPacket()
        var packetsRead = 0
        var decodedFrames = 0
        var seenKeyframe = false
        var bestImage: CGImage?
        var bestScore = -Double.greatestFiniteMagnitude
        var acceptedInBatch = 0

        packetLoop: while packetsRead < maxPackets {
            do {
                try format.readFrame(into: packet)
            } catch {
                break
            }

            defer { packet.unref() }

            guard packet.streamIndex == streamIndex else { continue }
            packetsRead += 1

            do {
                try codecContext.sendPacket(packet)
            } catch {
                continue
            }

            while true {
                do {
                    try codecContext.receiveFrame(frame)
                } catch let error as AVError where error == .tryAgain {
                    break
                } catch {
                    break
                }

                guard frame.width > 0, frame.height > 0 else { continue }

                decodedFrames += 1

                // Incomplete-decode gray blocks happen when we score P/B frames before
                // the decoder has a reference I-frame. Wait for one.
                if !seenKeyframe {
                    if frame.isKeyFrame || frame.pictureType == .I {
                        seenKeyframe = true
                    } else if decodedFrames < maxFramesWaitingForKeyframe {
                        continue
                    } else {
                        // Never got an explicit keyframe flag — proceed cautiously.
                        seenKeyframe = true
                    }
                }

                guard let image = makeCGImage(from: frame),
                      let score = FrameValidator.qualityScore(for: image) else {
                    continue
                }

                acceptedInBatch += 1
                if score > bestScore {
                    bestScore = score
                    bestImage = image
                }

                // Prefer the keyframe itself when it's already a strong scene.
                if (frame.isKeyFrame || frame.pictureType == .I), bestScore >= earlyBatchScore {
                    return bestImage
                }

                if acceptedInBatch >= 3, bestScore >= earlyBatchScore {
                    return bestImage
                }

                if acceptedInBatch >= analysisBatchSize {
                    break packetLoop
                }
            }
        }

        guard let bestImage, bestScore >= MediaFrameValidator.minimumAcceptableScore else {
            return nil
        }
        return bestImage
    }

    private static func makeCGImage(
        from frame: AVFrame,
        maxWidth: Int = 480,
        flags: SwsContext.Flag = .bicubic
    ) -> CGImage? {
        let source = softwareFrame(from: frame) ?? frame
        guard source.width > 0, source.height > 0, source.pixelFormat != .none else { return nil }

        let dstWidth = min(source.width, maxWidth)
        let dstHeight = max(1, Int(Double(dstWidth) * Double(source.height) / Double(source.width)))

        guard let sws = SwsContext(
            srcWidth: source.width,
            srcHeight: source.height,
            srcPixelFormat: source.pixelFormat,
            dstWidth: dstWidth,
            dstHeight: dstHeight,
            dstPixelFormat: .RGBA,
            flags: flags
        ) else {
            return nil
        }

        sws.setColorspaceDetails(
            sourceColorspace: .ITU709,
            sourceRange: .MPEG,
            destinationColorspace: .ITU709,
            destinationRange: .JPEG
        )

        let dstImage = AVImage(width: dstWidth, height: dstHeight, pixelFormat: .RGBA)
        let srcImage = AVImage(frame: source)

        do {
            try srcImage.reformat(using: sws, to: dstImage)
        } catch {
            return nil
        }

        let bytesPerRow = Int(dstImage.linesizes[0])
        let byteCount = bytesPerRow * dstHeight
        guard let dataPtr = dstImage.data[0] else { return nil }

        let ownedData = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: 1)
        ownedData.copyMemory(from: dataPtr, byteCount: byteCount)

        let releaseData: CGDataProviderReleaseDataCallback = { _, data, _ in
            data.deallocate()
        }

        guard let provider = CGDataProvider(
            dataInfo: nil,
            data: ownedData,
            size: byteCount,
            releaseData: releaseData
        ) else {
            ownedData.deallocate()
            return nil
        }

        return CGImage(
            width: dstWidth,
            height: dstHeight,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    private static func softwareFrame(from frame: AVFrame) -> AVFrame? {
        guard frame.hwFramesContext != nil else { return nil }
        let copy = AVFrame()
        do {
            try copy.transferData(from: frame)
            return copy
        } catch {
            return nil
        }
    }
}
