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

    static func loadPreview(url: URL, at time: TimeInterval) async -> VideoPreview {
        if Task.isCancelled {
            return VideoPreview(image: nil, duration: nil, qualityLabel: nil)
        }

        if let cached = cachedPreview(for: url) {
            return cached
        }

        let mediaID = ThumbnailDiskStore.mediaID(for: url) as NSString
        let preview = await MediaArtworkService.loadPreview(for: url, at: time)
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
