import SwiftUI
import KinemaCore
import KinemaPlaybill
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

    static let posterCornerRadius: CGFloat = 10
    static let posterAspect: CGFloat = 16 / 9
}

// MARK: - Video poster

struct MediaPosterCard: View {
    let url: URL
    let title: String
    let progress: WatchProgressEntry?
    var watch: MediaWatchSnapshot?
    let accent: Color

    private var resolvedWatch: MediaWatchSnapshot {
        watch ?? MediaWatchCoordinator.snapshot(for: url)
    }

    @State private var thumbnail: PlatformImage?
    @State private var probedDuration: TimeInterval?
    @State private var qualityLabel: String?
    @State private var loadFailed = false

    private var thumbTime: TimeInterval {
        if let progress, progress.lastPosition > 5 {
            return VideoThumbnailLoader.preferredTime(for: progress)
        }
        if resolvedWatch.resumePosition > 5 {
            return resolvedWatch.resumePosition
        }
        return VideoThumbnailLoader.preferredTime(for: progress)
    }

    private var displayDuration: TimeInterval? {
        if let progress, progress.duration > 0 { return progress.duration }
        if resolvedWatch.resumeDuration > 0 { return resolvedWatch.resumeDuration }
        return probedDuration
    }

    private var resumeFraction: Double? {
        guard resolvedWatch.hasPartialResume else { return nil }
        let duration = resolvedWatch.resumeDuration
        guard duration > 0 else { return nil }
        return min(1, max(0, resolvedWatch.resumePosition / duration))
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
            .frame(maxWidth: .infinity)
            .overlay {
                ZStack {
                    posterBackground

                    thumbnailLayer

                    cinematicVignette

                    VStack {
                        Spacer(minLength: 0)
                        HStack {
                            playHint
                            Spacer(minLength: 0)
                        }
                    }
                    .padding(10)

                    if let fraction = resumeFraction {
                        progressStrip(fraction)
                    }

                    if let qualityLabel, !qualityLabel.isEmpty {
                        qualityBadge(qualityLabel)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: MediaLibraryLayout.posterCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: MediaLibraryLayout.posterCornerRadius, style: .continuous)
                    .strokeBorder(KinemaTheme.hairline.opacity(0.84), lineWidth: 0.6)
            }
            .shadow(color: .black.opacity(0.42), radius: 14, y: 8)
            .onAppear {
                hydrateFromCache()
            }
            .task(id: "\(url.path)-\(thumbTime)") {
                hydrateFromCache()
                guard thumbnail == nil else { return }

                loadFailed = false

                let preview = await VideoThumbnailLoader.loadPreview(
                    url: url,
                    at: thumbTime,
                    priority: .visible
                )
                guard !Task.isCancelled else { return }

                // Metadata first (no layout animation), then fade the frame in.
                probedDuration = preview.duration
                qualityLabel = preview.qualityLabel
                loadFailed = preview.image == nil
                withAnimation(.easeOut(duration: 0.22)) {
                    thumbnail = preview.image
                }
            }
    }

    private func hydrateFromCache() {
        guard let cached = VideoThumbnailLoader.cachedPreview(for: url) else { return }
        thumbnail = cached.image
        probedDuration = cached.duration
        qualityLabel = cached.qualityLabel
        loadFailed = cached.image == nil
    }

    private func qualityBadge(_ label: String) -> some View {
        VStack {
            HStack {
                Spacer(minLength: 0)
                Text(label)
                    .font(KinemaType.microBold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(8)
            }
            Spacer(minLength: 0)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var thumbnailLayer: some View {
        // GeometryReader pins the image to the poster bounds so intrinsic
        // image size can never resize the placeholder vs final frame.
        GeometryReader { geo in
            ZStack {
                if let thumbnail {
                    Image(platformImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .transition(.opacity)
                } else if loadFailed {
                    Image(systemName: "film")
                        .font(.title2.weight(.light))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private var posterBackground: some View {
        LinearGradient(
            colors: [
                KinemaTheme.velvet.opacity(0.85),
                KinemaTheme.ink
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var cinematicVignette: some View {
        LinearGradient(
            colors: [.clear, .clear, .black.opacity(0.68)],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
    }

    private var playHint: some View {
        Image(systemName: "play.fill")
            .font(KinemaType.metadataBold)
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(accent.opacity(0.92), in: Circle())
            .overlay(Circle().strokeBorder(KinemaTheme.projectorWhite.opacity(0.30), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.38), radius: 8, y: 3)
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
                .font(KinemaType.posterTitle)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
                .foregroundStyle(.primary)

            metadataSubtitle
                .font(KinemaType.metadata)
                .lineLimit(1, reservesSpace: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var metadataSubtitle: some View {
        if resolvedWatch.isWatched, !resolvedWatch.hasPartialResume {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(KinemaType.metadataStrong)
                    .foregroundStyle(accent)
                Text(KinemaCopy.watchedLabel(count: resolvedWatch.watchCount))
                    .font(KinemaType.metadataMedium)
                    .foregroundStyle(accent)
                if let duration = displayDuration, duration > 0 {
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(formatTime(duration))
                        .foregroundStyle(.secondary)
                }
            }
        } else if resolvedWatch.hasPartialResume {
            HStack(spacing: 6) {
                Text("Resume \(formatTime(resolvedWatch.resumePosition))")
                if resolvedWatch.resumeDuration > 0 {
                    Text("·")
                    Text("\(formatTime(max(0, resolvedWatch.resumeDuration - resolvedWatch.resumePosition))) left")
                }
            }
            .foregroundStyle(.secondary)
        } else if let displayDuration, displayDuration > 0 {
            HStack(spacing: 6) {
                Text(formatTime(displayDuration))
                if let qualityLabel, !qualityLabel.isEmpty {
                    Text("·")
                    Text(qualityLabel)
                }
            }
            .foregroundStyle(.secondary)
        } else if let qualityLabel, !qualityLabel.isEmpty {
            Text(qualityLabel)
                .foregroundStyle(.secondary)
        } else {
            // Keep layout height identical before duration/quality are known.
            Text(" ")
                .foregroundStyle(.clear)
                .accessibilityHidden(true)
        }
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
                            .font(KinemaType.bodyStrong)
                            .foregroundStyle(isFullyWatched ? accent.opacity(0.7) : accent)
                    }

                if isFullyWatched {
                    Image(systemName: "checkmark.circle.fill")
                        .font(KinemaType.metadataBold)
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
                    .font(KinemaType.label)
                    .lineLimit(1)
                    .foregroundStyle(isFullyWatched ? .secondary : .primary)
                if let displaySubtitle {
                    Text(displaySubtitle)
                        .font(KinemaType.metadata.weight(isFullyWatched ? .medium : .regular))
                        .foregroundStyle(isFullyWatched ? accent : .secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if isFullyWatched {
                Image(systemName: "checkmark.circle.fill")
                    .font(KinemaType.bodyStrong)
                    .foregroundStyle(accent)
            } else {
                Image(systemName: "chevron.right")
                    .font(KinemaType.metadataStrong)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(KinemaTheme.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(KinemaTheme.hairline.opacity(0.72), lineWidth: 0.5)
        }
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
                        .font(KinemaType.bodyStrong)
                        .foregroundStyle(accent)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(KinemaCopy.addSource)
                    .font(KinemaType.labelStrong)
                Text(KinemaCopy.addSourceTileSubtitle)
                    .font(KinemaType.metadata)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(KinemaTheme.cardBackground.opacity(0.65), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(KinemaTheme.hairline.opacity(0.72), lineWidth: 0.5)
        }
    }
}

/// Same footprint as `MediaFolderTile`, with accent treatment for the built-in source.
struct BuiltInLibrarySourceTile: View {
    let accent: Color
    var isFullyWatched: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [accent, accent.opacity(0.72)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: "film.stack.fill")
                        .font(KinemaType.bodyStrong)
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(KinemaCopy.appName)
                        .font(KinemaType.labelStrong)
                        .lineLimit(1)
                        .foregroundStyle(isFullyWatched ? .secondary : .primary)

                    Text(KinemaCopy.builtInSourceBadge)
                        .font(KinemaType.microBold)
                        .foregroundStyle(accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(accent.opacity(0.14), in: Capsule())
                }

                Text(KinemaCopy.builtInSourceSubtitle)
                    .font(KinemaType.metadata)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(KinemaType.metadataStrong)
                .foregroundStyle(accent.opacity(0.8))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(KinemaTheme.cardBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(accent.opacity(0.35), lineWidth: 1.5)
                }
        }
        .opacity(isFullyWatched ? 0.92 : 1)
    }
}
