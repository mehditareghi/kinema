import CoreGraphics
import FFmpegKit
import Foundation
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
    private static let snapshotPosition: Double = 0.3
    private static let minimumDecodedFrames = 4

    public static func loadPreview(for url: URL, at time: TimeInterval) async -> MediaPreview {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return await ThumbnailPipeline.shared.loadPreview(for: url, at: time)
    }

    static func extractPreview(from url: URL, at time: TimeInterval) -> MediaPreview {
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
           ffmpeg.image != nil {
            return MediaPreview(
                duration: ffmpeg.duration ?? metadata.duration,
                width: ffmpeg.width ?? metadata.width,
                height: ffmpeg.height ?? metadata.height,
                image: ffmpeg.image
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

        if let ffmpeg = extractFFmpegPreview(from: url, at: time, metadata: metadata) {
            return MediaPreview(
                duration: ffmpeg.duration ?? metadata.duration,
                width: ffmpeg.width ?? metadata.width,
                height: ffmpeg.height ?? metadata.height,
                image: ffmpeg.image
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
        if requested > 0 { return requested }
        if let duration, duration > 0 {
            return max(1, duration * snapshotPosition)
        }
        return 10
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

            for seekTime in seekTimes {
                codecContext.flush()
                let didSeek = seekTime > 0.25 && seek(
                    to: seekTime,
                    format: format,
                    streamIndex: streamIndex,
                    stream: stream
                )

                if let image = decodeRepresentativeFrame(
                    format: format,
                    codecContext: codecContext,
                    streamIndex: streamIndex,
                    frame: frame,
                    fromBeginning: !didSeek
                ) {
                    return FFmpegPreview(
                        duration: duration,
                        width: frame.width > 0 ? frame.width : width,
                        height: frame.height > 0 ? frame.height : height,
                        image: image
                    )
                }
            }

            return FFmpegPreview(duration: duration, width: width, height: height, image: nil)
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
        stream: AVStream
    ) -> [TimeInterval] {
        let resolved = resolvedSeekTime(requested: requested, duration: duration)
        var candidates = [resolved, 10, 30, 1]
        if let duration, duration > 0 {
            candidates.append(duration * snapshotPosition)
            if duration > 3 {
                candidates.append(max(1, duration - 2))
            }
            candidates = candidates.map { min($0, max(0, duration - 0.5)) }
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

    private static func decodeRepresentativeFrame(
        format: AVFormatContext,
        codecContext: AVCodecContext,
        streamIndex: Int,
        frame: AVFrame,
        fromBeginning: Bool,
        maxPackets: Int = 1200
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
        var lastImage: CGImage?

        while packetsRead < maxPackets {
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
                if let image = makeCGImage(from: frame), FrameValidator.isAcceptable(image) {
                    lastImage = image
                    if decodedFrames >= minimumDecodedFrames {
                        return image
                    }
                }
            }
        }

        return lastImage.flatMap { FrameValidator.isAcceptable($0) ? $0 : nil }
    }

    private static func makeCGImage(from frame: AVFrame) -> CGImage? {
        let source = softwareFrame(from: frame) ?? frame
        guard source.width > 0, source.height > 0, source.pixelFormat != .none else { return nil }

        let maxWidth = 480
        let dstWidth = min(source.width, maxWidth)
        let dstHeight = max(1, Int(Double(dstWidth) * Double(source.height) / Double(source.width)))

        guard let sws = SwsContext(
            srcWidth: source.width,
            srcHeight: source.height,
            srcPixelFormat: source.pixelFormat,
            dstWidth: dstWidth,
            dstHeight: dstHeight,
            dstPixelFormat: .RGBA,
            flags: .bicubic
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
