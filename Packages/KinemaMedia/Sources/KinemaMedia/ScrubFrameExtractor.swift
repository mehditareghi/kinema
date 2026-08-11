import AVFoundation
import CoreGraphics
import FFmpegKit
import Foundation
import KinemaCore

/// Filmstrip cache for scrub previews: nearest-frame reads never wait on decode.
public final class ScrubFrameExtractor: @unchecked Sendable {
    public static let shared = ScrubFrameExtractor()

    private let workQueue = DispatchQueue(label: "kinema.scrub-filmstrip", qos: .userInitiated)
    private let stripLock = NSLock()
    private var strip: [Int: CGImage] = [:]
    private var step: TimeInterval = 2
    private var duration: TimeInterval = 0
    private var urlPath: String?
    private var avWorks: Bool?
    private var format: AVFormatContext?
    private var codecContext: AVCodecContext?
    private var streamIndex: Int?
    private var stream: AVStream?
    private var frame = AVFrame()
    private var generation: UInt64 = 0
    private var avGenerator: AVAssetImageGenerator?

    private init() {}

    public func prepare(url: URL, duration: TimeInterval) {
        workQueue.async {
            self.prepareLocked(url: url, duration: max(duration, 1))
        }
    }

    public func reset() {
        workQueue.async {
            self.generation &+= 1
            self.tearDown()
            self.stripLock.lock()
            self.strip.removeAll()
            self.stripLock.unlock()
            self.urlPath = nil
            self.duration = 0
            self.avWorks = nil
        }
    }

    /// Instant nearest filmstrip frame — never blocks on decode.
    public func nearestFrame(at time: TimeInterval) -> CGImage? {
        stripLock.lock()
        defer { stripLock.unlock() }
        return nearestLocked(at: time)
    }

    public func frame(at time: TimeInterval, url: URL) async -> CGImage? {
        await withCheckedContinuation { continuation in
            workQueue.async {
                self.prepareLocked(url: url, duration: max(self.duration, 1))

                if let hit = self.nearestFrame(at: time), self.hasTightCoverage(for: time) {
                    continuation.resume(returning: hit)
                    self.fillNeighbors(around: time)
                    return
                }

                let decoded = self.decodeAndStore(at: time)
                continuation.resume(returning: decoded ?? self.nearestFrame(at: time))
                self.fillNeighbors(around: time)
            }
        }
    }

    // MARK: - Setup

    private func prepareLocked(url: URL, duration: TimeInterval) {
        let path = url.standardizedFileURL.path
        stripLock.lock()
        let warm = urlPath == path && abs(self.duration - duration) < 1 && !strip.isEmpty
        stripLock.unlock()
        if warm { return }

        generation &+= 1
        let gen = generation
        tearDown()
        stripLock.lock()
        strip.removeAll(keepingCapacity: true)
        stripLock.unlock()

        urlPath = path
        self.duration = duration
        step = Self.step(for: duration)
        avWorks = nil

        if buildAVFilmstrip(url: url, generation: gen) {
            avWorks = true
            return
        }

        avWorks = false
        openFFmpeg(url: url)
        // Chunked fill so nearest-frame reads stay responsive.
        fillFFmpegFilmstripAsync(generation: gen)
    }

    private func tearDown() {
        avGenerator?.cancelAllCGImageGeneration()
        avGenerator = nil
        format = nil
        codecContext = nil
        streamIndex = nil
        stream = nil
    }

    private static func step(for duration: TimeInterval) -> TimeInterval {
        let samples = duration < 120 ? 56.0 : 72.0
        return max(0.4, duration / samples)
    }

    private func index(for time: TimeInterval) -> Int {
        Int((max(0, time) / max(step, 0.1)).rounded())
    }

    private func sampleTime(for index: Int) -> TimeInterval {
        min(max(0, Double(index) * step), max(0, duration - 0.05))
    }

    private func nearestLocked(at time: TimeInterval) -> CGImage? {
        guard !strip.isEmpty else { return nil }
        let target = index(for: time)
        if let exact = strip[target] { return exact }
        var best: CGImage?
        var bestDistance = Int.max
        for (idx, image) in strip {
            let distance = abs(idx - target)
            if distance < bestDistance {
                bestDistance = distance
                best = image
            }
        }
        return best
    }

    private func hasTightCoverage(for time: TimeInterval) -> Bool {
        stripLock.lock()
        defer { stripLock.unlock() }
        let target = index(for: time)
        return strip[target] != nil || strip[target - 1] != nil || strip[target + 1] != nil
    }

    private func store(_ image: CGImage, at time: TimeInterval) {
        stripLock.lock()
        strip[index(for: time)] = image
        stripLock.unlock()
    }

    // MARK: - AV path

    private func buildAVFilmstrip(url: URL, generation: UInt64) -> Bool {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 220, height: 124)
        let tolerance = min(1.5, step)
        generator.requestedTimeToleranceBefore = CMTime(seconds: tolerance, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: tolerance, preferredTimescale: 600)

        var actual = CMTime.zero
        let probeAt = CMTime(
            seconds: min(max(0.2, duration * 0.05), max(0, duration - 0.05)),
            preferredTimescale: 600
        )
        guard let probe = try? generator.copyCGImage(at: probeAt, actualTime: &actual) else {
            return false
        }
        store(probe, at: probeAt.seconds)

        let count = max(1, Int(ceil(duration / step)))
        let times: [NSValue] = (0..<count).map { idx in
            NSValue(time: CMTime(seconds: sampleTime(for: idx), preferredTimescale: 600))
        }

