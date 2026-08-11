import AVFoundation
import CoreGraphics
import FFmpegKit
import Foundation
import ImageIO

/// Embedded / sidecar cover art for Now Playing and similar surfaces.
public enum MediaCoverArt {
    private static let sidecarNames: Set<String> = [
        "cover", "folder", "poster", "front", "album", "albumart", "thumb", ".folder"
    ]
    private static let sidecarExtensions: Set<String> = [
        "jpg", "jpeg", "png", "webp", "bmp", "gif"
    ]

    /// Prefer sidecar → AV metadata artwork → FFmpeg attached picture.
    public static func loadImage(for url: URL) async -> CGImage? {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        if let sidecar = loadSidecarImage(near: url) {
            return sidecar
        }
        if let metadata = await loadAVMetadataArtwork(from: url) {
            return metadata
        }
        return await Task.detached(priority: .utility) {
            extractAttachedPicture(from: url)
        }.value
    }

    // MARK: - Sidecar

    private static func loadSidecarImage(near url: URL) -> CGImage? {
        let directory = url.deletingLastPathComponent()
        let baseName = url.deletingPathExtension().lastPathComponent.lowercased()
        let candidates = sidecarCandidates(in: directory, mediaBaseName: baseName)
        for candidate in candidates {
            if let image = decodeImageFile(at: candidate) {
                return image
            }
        }
        return nil
    }

    private static func sidecarCandidates(in directory: URL, mediaBaseName: String) -> [URL] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var namedMatches: [URL] = []
        var mediaNamedMatches: [URL] = []
        for file in contents {
            let ext = file.pathExtension.lowercased()
            guard sidecarExtensions.contains(ext) else { continue }
            let name = file.deletingPathExtension().lastPathComponent.lowercased()
            if sidecarNames.contains(name) {
                namedMatches.append(file)
            } else if name == mediaBaseName || name.hasPrefix(mediaBaseName + "-") {
                mediaNamedMatches.append(file)
            }
        }
        // Prefer generic cover/folder art, then media-named stills.
        return namedMatches + mediaNamedMatches
    }

    private static func decodeImageFile(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    // MARK: - AV metadata

    private static func loadAVMetadataArtwork(from url: URL) async -> CGImage? {
        let asset = AVURLAsset(url: url)
        do {
            let metadata = try await asset.load(.commonMetadata)
            for item in metadata where item.commonKey == .commonKeyArtwork {
                if let data = try await item.load(.dataValue),
                   let image = decodeImageData(data) {
                    return image
                }
            }
        } catch {
            return nil
        }
        return nil
    }

    // MARK: - FFmpeg attached_pic

    private static func extractAttachedPicture(from url: URL) -> CGImage? {
        do {
            let format = try AVFormatContext(url: url.path)
            try format.findStreamInfo()
            for stream in format.streams where stream.isAttachedPicture {
                guard let data = stream.copyAttachedPictureData(),
                      let image = decodeImageData(data) else { continue }
                return image
            }
        } catch {
            return nil
        }
        return nil
    }

    private static func decodeImageData(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
