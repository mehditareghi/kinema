import AVFoundation
import Foundation
import KinemaMedia
import SwiftUI
import KinemaCore
#if os(iOS) || os(macOS)
import QuickLookThumbnailing
#endif
#if os(macOS)
import AppKit
#else
import UIKit
#endif

#if os(macOS)
typealias PlatformImage = NSImage
#else
typealias PlatformImage = UIImage
#endif

struct VideoPreview {
    let image: PlatformImage?
    let duration: TimeInterval?
    let qualityLabel: String?
}

enum VideoThumbnailLoader {
    private static let memoryCache: NSCache<NSString, PlatformImage> = {
        let cache = NSCache<NSString, PlatformImage>()
        cache.countLimit = 120
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()

    /// Canonical snapshot time — actual seek is resolved inside MediaArtworkService.
    static let canonicalTime: TimeInterval = 0

    /// Picks a representative frame: resume point when meaningful, otherwise 30% into the file.
    static func preferredTime(for progress: WatchProgressEntry?) -> TimeInterval {
        guard let progress, progress.duration > 0 else { return canonicalTime }
        if progress.isMostlyFinished {
            return max(1, progress.duration - 3)
        }
        if progress.lastPosition > 8 {
            return progress.lastPosition
        }
        return min(45, max(1, progress.duration * 0.3))
    }

    /// Instant path: memory + disk only, no decoding.
    static func cachedPreview(for url: URL) -> VideoPreview? {
        let mediaID = ThumbnailDiskStore.mediaID(for: url) as NSString

        if let image = memoryCache.object(forKey: mediaID) {
            if isAcceptable(image) {
                let disk = ThumbnailDiskStore.cachedSnapshot(for: url)
                return VideoPreview(
                    image: image,
                    duration: disk?.duration,
                    qualityLabel: disk?.qualityLabel
                )
            }
            memoryCache.removeObject(forKey: mediaID)
        }

        if let disk = ThumbnailDiskStore.cachedSnapshot(for: url) {
            if let image = disk.image, isAcceptable(image) {
                memoryCache.setObject(image, forKey: mediaID)
                return disk
            }
            ThumbnailDiskStore.remove(for: url)
        }

        return nil
    }

    static func loadPreview(
        url: URL,
        at time: TimeInterval,
        priority: ThumbnailPipeline.Priority = .visible
    ) async -> VideoPreview {
        if Task.isCancelled {
            return VideoPreview(image: nil, duration: nil, qualityLabel: nil)
        }

        if let cached = cachedPreview(for: url) {
            return cached
        }

        let mediaID = ThumbnailDiskStore.mediaID(for: url) as NSString

        // Pipeline-limited decode (max 2). AV-first for friendly containers lives inside
        // MediaArtworkService — never fire unbounded AV/QuickLook from the scroll grid.
        let preview = await MediaArtworkService.loadPreview(for: url, at: time, priority: priority)
        if Task.isCancelled {
            return VideoPreview(image: nil, duration: nil, qualityLabel: nil)
        }

        if let cgImage = preview.image, isAcceptable(cgImage) {
            return store(
                makePlatformImage(from: cgImage),
                duration: preview.duration,
                qualityLabel: preview.qualityLabel,
                for: url,
                mediaID: mediaID
            )
        }

        let seekTimes = seekCandidates(requested: time, duration: preview.duration)
        for seekTime in seekTimes {
            if Task.isCancelled {
                return VideoPreview(image: nil, duration: preview.duration, qualityLabel: preview.qualityLabel)
            }
            if let generated = await generate(url: url, at: seekTime), isAcceptable(generated) {
                return store(
                    generated,
                    duration: preview.duration,
                    qualityLabel: preview.qualityLabel,
                    for: url,
                    mediaID: mediaID
                )
            }
        }

        if let quickLook = await quickLookThumbnail(url: url), isAcceptable(quickLook) {
            return store(
                quickLook,
                duration: preview.duration,
                qualityLabel: preview.qualityLabel,
                for: url,
                mediaID: mediaID
            )
        }

        return VideoPreview(
            image: nil,
            duration: preview.duration,
            qualityLabel: preview.qualityLabel
        )
    }

    static func load(url: URL, at time: TimeInterval) async -> PlatformImage? {
        await loadPreview(url: url, at: time).image
    }

    private static func store(
        _ image: PlatformImage,
        duration: TimeInterval?,
        qualityLabel: String?,
        for url: URL,
        mediaID: NSString
    ) -> VideoPreview {
        memoryCache.setObject(image, forKey: mediaID)
        ThumbnailDiskStore.save(
            image: image,
            duration: duration,
            qualityLabel: qualityLabel,
            for: url
        )
        return VideoPreview(image: image, duration: duration, qualityLabel: qualityLabel)
    }

    private static func seekCandidates(requested: TimeInterval, duration: TimeInterval?) -> [TimeInterval] {
        var candidates: [TimeInterval] = []
        if requested > 0 {
            candidates.append(requested)
        }
        candidates.append(contentsOf: [10, 30, 1, 45])
        if let duration, duration > 0 {
            candidates.append(max(1, duration * 0.3))
            if duration > 3 {
                candidates.append(max(1, duration - 2))
            }
            candidates = candidates.map { min($0, max(0.5, duration - 0.5)) }
        }

        var seen = Set<Int>()
        return candidates.filter { value in
            seen.insert(Int(value * 1000)).inserted
        }
    }

    private static func generate(url: URL, at time: TimeInterval) async -> PlatformImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 270)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 4, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 4, preferredTimescale: 600)

        let seekTime = time > 0 ? time : 10
        let cmTime = CMTime(seconds: max(0, seekTime), preferredTimescale: 600)
        return await withCheckedContinuation { continuation in
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: cmTime)]) { _, cgImage, _, result, _ in
                guard result == .succeeded, let cgImage else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: makePlatformImage(from: cgImage))
            }
        }
    }

    private static func quickLookThumbnail(url: URL) async -> PlatformImage? {
        #if os(iOS) || os(macOS)
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 480, height: 270),
            scale: 2,
            representationTypes: .thumbnail
        )

        return await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                guard let cgImage = representation?.cgImage else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: makePlatformImage(from: cgImage))
            }
        }
        #else
        return nil
        #endif
    }

    private static func isAcceptable(_ image: PlatformImage) -> Bool {
        guard let cgImage = cgImage(from: image) else { return false }
        return MediaFrameValidator.isAcceptable(cgImage)
    }

    private static func isAcceptable(_ image: CGImage) -> Bool {
        MediaFrameValidator.isAcceptable(image)
    }

    private static func cgImage(from image: PlatformImage) -> CGImage? {
        #if os(macOS)
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        #else
        return image.cgImage
        #endif
    }

    private static func makePlatformImage(from cgImage: CGImage) -> PlatformImage {
        #if os(macOS)
        let size = NSSize(width: cgImage.width, height: cgImage.height)
        return NSImage(cgImage: cgImage, size: size)
        #else
        return UIImage(cgImage: cgImage)
        #endif
    }
}

