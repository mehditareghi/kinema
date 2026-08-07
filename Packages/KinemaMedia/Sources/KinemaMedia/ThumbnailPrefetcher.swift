import Foundation

/// Warms the thumbnail cache in the background so scrolling feels instant on revisit.
public enum ThumbnailPrefetcher {
    public static func schedule(_ urls: [URL]) {
        guard !urls.isEmpty else { return }

        Task.detached(priority: .background) {
            for url in urls {
                if Task.isCancelled { return }
                // Skip work we already paid for — prefetch should never block visible loads.
                _ = await MediaArtworkService.loadPreview(
                    for: url,
                    at: 0,
                    priority: .background
                )
            }
        }
    }
}
