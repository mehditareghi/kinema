import Foundation
import KinemaCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct ThumbnailMetadata: Codable {
    let duration: TimeInterval?
    let qualityLabel: String?
}

enum ThumbnailDiskStore {
    static func mediaID(for url: URL) -> String {
        PlaybackHistoryEntry.mediaID(for: url)
    }

    static func cachedSnapshot(for url: URL) -> VideoPreview? {
        let id = mediaID(for: url)
        let imageURL = imageFileURL(for: id)
        guard let image = loadImage(from: imageURL) else { return nil }

        let metadata = loadMetadata(for: id)
        return VideoPreview(
            image: image,
            duration: metadata?.duration,
            qualityLabel: metadata?.qualityLabel
        )
    }

    static func remove(for url: URL) {
        let id = mediaID(for: url)
        try? FileManager.default.removeItem(at: imageFileURL(for: id))
        try? FileManager.default.removeItem(at: metadataFileURL(for: id))
    }

    static func save(
        image: PlatformImage,
        duration: TimeInterval?,
        qualityLabel: String?,
        for url: URL
    ) {
        let id = mediaID(for: url)
        saveImage(image, to: imageFileURL(for: id))
        saveMetadata(
            ThumbnailMetadata(duration: duration, qualityLabel: qualityLabel),
            for: id
        )
    }

    private static func thumbnailsDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("Kinema/thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func imageFileURL(for mediaID: String) -> URL {
        thumbnailsDirectory().appendingPathComponent("\(stableHash(mediaID)).jpg")
    }

    private static func metadataFileURL(for mediaID: String) -> URL {
        thumbnailsDirectory().appendingPathComponent("\(stableHash(mediaID)).json")
    }

    private static func stableHash(_ value: String) -> String {
        var hash: UInt64 = 5381
        for byte in value.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return String(hash, radix: 16)
    }

    private static func loadImage(from url: URL) -> PlatformImage? {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return nil }
        #if os(macOS)
        return NSImage(data: data)
        #else
        return UIImage(data: data)
        #endif
    }

    private static func saveImage(_ image: PlatformImage, to url: URL) {
        #if os(macOS)
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.86]) else { return }
        #else
        guard let data = image.jpegData(compressionQuality: 0.86) else { return }
        #endif
        try? data.write(to: url, options: .atomic)
    }

    private static func loadMetadata(for mediaID: String) -> ThumbnailMetadata? {
        let url = metadataFileURL(for: mediaID)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ThumbnailMetadata.self, from: data)
    }

    private static func saveMetadata(_ metadata: ThumbnailMetadata, for mediaID: String) {
        guard let data = try? JSONEncoder().encode(metadata) else { return }
        try? data.write(to: metadataFileURL(for: mediaID), options: .atomic)
    }
}
