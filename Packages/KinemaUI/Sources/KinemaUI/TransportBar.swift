import SwiftUI
import KinemaCore
import KinemaPlayback

public struct TransportBar: View {
    @Bindable var viewModel: PlayerViewModel
    let accent: Color
    @State private var scrubPosition: Double = 0
    @State private var isScrubbing = false

    private let maxBarWidth: CGFloat = 560

    public init(viewModel: PlayerViewModel, accent: Color) {
        self.viewModel = viewModel
        self.accent = accent
    }

    public var body: some View {
        VStack(spacing: 14) {
            progressRow
            SpeedPickerStrip(viewModel: viewModel, accent: accent)
            controlsRow
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: maxBarWidth)
        .kinemaLiquidGlass(cornerRadius: 24)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .onChange(of: viewModel.session.info.position) { _, position in
            if !isScrubbing { scrubPosition = position }
        }
        .onAppear {
            scrubPosition = viewModel.session.info.position
        }
    }

    private var progressRow: some View {
        VStack(spacing: 6) {
            Slider(
                value: $scrubPosition,
                in: 0...max(viewModel.session.info.duration, 1)
            ) { editing in
                isScrubbing = editing
                if editing {
                    viewModel.cancelAutoHideControls()
                } else {
                    viewModel.session.seek(to: scrubPosition)
                    viewModel.scheduleHideControls()
                }
            }
            .tint(accent)

            HStack {
                Text(formatTime(viewModel.session.info.position))
                Spacer()
                Text(formatTime(viewModel.session.info.duration))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private var controlsRow: some View {
        HStack(spacing: 0) {
            transportButton("backward.end.fill", label: "Previous") {
                viewModel.session.playPrevious()
            }
            transportButton("gobackward.10", label: "Back 10 seconds") {
                viewModel.session.seekRelative(-10)
                viewModel.showOSD("-10s")
            }

            Button {
                viewModel.session.togglePlayPause()
                viewModel.scheduleHideControls()
            } label: {
                Image(systemName: viewModel.session.info.isPaused ? "play.fill" : "pause.fill")
                    .font(.title2.weight(.semibold))
                    .frame(width: 52, height: 52)
                    .background(accent.opacity(0.22), in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.2), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 6)

            transportButton("goforward.10", label: "Forward 10 seconds") {
                viewModel.session.seekRelative(10)
                viewModel.showOSD("+10s")
            }
            transportButton("forward.end.fill", label: "Next") {
                viewModel.session.playNext()
            }

            Spacer(minLength: 4)
            PlayerToolsMenu(viewModel: viewModel, accent: accent)
        }
        .foregroundStyle(.white)
    }

    private func transportButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct SpeedPickerStrip: View {
    @Bindable var viewModel: PlayerViewModel
    let accent: Color

    private let speeds: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    var body: some View {
        HStack(spacing: 8) {
            Button {
                nudgeSpeed(by: -0.25)
            } label: {
                Image(systemName: "minus")
                    .font(.caption.weight(.bold))
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(speeds, id: \.self) { speed in
                        speedChip(speed)
                    }
                }
                .padding(.horizontal, 2)
            }

            Button {
                nudgeSpeed(by: 0.25)
            } label: {
                Image(systemName: "plus")
                    .font(.caption.weight(.bold))
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
    }

    private func speedChip(_ speed: Double) -> some View {
        let selected = abs(viewModel.session.info.speed - speed) < 0.01
        return Button {
            viewModel.session.setSpeed(speed)
            viewModel.showOSD(String(format: "%.2g×", speed))
            viewModel.scheduleHideControls()
        } label: {
            Text(String(format: "%.2g×", speed))
                .font(.caption.weight(selected ? .bold : .medium).monospacedDigit())
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background {
                    if selected {
                        Capsule().fill(accent.opacity(0.35))
                        Capsule().strokeBorder(accent.opacity(0.6), lineWidth: 1)
                    } else {
                        Capsule().fill(.white.opacity(0.08))
                    }
                }
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: viewModel.session.info.speed)
    }

    private func nudgeSpeed(by delta: Double) {
        let next = min(4, max(0.25, viewModel.session.info.speed + delta))
        viewModel.session.setSpeed(next)
        viewModel.showOSD(String(format: "%.2g×", next))
        viewModel.scheduleHideControls()
    }
}

struct PlayerToolsMenu: View {
    @Bindable var viewModel: PlayerViewModel
    let accent: Color
    @State private var showSettings = false

    var body: some View {
        Menu {
            Button { viewModel.showPlaylist = true } label: {
                Label(KinemaCopy.lineup, systemImage: "list.bullet")
            }
            Button { viewModel.showSubtitles = true } label: {
                Label(KinemaCopy.captions, systemImage: "captions.bubble")
            }
            Divider()
            Button {
                viewModel.isMuted.toggle()
                viewModel.session.setMuted(viewModel.isMuted)
                viewModel.showOSD(viewModel.isMuted ? "Muted" : "Unmuted")
            } label: {
                Label(viewModel.isMuted ? "Unmute" : "Mute", systemImage: viewModel.isMuted ? "speaker.slash" : "speaker.wave.2")
            }
            #if os(macOS)
            Button { viewModel.toggleFullscreen() } label: {
                Label("Fullscreen", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            #endif
            Divider()
            Button { showSettings = true } label: {
                Label(KinemaCopy.preferences, systemImage: "gearshape")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .frame(width: 36, height: 36)
                .background(.white.opacity(0.08), in: Circle())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .sheet(isPresented: $showSettings) { SettingsView() }
        .onChange(of: showSettings) { _, isShowing in
            if isShowing {
                viewModel.cancelAutoHideControls()
            }
        }
    }
}

public struct OSDOverlay: View {
    let message: String?

    public init(message: String?) { self.message = message }

    public var body: some View {
        if let message {
            Text(message)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.55), radius: 4, y: 1)
                .transition(.opacity)
        }
    }
}
