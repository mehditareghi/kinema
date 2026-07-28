import SwiftUI
import KinemaCore
import KinemaPlayback

/// Minimal playback chrome — native Liquid Glass on controls.
public struct PlayerControlsOverlay: View {
    @Bindable var viewModel: PlayerViewModel
    let accent: Color

    @State private var scrubPosition: Double = 0
    @State private var isScrubbing = false

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

            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(.white.opacity(0.95))
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(.black.opacity(0.28), in: Capsule())
                .frame(maxWidth: 460, alignment: .leading)

            Spacer(minLength: 0)
        }
    }

    // MARK: - Bottom

    private var bottomChrome: some View {
        VStack(spacing: 10) {
            HStack {
                Text(formatTime(displayedPosition))
                    .frame(minWidth: 48, alignment: .leading)
                Spacer()
                Text(formatTime(viewModel.session.info.duration))
                    .frame(minWidth: 48, alignment: .trailing)
            }
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(.white.opacity(0.88))

            PlayerProgressSlider(
                position: $scrubPosition,
                duration: duration,
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

            // One row under the scrubber — same height budget as before, so the
            // timeline stays where it was; transport sits in the middle.
            ZStack {
                HStack(alignment: .center, spacing: 12) {
                    iconButton(
                        viewModel.session.subtitlesAreActive ? "captions.bubble.fill" : "captions.bubble",
                        label: KinemaCopy.captions
                    ) {
                        viewModel.cancelAutoHideControls()
                        viewModel.showSubtitles = true
                    }

                    Spacer(minLength: 12)

                    iconButton("gearshape", label: KinemaCopy.preferences) {
                        viewModel.cancelAutoHideControls()
                        viewModel.showSettings = true
                    }
                }

                transportControls
            }
            .frame(height: 52)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .safeAreaPadding(.bottom, 2)
    }

    private var transportControls: some View {
        HStack(spacing: 28) {
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