#if os(macOS)
extension Image {
    init(platformImage: NSImage) {
        self.init(nsImage: platformImage)
    }
}
#else
extension Image {
    init(platformImage: UIImage) {
        self.init(uiImage: platformImage)
    }
}
#endif

// MARK: - Scrub seek preview (filmstrip)

/// Shows nearest filmstrip frame immediately; background fill keeps scrubbing fluid.
@MainActor
@Observable
final class ScrubFrameLoader {
    private(set) var image: PlatformImage?
    private(set) var displayTime: TimeInterval = 0

    private var mediaURL: URL?
    private var duration: TimeInterval = 0
    private var refineTask: Task<Void, Never>?
    private var requestID: UInt64 = 0

    func bind(url: URL?, duration: TimeInterval) {
        let normalized = url?.standardizedFileURL
        let safeDuration = max(duration, 1)
        let same =
            normalized == mediaURL
            && abs(self.duration - safeDuration) < 1

        mediaURL = normalized
        self.duration = safeDuration

        if let normalized {
            ScrubFrameExtractor.shared.prepare(url: normalized, duration: safeDuration)
            if !same {
                image = nil
                requestID &+= 1
            }
        } else {
            ScrubFrameExtractor.shared.reset()
            image = nil
            requestID &+= 1
        }
    }