        avGenerator = generator
        generator.generateCGImagesAsynchronously(forTimes: times) { [weak self] requested, cgImage, _, result, _ in
            guard let self else { return }
            guard generation == self.generation else { return }
            if result == .succeeded, let cgImage {
                self.store(cgImage, at: requested.seconds)
            }
        }
        return true
    }

    private static func avCopy(url: URL, time: TimeInterval, step: TimeInterval) -> CGImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 220, height: 124)
        let tolerance = min(1.5, step)
        generator.requestedTimeToleranceBefore = CMTime(seconds: tolerance, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: tolerance, preferredTimescale: 600)
        var actual = CMTime.zero
        return try? generator.copyCGImage(
            at: CMTime(seconds: max(0, time), preferredTimescale: 600),
            actualTime: &actual
        )
    }

    // MARK: - FFmpeg path

    private func openFFmpeg(url: URL) {
        tearDown()
        guard LibraryMediaPaths.isStableMediaFile(url) else { return }
        do {
            let format = try AVFormatContext(url: url.path)
            try format.findStreamInfo()
            guard let streamIndex = format.findBestStream(type: .video) else { return }
            let stream = format.streams[streamIndex]
            guard let codec = AVCodec.findDecoderById(stream.codecParameters.codecId) else { return }
            let codecContext = AVCodecContext(codec: codec)
            codecContext.setParameters(stream.codecParameters)
            try codecContext.openCodec(codec)
            if duration <= 1, let probed = Self.probeDuration(format: format) {
                duration = probed
                step = Self.step(for: probed)
            }
            self.format = format
            self.codecContext = codecContext
            self.streamIndex = streamIndex
            self.stream = stream
            self.frame = AVFrame()
            self.urlPath = url.standardizedFileURL.path
        } catch {
            tearDown()
        }
    }

    private func fillFFmpegFilmstripAsync(generation: UInt64) {
        let count = max(1, Int(ceil(duration / step)))
        func fillNext(_ idx: Int) {
            guard generation == self.generation else { return }
            guard idx < count else { return }
            if self.stripMissing(idx) {
                _ = self.decodeAndStore(at: self.sampleTime(for: idx))
            }
            // Yield between samples so scrub lookups stay snappy.
            self.workQueue.async {
                fillNext(idx + 1)
            }
        }
        fillNext(0)
    }

    private func stripMissing(_ idx: Int) -> Bool {
        stripLock.lock()
        defer { stripLock.unlock() }
        return strip[idx] == nil
    }

    private func fillNeighbors(around time: TimeInterval) {
        let center = index(for: time)
        for offset in [0, -1, 1, -2, 2, -3, 3] {
            let idx = center + offset
            guard idx >= 0 else { continue }
            if !stripMissing(idx) { continue }
            _ = decodeAndStore(at: sampleTime(for: idx))
        }
    }

    private func decodeAndStore(at time: TimeInterval) -> CGImage? {
        if let image = decodeOne(at: time) {
            store(image, at: time)
            return image
        }
        return nil
    }

    private func decodeOne(at time: TimeInterval) -> CGImage? {
        if avWorks != false, let path = urlPath {
            if let image = Self.avCopy(url: URL(fileURLWithPath: path), time: time, step: step) {
                avWorks = true
                return image
            }
            if avWorks == nil {
                avWorks = false
                openFFmpeg(url: URL(fileURLWithPath: path))
            }
        }

        guard let format,
              let codecContext,
              let streamIndex,
              let stream else { return nil }

        let seekTime = Self.clamped(time, duration: duration)
        let didSeek = seekTime > 0.02 && Self.seek(
            to: seekTime,
            format: format,
            streamIndex: streamIndex,
            stream: stream
        )
        codecContext.flush()
        if !didSeek {
            do {
                try format.seekFrame(to: 0, streamIndex: streamIndex, flags: [.backward])
                codecContext.flush()
            } catch {}
        }

        let packet = AVPacket()
        var packetsRead = 0
        var decodedFrames = 0
        var seenKeyframe = false

        while packetsRead < 80 {
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
                } catch let error as FFmpegKit.AVError where error == .tryAgain {
                    break
                } catch {
                    break
                }
                guard frame.width > 0, frame.height > 0 else { continue }
                decodedFrames += 1
                if !seenKeyframe {
                    if frame.isKeyFrame || frame.pictureType == .I {
                        seenKeyframe = true
                    } else if decodedFrames < 10 {
                        continue
                    } else {
                        seenKeyframe = true
                    }
                }
                if let image = MediaArtworkService.makeScrubCGImage(from: frame) {
                    return image
                }
            }
        }
        return nil
    }

    private static func clamped(_ time: TimeInterval, duration: TimeInterval) -> TimeInterval {
        guard duration > 0 else { return max(0, time) }
        return min(max(0, time), max(0, duration - 0.05))
    }

    private static func probeDuration(format: AVFormatContext) -> TimeInterval? {
        if format.duration > 0, format.duration != AVTimestamp.noPTS {
            return Double(format.duration) / Double(AVTimestamp.timebase)
        }
        return nil
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
            try format.seekFrame(to: timestamp, streamIndex: streamIndex, flags: [.backward])
            return true
        } catch {
            do {
                try format.seekFrame(to: timestamp, streamIndex: streamIndex, flags: [.backward, .any])
                return true
            } catch {
                return false
            }
        }
    }
}
