import SwiftUI
import KinemaCore
import KinemaMedia
import KinemaPlayback
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Cinematic end-of-episode card — glass poster, countdown ring, Play Now / Not now.
public struct UpNextOverlay: View {
    let offer: UpNextOffer
    let accent: Color
    let onPlayNow: () -> Void
    let onCancel: () -> Void

    @State private var deadline: Date = .distantFuture
    @State private var thumbnail: PlatformImage?
    @State private var appeared = false
    @State private var didAutoAdvance = false

    public init(
        offer: UpNextOffer,
        accent: Color,
        onPlayNow: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.offer = offer
        self.accent = accent
        self.onPlayNow = onPlayNow
        self.onCancel = onCancel
    }

    public var body: some View {
        ZStack {
            scrim

            VStack {
                Spacer(minLength: 0)
                card
                    .padding(.horizontal, horizontalPadding)
                    .padding(.bottom, bottomPadding)
                    .frame(maxWidth: cardMaxWidth)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 28)
        .onAppear {
            deadline = Date().addingTimeInterval(offer.countdownSeconds)
            withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) {
                appeared = true
            }
        }
        .task(id: offer.id) {
            deadline = Date().addingTimeInterval(offer.countdownSeconds)
            hydrateThumbnail()
            let preview = await VideoThumbnailLoader.loadPreview(
                url: offer.item.url,
                at: VideoThumbnailLoader.preferredTime(
                    for: WatchProgressStore.entry(for: offer.item.url)
                )
            )
            guard !Task.isCancelled else { return }
            thumbnail = preview.image
        }
    }

    private var horizontalPadding: CGFloat {
        #if os(tvOS)
        48
        #else
        20
        #endif
    }

    private var bottomPadding: CGFloat {
        #if os(tvOS)
        56
        #elseif os(macOS)
        36
        #else
        28
        #endif
    }

    private var cardMaxWidth: CGFloat {
        #if os(tvOS)
        520
        #elseif os(macOS)
        420
        #else
        400
        #endif
    }

    private var scrim: some View {
        LinearGradient(
            colors: [
                .black.opacity(0.05),
                .black.opacity(0.28),
                .black.opacity(0.62)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .allowsHitTesting(true)
        .onTapGesture {
            // Absorb taps so the finished frame isn't dismissed accidentally.
        }
    }

    private var card: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let remaining = max(0, deadline.timeIntervalSince(context.date))
            let progress = offer.countdownSeconds > 0
                ? remaining / offer.countdownSeconds
                : 0

            VStack(alignment: .leading, spacing: 0) {
                poster

                VStack(alignment: .leading, spacing: 14) {
                    eyebrow
                    titles
                    actions(remaining: remaining, progress: progress)
                }
                .padding(18)
            }
            .kinemaNativeGlass(cornerRadius: 22)
            .shadow(color: .black.opacity(0.45), radius: 28, y: 14)
            .onChange(of: remaining) { _, value in
                guard value <= 0.05, !didAutoAdvance else { return }
                didAutoAdvance = true
                onPlayNow()
            }
        }
    }

    private var poster: some View {
        Color.black
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                ZStack {
                    if let thumbnail {
                        #if os(macOS)
                        Image(nsImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                        #else
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                        #endif
                    } else {
                        LinearGradient(
                            colors: [
                                accent.opacity(0.35),
                                Color.black.opacity(0.85)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        Image(systemName: "film")
                            .font(.largeTitle.weight(.light))
                            .foregroundStyle(.white.opacity(0.35))
                    }

                    LinearGradient(
                        colors: [.clear, .black.opacity(0.55)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                }
            }
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 22,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 22,
                    style: .continuous
                )
            )
            .overlay(alignment: .topLeading) {
                Text(offer.episode?.seasonEpisodeCode ?? KinemaCopy.upNext)
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.45), in: Capsule())
                    .padding(12)
            }
    }

    private var eyebrow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(accent)
                .frame(width: 7, height: 7)
                .shadow(color: accent.opacity(0.7), radius: 4)
            Text(KinemaCopy.upNext.uppercased())
                .font(.caption.weight(.bold))
                .tracking(1.4)
                .foregroundStyle(accent)
            Spacer(minLength: 0)
        }
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(offer.showTitle)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
            if offer.episode != nil {
                Text(offer.detailLabel)
                    .font(.subheadline.weight(.medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.72))
            } else if offer.detailLabel != offer.showTitle {
                Text(offer.detailLabel)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(2)
            }
        }
    }

    private func actions(remaining: TimeInterval, progress: Double) -> some View {
        HStack(spacing: 12) {
            playNowButton(remaining: remaining, progress: progress)

            Button(action: onCancel) {
                Text(KinemaCopy.upNextCancel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.78))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(KinemaCopy.upNextCancel)
        }
    }

    private func playNowButton(remaining: TimeInterval, progress: Double) -> some View {
        Button(action: onPlayNow) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.22), lineWidth: 3)
                        .frame(width: 34, height: 34)
                    Circle()
                        .trim(from: 0, to: max(0.001, progress))
                        .stroke(
                            Color.white.opacity(0.95),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .frame(width: 34, height: 34)
                        .rotationEffect(.degrees(-90))
                    Text("\(max(0, Int(ceil(remaining))))")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(KinemaCopy.upNextPlayNow)
                        .font(.subheadline.weight(.semibold))
                    Text("\(KinemaCopy.upNextPlayingIn) \(max(0, Int(ceil(remaining))))s")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.78))
                }

                Spacer(minLength: 0)

                Image(systemName: "play.fill")
                    .font(.footnote.weight(.bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                LinearGradient(
                    colors: [accent, accent.opacity(0.82)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(KinemaCopy.upNextPlayNow)
    }

    private func hydrateThumbnail() {
        if let cached = VideoThumbnailLoader.cachedPreview(for: offer.item.url)?.image {
            thumbnail = cached
        }
    }
}
