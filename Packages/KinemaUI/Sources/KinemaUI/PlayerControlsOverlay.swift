import SwiftUI
import KinemaCore
import KinemaPlayback

/// Minimal playback chrome — native Liquid Glass on controls.
public struct PlayerControlsOverlay: View {
    @Bindable var viewModel: PlayerViewModel
    let accent: Color

    @State private var scrubPosition: Double = 0
    @State private var isScrubbing = false
    @State private var chromeWidth: CGFloat = 0

    public init(viewModel: PlayerViewModel, accent: Color) {
        self.viewModel = viewModel
        self.accent = accent
    }

    private var title: String {
        viewModel.session.currentItem?.title ?? viewModel.session.info.title
    }

    private var duration: Double {
        max(viewModel.session.info.duration, 1)
    }

    private var displayedPosition: Double {
        isScrubbing ? scrubPosition : viewModel.session.info.position
    }

    private let progressHeight: CGFloat = 34

    public var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { viewModel.toggleControls() }

            topChrome
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .safeAreaPadding(.top, 4)

            bottomChrome
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .foregroundStyle(.white)
        .onChange(of: viewModel.session.info.position) { _, position in
            guard !isScrubbing else { return }
            scrubPosition = position
        }
        .onAppear {
            scrubPosition = viewModel.session.info.position
        }
    }

    private var topChrome: some View {
        HStack(spacing: 12) {
            glassCircleButton(size: 44) {
                viewModel.exitPlayer()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
            }
            .accessibilityLabel("Close player")

            HStack(spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(.white.opacity(0.95))

                if viewModel.session.isHDRContent {
                    hdrTitleTag
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(.black.opacity(0.28), in: Capsule())
            .frame(maxWidth: 460, alignment: .leading)

            Spacer(minLength: 0)
        }
    }

    /// Compact HDR wordmark tag (no public SF Symbol for the HDR logo on all OS versions).
    private var hdrTitleTag: some View {
        HStack(spacing: 3) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 8, weight: .bold))
                .symbolRenderingMode(.hierarchical)
            Text("HDR")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(0.4)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.white.opacity(0.18), in: Capsule())
        .accessibilityLabel("HDR content")
        .accessibilityAddTraits(.isStaticText)
    }

    // MARK: - Bottom

    private var speedStyle: PlaybackSpeedControl.Style {
        #if os(tvOS)
        return .menu
        #else
        // Prefer menu until we have a real measurement — never stick on the wide
        // slider because chromeWidth was still 0.
        guard chromeWidth > 1 else { return .menu }
        return chromeWidth >= PlaybackSpeedControl.inlineMinChromeWidth ? .inlineSteps : .menu
        #endif
    }

    private var bottomChrome: some View {
        VStack(spacing: 10) {
            HStack {
                Text(formatTime(displayedPosition))
                    .frame(minWidth: 48, alignment: .leading)
                Spacer()
                if viewModel.session.isABLooping {
                    Text(KinemaCopy.abLoop)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .foregroundStyle(accent.opacity(0.95))
                } else if viewModel.session.hasABLoopA {
                    Text("Loop A set")
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .foregroundStyle(accent.opacity(0.85))
                } else if let chapter = viewModel.session.currentChapter {
                    Text(chapter.displayTitle)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .foregroundStyle(.white.opacity(0.72))
                }
                Spacer()
                Text(formatTime(viewModel.session.info.duration))
                    .frame(minWidth: 48, alignment: .trailing)
            }
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(.white.opacity(0.88))

            PlayerProgressSlider(
                position: $scrubPosition,
                duration: duration,
                chapters: viewModel.session.chapters,
                abLoopA: viewModel.session.abLoopA,
                abLoopB: viewModel.session.abLoopB,
                accent: accent,
                rowHeight: progressHeight,
                isScrubbing: $isScrubbing,
                onScrubStart: { viewModel.cancelAutoHideControls() },
                onScrubEnd: { position in
                    scrubPosition = position
                    viewModel.session.seek(to: position)
                    viewModel.scheduleHideControls()
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(220))
                        isScrubbing = false
                    }
                }
            )
            .frame(maxWidth: .infinity)
            .frame(height: progressHeight)

            ZStack {
                HStack(alignment: .center, spacing: 10) {
                    iconButton(
                        viewModel.session.subtitlesAreActive ? "captions.bubble.fill" : "captions.bubble",
                        label: KinemaCopy.captions
                    ) {
                        viewModel.cancelAutoHideControls()
                        viewModel.showSubtitles = true
                    }

                    if viewModel.session.hasChapters {
                        iconButton("list.bullet.rectangle", label: KinemaCopy.chapters) {
                            viewModel.cancelAutoHideControls()
                            viewModel.showChapters = true
                        }
                    }

                    iconButton("repeat", label: KinemaCopy.abLoop) {
                        let message = viewModel.session.cycleABLoop()
                        viewModel.showOSD(message)
                        viewModel.scheduleHideControls()
                    }
                    .foregroundStyle(
                        viewModel.session.isABLooping || viewModel.session.hasABLoopA
                            ? accent
                            : Color.white
                    )

                    Spacer(minLength: 8)

                    PlaybackSpeedControl(
                        viewModel: viewModel,
                        accent: accent,
                        style: speedStyle
                    )

                    iconButton("slider.horizontal.3", label: KinemaCopy.audio) {
                        viewModel.cancelAutoHideControls()
                        viewModel.showAudio = true
                    }
                }

                transportControls
            }
            .frame(height: 52)
            .background {
                GeometryReader { geo in
                    Color.clear
                        .task(id: geo.size.width) {
                            chromeWidth = geo.size.width
                        }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .safeAreaPadding(.bottom, 2)
    }

    private var transportControls: some View {
        HStack(spacing: viewModel.session.hasChapters ? 18 : 28) {
            if viewModel.session.hasChapters {
                glassCircleButton(size: 36) {
                    viewModel.session.playPreviousChapter()
                    viewModel.showOSD(viewModel.session.currentChapter?.displayTitle ?? KinemaCopy.chapters)
                    viewModel.scheduleHideControls()
                } label: {
                    Image(systemName: "backward.end.alt.fill")
                        .font(.system(size: 14, weight: .medium))
                }
                .accessibilityLabel("Previous chapter")
            }

            glassCircleButton(size: 40) {
                viewModel.session.seekRelative(-10)
                viewModel.showOSD("-10s")
                viewModel.scheduleHideControls()
            } label: {
                Image(systemName: "gobackward.10")
                    .font(.system(size: 17, weight: .medium))
            }
            .accessibilityLabel("Back 10 seconds")

            glassCircleButton(size: 52) {
                viewModel.session.togglePlayPause()
                viewModel.scheduleHideControls()
            } label: {
                Image(systemName: viewModel.session.info.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .offset(x: viewModel.session.info.isPaused ? 1 : 0)
            }
            .accessibilityLabel(viewModel.session.info.isPaused ? "Play" : "Pause")

            glassCircleButton(size: 40) {
                viewModel.session.seekRelative(10)
                viewModel.showOSD("+10s")
                viewModel.scheduleHideControls()
            } label: {
                Image(systemName: "goforward.10")
                    .font(.system(size: 17, weight: .medium))
            }
            .accessibilityLabel("Forward 10 seconds")

            if viewModel.session.hasChapters {
                glassCircleButton(size: 36) {
                    viewModel.session.playNextChapter()
                    viewModel.showOSD(viewModel.session.currentChapter?.displayTitle ?? KinemaCopy.chapters)
                    viewModel.scheduleHideControls()
                } label: {
                    Image(systemName: "forward.end.alt.fill")
                        .font(.system(size: 14, weight: .medium))
                }
                .accessibilityLabel("Next chapter")
            }
        }
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.medium))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private func glassCircleButton<Label: View>(
        size: CGFloat,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            Button(action: action) {
                label()
                    .frame(width: size, height: size)
                    .contentShape(Circle())
            }
            .buttonStyle(KinemaGlassProminentButtonStyle())
        } else {
            Button(action: action) {
                label()
                    .frame(width: size, height: size)
                    .kinemaNativeGlassCircle()
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
        #else
        Button(action: action) {
            label()
                .frame(width: size, height: size)
                .kinemaNativeGlassCircle()
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        #endif
    }
}

// MARK: - Progress slider

private struct PlayerProgressSlider: View {
    @Binding var position: Double
    let duration: Double
    let chapters: [Chapter]
    let abLoopA: TimeInterval?
    let abLoopB: TimeInterval?
    let accent: Color
    let rowHeight: CGFloat
    @Binding var isScrubbing: Bool
    let onScrubStart: () -> Void
    let onScrubEnd: (Double) -> Void

    @State private var localPosition: Double = 0

    private var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, localPosition / duration))
    }

    var body: some View {
        ZStack {
            ChapterMarkerTrack(chapters: chapters, duration: duration, accent: accent)
                .frame(height: 4)
                .padding(.horizontal, 2)
                .allowsHitTesting(false)

            ABLoopMarkerTrack(pointA: abLoopA, pointB: abLoopB, duration: duration, accent: accent)
                .frame(height: rowHeight)
                .padding(.horizontal, 2)
                .allowsHitTesting(false)

            #if os(tvOS)
            ProgressView(value: min(max(localPosition, 0), max(duration, 0.001)), total: max(duration, 0.001))
                .tint(accent)
                .progressViewStyle(.linear)
            #else
            Slider(
                value: $localPosition,
                in: 0...max(duration, 0.001),
                onEditingChanged: { editing in
                    if editing {
                        isScrubbing = true
                        onScrubStart()
                    } else {
                        position = localPosition
                        onScrubEnd(localPosition)
                    }
                }
            )
            .tint(accent)
            #endif
        }
        .frame(height: rowHeight)
        .onAppear {
            localPosition = position
        }
        .onChange(of: localPosition) { _, value in
            if isScrubbing {
                position = value
            }
        }
        .onChange(of: position) { _, newValue in
            if !isScrubbing {
                localPosition = newValue
            }
        }
        .transaction { transaction in
            if isScrubbing {
                transaction.animation = nil
            }
        }
    }
}