    func request(time: TimeInterval) {
        displayTime = max(0, time)
        guard let mediaURL else {
            image = nil
            return
        }

        // Instant path: nearest strip frame (no await).
        if let nearest = ScrubFrameExtractor.shared.nearestFrame(at: displayTime) {
            image = Self.makePlatformImage(from: nearest)
        }

        requestID &+= 1
        let id = requestID
        refineTask?.cancel()
        let needsUrgentFill = image == nil
        refineTask = Task { [weak self] in
            if !needsUrgentFill {
                try? await Task.sleep(nanoseconds: 8_000_000)
                guard !Task.isCancelled else { return }
            }
            await self?.refine(url: mediaURL, requestID: id)
        }
    }

    func endSession() {
        refineTask?.cancel()
        refineTask = nil
        requestID &+= 1
        // Keep last image / strip warm for the next scrub.
    }

    private func refine(url: URL, requestID: UInt64) async {
        let target = displayTime
        let cgImage = await MediaArtworkService.extractScrubFrame(from: url, at: target)
        guard requestID == self.requestID else { return }
        guard let cgImage else { return }
        // Only replace if we're still near the refined time (avoid visual jump backwards).
        if abs(displayTime - target) < 1.25 {
            image = Self.makePlatformImage(from: cgImage)
        }
    }

    private static func makePlatformImage(from cgImage: CGImage) -> PlatformImage {
        #if os(macOS)
        let size = NSSize(width: cgImage.width, height: cgImage.height)
        return NSImage(cgImage: cgImage, size: size)
        #else
        return UIImage(cgImage: cgImage)
        #endif
    }
}

/// Floating frame + time chip shown above the scrubber thumb.
struct ScrubPreviewBubble: View {
    let image: PlatformImage?
    let time: TimeInterval
    let accent: Color

    static let previewWidth: CGFloat = 168
    static let previewHeight: CGFloat = 94

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.55))
                if let image {
                    Image(platformImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: Self.previewWidth, height: Self.previewHeight)
                        .clipped()
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white.opacity(0.7))
                }
            }
            .frame(width: Self.previewWidth, height: Self.previewHeight)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.45), radius: 10, y: 4)

            Text(formatTime(time))
                .font(KinemaType.timecode)
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.72), in: Capsule())
                .overlay(Capsule().strokeBorder(accent.opacity(0.55), lineWidth: 0.5))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview at \(formatTime(time))")
    }
}

/// Maps scrub progress to the visual center of a SwiftUI `Slider` thumb.
enum ScrubThumbGeometry {
    /// Approximate leading/trailing inset of the default Slider thumb travel.
    static let trackInset: CGFloat = 15
    /// Keep the preview fully inside the scrubber/chrome bounds.
    static let edgeMargin: CGFloat = 8

    static func thumbCenterX(fraction: CGFloat, in width: CGFloat) -> CGFloat {
        let inset = trackInset
        let usable = max(1, width - inset * 2)
        return inset + usable * min(1, max(0, fraction))
    }

    /// Prefer thumb-centering, but clamp so the bubble never hangs off-screen.
    static func bubbleCenterX(
        thumbX: CGFloat,
        bubbleWidth: CGFloat,
        in width: CGFloat
    ) -> CGFloat {
        let half = bubbleWidth / 2
        let minX = half + edgeMargin
        let maxX = width - half - edgeMargin
        guard maxX >= minX else { return width / 2 }
        return min(max(thumbX, minX), maxX)
    }
}
