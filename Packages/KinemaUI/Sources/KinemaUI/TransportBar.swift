import SwiftUI
import KinemaCore
import KinemaPlayback

#if os(macOS)
public struct TransportBar: View {
    @Bindable var viewModel: PlayerViewModel
    let accent: Color
    @State private var scrubPosition: Double = 0
    @State private var isScrubbing = false
    @State private var scrubLoader = ScrubFrameLoader()

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

                ABLoopMarkerTrack(
                    pointA: viewModel.session.abLoopA,
                    pointB: viewModel.session.abLoopB,
                    duration: max(viewModel.session.info.duration, 1),
                    accent: accent
                )
                .frame(height: 28)
                .padding(.horizontal, 2)
                .allowsHitTesting(false)

                Slider(
                    value: $scrubPosition,
                    in: 0...max(viewModel.session.info.duration, 1)
                ) { editing in
                    isScrubbing = editing
                    if editing {
                        viewModel.cancelAutoHideControls()
                        scrubLoader.bind(
                            url: viewModel.session.scrubMediaURL,
                            duration: max(viewModel.session.info.duration, 1)
                        )
                        scrubLoader.request(time: scrubPosition)
                    } else {
                        viewModel.session.seek(to: scrubPosition)
                        viewModel.scheduleHideControls()
                        scrubLoader.endSession()
                    }
                }
                .tint(accent)
            }
            .overlay {
                GeometryReader { geo in
                    if isScrubbing {
                        let duration = max(viewModel.session.info.duration, 1)
                        let fraction = scrubPosition / duration
                        let thumbX = ScrubThumbGeometry.thumbCenterX(fraction: fraction, in: geo.size.width)
                        let bubbleX = ScrubThumbGeometry.bubbleCenterX(
                            thumbX: thumbX,
                            bubbleWidth: ScrubPreviewBubble.previewWidth,
                            in: geo.size.width
                        )
                        ScrubPreviewBubble(
                            image: scrubLoader.image,
                            time: scrubPosition,
                            accent: accent
                        )
                        .position(x: bubbleX, y: -58)
                        .allowsHitTesting(false)
                    }
                }
            }
            .onChange(of: scrubPosition) { _, value in
                if isScrubbing {
                    scrubLoader.request(time: value)
                }
            }
            .onChange(of: viewModel.session.scrubMediaURL) { _, url in
                scrubLoader.bind(
                    url: url,
                    duration: max(viewModel.session.info.duration, 1)
                )
            }
            .onAppear {
                scrubLoader.bind(
                    url: viewModel.session.scrubMediaURL,
                    duration: max(viewModel.session.info.duration, 1)
                )
            }

            HStack {
                Text(formatTime(isScrubbing ? scrubPosition : viewModel.session.info.position))
                    .font(KinemaType.timecodeSmall)
                Spacer()
                if viewModel.session.isABLooping {
                    Text(KinemaCopy.abLoop)
                        .font(KinemaType.microStrong)
                        .foregroundStyle(accent)
                } else if let chapter = viewModel.session.currentChapter {
                    Text(chapter.displayTitle)
                        .font(KinemaType.microMedium)
                        .lineLimit(1)
                }
                Spacer()
                Text(formatTime(viewModel.session.info.duration))
                    .font(KinemaType.timecodeSmall)
            }
            .foregroundStyle(.secondary)
        }
    }

    private var controlsRow: some View {
        HStack(spacing: 0) {
            transportButton("backward.end.fill", label: "Previous") {
                viewModel.session.playPrevious()
            }
            transportButton(
                PreferencesStore.shared.preferences.seekStep.backwardSystemImage,
                label: "Back \(PreferencesStore.shared.preferences.seekStep.displayName)"
            ) {
                viewModel.seekByConfiguredStep(forward: false)
            }

            Button {
                viewModel.session.togglePlayPause()
                viewModel.scheduleHideControls()
            } label: {
                Image(systemName: viewModel.session.info.isPaused ? "play.fill" : "pause.fill")
                    .font(KinemaType.title)
                    .frame(width: 52, height: 52)
                    .background(accent.opacity(0.22), in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.2), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 6)

            transportButton(
                PreferencesStore.shared.preferences.seekStep.forwardSystemImage,
                label: "Forward \(PreferencesStore.shared.preferences.seekStep.displayName)"
            ) {
                viewModel.seekByConfiguredStep(forward: true)
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
                .font(KinemaType.bodyStrong)
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
            Menu {
                ForEach(PlaylistPlaybackMode.allCases) { mode in
                    Button {
                        viewModel.showOSD(viewModel.session.setPlaylistMode(mode))
                    } label: {
                        if viewModel.session.playlistMode == mode {
                            Label(mode.displayName, systemImage: "checkmark")
                        } else {
                            Label(mode.displayName, systemImage: mode.systemImage)
                        }
                    }
                }
            } label: {
                Label(KinemaCopy.playlistMode, systemImage: viewModel.session.playlistMode.systemImage)
            }
            if viewModel.session.hasChapters {
                Button { viewModel.showChapters = true } label: {
                    Label(KinemaCopy.chapters, systemImage: "list.bullet.rectangle")
                }
            }
            Button {
                let message = viewModel.session.cycleABLoop()
                viewModel.showOSD(message)
            } label: {
                Label(
                    viewModel.session.isABLooping
                        ? "Clear A–B Loop"
                        : (viewModel.session.hasABLoopA ? "Set Loop B" : "Set Loop A"),
                    systemImage: viewModel.session.abLoopSystemImage
                )
            }
            Button { viewModel.showSubtitles = true } label: {
                Label(KinemaCopy.captions, systemImage: "captions.bubble")
            }
            Button { viewModel.showAudio = true } label: {
                Label(KinemaCopy.audio, systemImage: "slider.horizontal.3")
            }
            Button { viewModel.showVideoFilters = true } label: {
                Label(KinemaCopy.videoFilters, systemImage: "camera.filters")
            }
            Menu {
                ForEach(VideoFitMode.allCases) { mode in
                    Button {
                        viewModel.showOSD(viewModel.session.setVideoFitMode(mode))
                    } label: {
                        if viewModel.session.videoFitMode == mode {
                            Label(mode.displayName, systemImage: "checkmark")
                        } else {
                            Text(mode.displayName)
                        }
                    }
                }
                Divider()
                Button(KinemaCopy.pictureZoomIn) {
                    viewModel.showOSD(viewModel.session.adjustVideoZoom(by: 0.1))
                }
                Button(KinemaCopy.pictureZoomOut) {
                    viewModel.showOSD(viewModel.session.adjustVideoZoom(by: -0.1))
                }
                Button(KinemaCopy.pictureRotate) {
                    viewModel.showOSD(viewModel.session.rotateVideo90())
                }
                if viewModel.session.isVideoDisplayCustomized {
                    Button(KinemaCopy.pictureReset) {
                        viewModel.showOSD(viewModel.session.resetVideoDisplay())
                    }
                }
            } label: {
                Label(KinemaCopy.picture, systemImage: "aspectratio")
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
                .font(KinemaType.bodyStrong)
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
                .font(KinemaType.subtitle)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.55), radius: 4, y: 1)
                .transition(.opacity)
        }
    }
}