/// Subtle chapter ticks under the scrubber — shared by player chrome and Music Mode.
struct ChapterMarkerTrack: View {
    let chapters: [Chapter]
    let duration: Double
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let safeDuration = max(duration, 0.001)
            ZStack(alignment: .leading) {
                ForEach(chapters) { chapter in
                    // Skip the very start mark — it coincides with the track origin.
                    if chapter.time > 0.5, chapter.time < safeDuration {
                        let x = width * min(1, max(0, chapter.time / safeDuration))
                        Capsule()
                            .fill(Color.white.opacity(0.55))
                            .frame(width: 2, height: 8)
                            .shadow(color: accent.opacity(0.35), radius: 1, y: 0)
                            .position(x: x, y: geo.size.height / 2)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// A–B loop range + labeled ticks on the scrubber.
struct ABLoopMarkerTrack: View {
    let pointA: TimeInterval?
    let pointB: TimeInterval?
    let duration: Double
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let safeDuration = max(duration, 0.001)
            let midY = geo.size.height / 2

            ZStack(alignment: .leading) {
                if let pointA, let pointB {
                    let start = min(pointA, pointB)
                    let end = max(pointA, pointB)
                    let x0 = width * min(1, max(0, start / safeDuration))
                    let x1 = width * min(1, max(0, end / safeDuration))
                    Capsule()
                        .fill(accent.opacity(0.28))
                        .frame(width: max(2, x1 - x0), height: 6)
                        .position(x: (x0 + x1) / 2, y: midY)
                }

                if let pointA {
                    loopTick(label: "A", time: pointA, width: width, safeDuration: safeDuration, midY: midY)
                }
                if let pointB {
                    loopTick(label: "B", time: pointB, width: width, safeDuration: safeDuration, midY: midY)
                }
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func loopTick(
        label: String,
        time: TimeInterval,
        width: CGFloat,
        safeDuration: Double,
        midY: CGFloat
    ) -> some View {
        let x = width * min(1, max(0, time / safeDuration))
        VStack(spacing: 1) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
            Capsule()
                .fill(accent)
                .frame(width: 2.5, height: 12)
        }
        .position(x: x, y: midY - 2)
    }
}
