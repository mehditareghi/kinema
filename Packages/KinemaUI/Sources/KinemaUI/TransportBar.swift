import SwiftUI
import KinemaCore
import KinemaPlayback

#if os(macOS)
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
            ZStack {
                ChapterMarkerTrack(
                    chapters: viewModel.session.chapters,
                    duration: max(viewModel.session.info.duration, 1),
                    accent: accent
                )
                .frame(height: 4)
                .padding(.horizontal, 2)
                .allowsHitTesting(false)

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
            }

            HStack {
                Text(formatTime(viewModel.session.info.position))
                    .font(.caption2.monospacedDigit())
                Spacer()
                if let chapter = viewModel.session.currentChapter {
                    Text(chapter.displayTitle)
                        .font(.caption2.weight(.medium))
                        .lineLimit(1)
                }
                Spacer()
                Text(formatTime(viewModel.session.info.duration))
                    .font(.caption2.monospacedDigit())
            }
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
            PlaybackSpeedControl(viewModel: viewModel, accent: accent, style: .menu)
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

struct PlayerToolsMenu: View {
    @Bindable var viewModel: PlayerViewModel
    let accent: Color

    var body: some View {
        Menu {
            Button { viewModel.showPlaylist = true } label: {
                Label(KinemaCopy.lineup, systemImage: "list.bullet")
            }
            if viewModel.session.hasChapters {
                Button { viewModel.showChapters = true } label: {
                    Label(KinemaCopy.chapters, systemImage: "list.bullet.rectangle")
                }
            }
            Button { viewModel.showSubtitles = true } label: {
                Label(KinemaCopy.captions, systemImage: "captions.bubble")
            }
            Button { viewModel.showAudio = true } label: {
                Label(KinemaCopy.audio, systemImage: "slider.horizontal.3")
            }
            Divider()
            Button {
                viewModel.isMuted.toggle()
                viewModel.session.setMuted(viewModel.isMuted)
                viewModel.showOSD(viewModel.isMuted ? "Muted" : "Unmuted")
            } label: {
                Label(viewModel.isMuted ? "Unmute" : "Mute", systemImage: viewModel.isMuted ? "speaker.slash" : "speaker.wave.2")
            }
            Button { viewModel.toggleFullscreen() } label: {
                Label("Fullscreen", systemImage: "arrow.up.left.and.arrow.down.right")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .frame(width: 36, height: 36)
                .background(.white.opacity(0.08), in: Circle())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
#endif

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
