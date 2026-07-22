import SwiftUI
import KinemaCore
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Grid layout

enum MediaLibraryLayout {
    static func posterColumns(horizontalSizeClass: UserInterfaceSizeClass?) -> [GridItem] {
        let minimum: CGFloat
        let maximum: CGFloat
        let spacing: CGFloat

        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad {
            minimum = 218
            maximum = 340
            spacing = 20
        } else if horizontalSizeClass == .regular {
            minimum = 190
            maximum = 280
            spacing = 18
        } else {
            minimum = 160
            maximum = 250
            spacing = 16
        }
        #elseif os(macOS)
        minimum = 200
        maximum = 310
        spacing = 20
        #else
        minimum = 200
        maximum = 320
        spacing = 20
        #endif

        return [GridItem(.adaptive(minimum: minimum, maximum: maximum), spacing: spacing, alignment: .top)]
    }

    static func gridSpacing(horizontalSizeClass: UserInterfaceSizeClass?) -> CGFloat {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad { return 20 }
        #endif
        return horizontalSizeClass == .regular ? 18 : 16
    }

    static let posterCornerRadius: CGFloat = 12
    static let posterAspect: CGFloat = 16 / 9
}

// MARK: - Video poster

struct MediaPosterCard: View {
    let url: URL
    let title: String
    let progress: WatchProgressEntry?
    let accent: Color

    @State private var thumbnail: PlatformImage?
    @State private var probedDuration: TimeInterval?
    @State private var loadFailed = false
    @State private var isLoading = false

    private var thumbTime: TimeInterval {
        VideoThumbnailLoader.preferredTime(for: progress)
    }

    private var displayDuration: TimeInterval? {
        if let progress, progress.duration > 0 { return progress.duration }
        return probedDuration
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            poster
            metadata
        }
    }

    private var poster: some View {
        Color.clear
            .aspectRatio(MediaLibraryLayout.posterAspect, contentMode: .fit)
            .overlay {
                ZStack {
                    if thumbnail == nil {
                        posterBackground
                    } else {
                        Color.black
                    }

                    thumbnailLayer

                    playHint
                        .opacity(progress == nil ? 0.55 : 1)

                    if let progress, progress.duration > 0, !progress.isMostlyFinished {
                        progressStrip(progress.progress)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: MediaLibraryLayout.posterCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: MediaLibraryLayout.posterCornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
            .onAppear {
                hydrateFromCache()
            }
            .task(id: "\(url.path)-\(thumbTime)") {
                hydrateFromCache()
                guard thumbnail == nil else { return }

                isLoading = true
                loadFailed = false

                let preview = await VideoThumbnailLoader.loadPreview(url: url, at: thumbTime)
                guard !Task.isCancelled else { return }

                isLoading = false
                thumbnail = preview.image
                probedDuration = preview.duration
                loadFailed = preview.image == nil
            }
    }

    private func hydrateFromCache() {
        guard let cached = VideoThumbnailLoader.cachedPreview(for: url) else { return }
        thumbnail = cached.image
        probedDuration = cached.duration
        loadFailed = cached.image == nil
        isLoading = false
    }

    @ViewBuilder
    private var thumbnailLayer: some View {
        if let thumbnail {
            Image(platformImage: thumbnail)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        } else if loadFailed {
            Image(systemName: "film")
                .font(.title2.weight(.light))
                .foregroundStyle(.secondary)
        } else if isLoading {
            ProgressView()
                .controlSize(.small)
        }
    }

    private var posterBackground: some View {
        LinearGradient(
            colors: [
                accent.opacity(0.22),
                Color.primary.opacity(0.06)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var playHint: some View {
        Image(systemName: "play.fill")
            .font(.title3.weight(.semibold))
            .foregroundStyle(.white)
            .padding(14)
            .background(.black.opacity(0.42), in: Circle())
            .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
    }

    private func progressStrip(_ fraction: Double) -> some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(.black.opacity(0.35))
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [accent, accent.opacity(0.85)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(geo.size.width * fraction, fraction > 0 ? 4 : 0))
                }
                .frame(height: 4)
            }
        }
        .allowsHitTesting(false)
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .foregroundStyle(.primary)

            if let progress, progress.duration > 0 {
                if progress.isMostlyFinished {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(accent)
                        Text("Watched")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(accent)
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text(formatTime(progress.duration))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                } else {
                    HStack(spacing: 6) {
                        Text("Resume \(formatTime(progress.lastPosition))")
                        Text("·")
                        Text("\(formatTime(max(0, progress.duration - progress.lastPosition))) left")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            } else if let displayDuration, displayDuration > 0 {
                Text(formatTime(displayDuration))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Folder tile

struct MediaFolderTile: View {
    let name: String
    let accent: Color
    var systemImage: String = "folder.fill"
    var subtitle: String?
    var isFullyWatched: Bool = false

    private var displaySubtitle: String? {
        if isFullyWatched {
            if let subtitle, !subtitle.isEmpty {
                return "\(KinemaCopy.folderWatched) · \(subtitle)"
            }
            return KinemaCopy.folderWatched
        }
        return subtitle
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isFullyWatched ? accent.opacity(0.08) : accent.opacity(0.14))
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: systemImage)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(isFullyWatched ? accent.opacity(0.7) : accent)
                    }

                if isFullyWatched {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(accent)
                        .background(
                            Circle()
                                .fill(KinemaTheme.cardBackground)
                                .padding(-2)
                        )
                        .offset(x: 5, y: 5)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(isFullyWatched ? .secondary : .primary)
                if let displaySubtitle {
                    Text(displaySubtitle)
                        .font(.caption.weight(isFullyWatched ? .medium : .regular))
                        .foregroundStyle(isFullyWatched ? accent : .secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if isFullyWatched {
                Image(systemName: "checkmark.circle.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(accent)
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(KinemaTheme.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .opacity(isFullyWatched ? 0.92 : 1)
    }
}

struct AddLibraryFolderTile: View {
    let accent: Color

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(accent.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(accent)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(KinemaCopy.addSource)
                    .font(.subheadline.weight(.semibold))
                Text(KinemaCopy.addSourceTileSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(KinemaTheme.cardBackground.opacity(0.65), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
