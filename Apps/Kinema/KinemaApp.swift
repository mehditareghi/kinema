import SwiftUI
import SwiftData
import KinemaCore
import KinemaUI
import KinemaPlayback
import KinemaPlugins
import KinemaSharing

@main
struct KinemaApp: App {
    @State private var viewModel = PlayerViewModel()
    @Environment(\.openWindow) private var openWindow
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(viewModel)
                #if os(macOS)
                .macOSFileDrop(viewModel: viewModel)
                #endif
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
                .onAppear {
                    _ = SubtitleFontRegistry.prepare()
                    // Defer library I/O and Wi‑Fi so the first frame can paint.
                    Task { @MainActor in
                        LibraryRootStore.shared.prepareLibraryServices()
                        syncWiFiSharing()
                    }
                    Task { await PluginRegistry.shared.activateAll(for: viewModel.session) }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { @MainActor in
                            LibraryRootStore.shared.handleAppBecameActive()
                            WiFiSharingServer.shared.refreshAddress()
                        }
                    }
                }
        }
        .modelContainer(try! HistoryStore.container())
        #if os(macOS)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open File…") { openFilePanel() }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(after: .windowArrangement) {
                Button("Music Mode") {
                    openMusicMode()
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            }
        }
        #endif

        #if os(macOS)
        Window("Music Mode", id: "music-mode") {
            MusicModeView(viewModel: viewModel)
        }
        .defaultSize(width: 360, height: 280)
        #endif
    }

    private func handleIncomingURL(_ url: URL) {
        if let link = DeepLinkParser.parse(url) {
            handleDeepLink(link)
            return
        }

        // Avoid opening incomplete Finder/USB copies — that fights AFC and drops the link.
        if url.isFileURL,
           LibraryMediaPaths.isInsideBuiltInLibrary(url),
           !LibraryMediaPaths.isStableMediaFile(url) {
            return
        }

        Task {
            viewModel.session.grantFileAccess(to: url)
            await viewModel.open(url)
        }
    }

    private func handleDeepLink(_ link: KinemaDeepLink) {
        guard let mediaURL = link.mediaURL else { return }
        if link.newWindow {
            let session = PlayerSessionPool.createSession()
            Task {
                try? await session.load(MediaItem(url: mediaURL))
                session.play()
            }
            return
        }
        Task {
            viewModel.session.grantFileAccess(to: mediaURL)
            await viewModel.open(mediaURL)
        }
    }

    private func syncWiFiSharing() {
        let prefs = PreferencesStore.shared.preferences
        if prefs.wifiSharingEnabled {
            _ = WiFiSharingServer.shared.start(
                passcode: prefs.wifiSharingPasscode,
                preferIPv6: prefs.wifiSharingPreferIPv6
            )
        } else {
            WiFiSharingServer.shared.stop()
        }
    }

    #if os(macOS)
    private func openFilePanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie, .audio]
        if panel.runModal() == .OK {
            let items = panel.urls.map { MediaItem(url: $0) }
            Task { await viewModel.openItems(items) }
        }
    }

    private func openMusicMode() {
        openWindow(id: "music-mode")
    }
    #endif
}

#if os(macOS)
import AppKit
#endif
