import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import KinemaCore
import KinemaPlayback
import KinemaMPV

public struct PlayerView: View {
    @Bindable var viewModel: PlayerViewModel
    @Bindable private var preferences = PreferencesStore.shared

    public init(viewModel: PlayerViewModel) {
        self.viewModel = viewModel
    }

    private var accent: Color { KinemaTheme.accent }

    public var body: some View {
        ZStack {
            KinemaTheme.playerBackground.ignoresSafeArea()

            #if os(iOS) || os(tvOS)
            if let surface = viewModel.session.renderSurface as? AVFoundationRenderSurface {
                MPVPlatformView(surface: surface)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
            }
            #elseif os(macOS)
            if let surface = viewModel.session.renderSurface as? MacOSRenderSurface {
                MPVPlatformView(surface: surface)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
            }
            #endif

            playerTapLayer

            #if os(iOS) || os(macOS)
            if viewModel.upNextOffer == nil {
                PlayerSideGestureOverlay(viewModel: viewModel, accent: accent)
                    .zIndex(2)
            }
            #endif

            if viewModel.showControls, viewModel.upNextOffer == nil {
                PlayerControlsOverlay(viewModel: viewModel, accent: accent)
                    .transition(.opacity)
                    .zIndex(1)
            }

            OSDOverlay(message: viewModel.osdMessage)
                .zIndex(3)

            if let offer = viewModel.upNextOffer {
                UpNextOverlay(
                    offer: offer,
                    accent: accent,
                    onPlayNow: { viewModel.confirmUpNext() },
                    onCancel: { viewModel.dismissUpNext() }
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .zIndex(5)
            }

            if preferences.preferences.audioVisualizationEnabled,
               viewModel.isInPlayer,
               viewModel.upNextOffer == nil {
                AudioVisualizationOverlay(
                    volume: viewModel.isMuted ? 0 : viewModel.session.info.volume,
                    isPaused: viewModel.session.info.isPaused,
                    isMuted: viewModel.isMuted
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, viewModel.showControls ? 120 : 36)
                .zIndex(2)
                .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: viewModel.showControls)
        .animation(.spring(response: 0.45, dampingFraction: 0.88), value: viewModel.upNextOffer?.id)
        .animation(.easeOut(duration: 0.2), value: preferences.preferences.audioVisualizationEnabled)
        .onChange(of: viewModel.isInPlayer) { _, _ in
            ScreenWakeLock.apply(
                playerVisible: viewModel.isInPlayer,
                state: viewModel.session.state
            )
        }
        .onChange(of: viewModel.session.state) { _, state in
            ScreenWakeLock.apply(
                playerVisible: viewModel.isInPlayer,
                state: state
            )
        }
        .onAppear {
            ScreenWakeLock.apply(
                playerVisible: viewModel.isInPlayer,
                state: viewModel.session.state
            )
            if viewModel.isInPlayer {
                viewModel.scheduleHideControls()
            }
        }
        .onDisappear {
            ScreenWakeLock.setPreventSleep(false)
        }
        .sheet(isPresented: $viewModel.showPlaylist) {
            PlaylistSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showSubtitles) {
            SubtitlePickerSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showAudio) {
            AudioSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showChapters) {
            ChaptersSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showSettings) {
            SettingsView()
        }
        .onChange(of: viewModel.showSettings) { _, isShowing in
            if isShowing {
                viewModel.cancelAutoHideControls()
            } else if viewModel.showControls {
                viewModel.scheduleHideControls()
            }
        }
        .onChange(of: viewModel.showAudio) { _, isShowing in
            if isShowing {
                viewModel.cancelAutoHideControls()
            } else if viewModel.showControls {
                viewModel.scheduleHideControls()
            }
        }
        .onChange(of: viewModel.showChapters) { _, isShowing in
            if isShowing {
                viewModel.cancelAutoHideControls()
            } else if viewModel.showControls {
                viewModel.scheduleHideControls()
            }
        }
        #if os(macOS)
        .onKeyPress { press in
            if viewModel.upNextOffer != nil {
                if press.key == .escape {
                    viewModel.dismissUpNext()
                    return .handled
                }
                if press.key == .return || press.characters == " " {
                    viewModel.confirmUpNext()
                    return .handled
                }
            }
            guard viewModel.handlesKey(press.characters) else { return .ignored }
            viewModel.handleKey(press.characters)
            return .handled
        }
        #endif
        .onChange(of: viewModel.upNextOffer?.id) { _, offerID in
            if offerID != nil {
                viewModel.cancelAutoHideControls()
                withAnimation(.easeOut(duration: 0.2)) {
                    viewModel.showControls = false
                }
            }
        }
        .onChange(of: viewModel.session.info.position) { _, position in
            viewModel.prefetchUpNextIfNeeded(position: position)
        }
    }

    @ViewBuilder
    private var playerTapLayer: some View {
        #if os(iOS) || os(tvOS)
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                guard viewModel.upNextOffer == nil else { return }
                viewModel.toggleControls()
            }
            .ignoresSafeArea()
            .allowsHitTesting(!viewModel.showControls && viewModel.upNextOffer == nil)
        #elseif os(macOS)
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                guard viewModel.upNextOffer == nil else { return }
                viewModel.toggleControls()
            }
            .ignoresSafeArea()
            .allowsHitTesting(!viewModel.showControls && viewModel.upNextOffer == nil)
        #endif
    }
}

public struct RootView: View {
    @Environment(PlayerViewModel.self) private var viewModel

    public init() {}

    public var body: some View {
        @Bindable var viewModel = viewModel

        #if os(tvOS)
        PlayerView(viewModel: viewModel)
        #else
        ZStack {
            // Keep the GLES / OpenGL surface out of the hierarchy until playback.
            // Mounting it under opacity 0 still lays it out and can burn CPU.
            if viewModel.isInPlayer {
                PlayerView(viewModel: viewModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            }

            LibraryShellView(viewModel: viewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(viewModel.isInPlayer ? 0 : 1)
                .allowsHitTesting(!viewModel.isInPlayer)
                .accessibilityHidden(viewModel.isInPlayer)
        }
        .animation(.easeInOut(duration: 0.28), value: viewModel.appMode)
        #if os(macOS)
        .onAppear { viewModel.prepare() }
        #endif
        #endif
    }
}

#if os(macOS)
import AppKit

public struct MusicModeView: View {
    @Bindable var viewModel: PlayerViewModel

    public init(viewModel: PlayerViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 20) {
            KinemaMark(size: 56)
            Text(viewModel.session.currentItem?.title ?? "No track")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            TransportBar(
                viewModel: viewModel,
                accent: KinemaTheme.accent
            )
        }
        .padding(24)
        .frame(width: 360, height: 300)
        .sheet(isPresented: $viewModel.showAudio) {
            AudioSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showSubtitles) {
            SubtitlePickerSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showPlaylist) {
            PlaylistSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showChapters) {
            ChaptersSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showSettings) {
            SettingsView()
        }
    }
}
#endif
