import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import KinemaCore
import KinemaPlayback
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Kinema shell — tabs on iPhone (compact), sidebar on iPad / Mac (regular).
public struct LibraryShellView: View {
    @Bindable var viewModel: PlayerViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var showFileImporter = false
    @State private var showFolderPicker = false
    @State private var removeRootTarget: LibraryRoot?

    private var accent: Color { KinemaTheme.accent }
    private var browse: LibraryBrowseState { viewModel.libraryBrowse }
    private var rootStore: LibraryRootStore { browse.rootStore }

    private var usesTabBar: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    public init(viewModel: PlayerViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Group {
            #if os(iOS)
            if usesTabBar {
                tabShell
            } else {
                splitShell
            }
            #else
            splitShell
            #endif
        }
        .tint(accent)
        .font(KinemaType.body)
        .onAppear {
            viewModel.session.historyContext = modelContext
        }
        #if os(iOS) || os(macOS)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.movie, .video, .mpeg4Movie, .quickTimeMovie, .audio, .folder],
            allowsMultipleSelection: true
        ) { result in
            handleImportedFiles(result)
        }
        #endif
        #if os(iOS) || os(macOS)
        .fileImporter(
            isPresented: $showFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleFolderImport(result)
        }
        #endif
        .confirmationDialog(
            KinemaCopy.removeSourceTitle,
            isPresented: Binding(
                get: { removeRootTarget != nil },
                set: { if !$0 { removeRootTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(KinemaCopy.removeSource, role: .destructive) {
                commitRemoveRoot()
            }
            Button(KinemaCopy.cancel, role: .cancel) { removeRootTarget = nil }
        } message: {
            Text(KinemaCopy.removeSourceMessage)
        }
    }

    // MARK: - iPhone: tabs only

    #if os(iOS)
    private var tabShell: some View {
        TabView(selection: Binding(
            get: { viewModel.librarySection },
            set: { viewModel.librarySection = $0 }
        )) {
            ForEach(LibrarySection.tabCases) { section in
                NavigationStack {
                    detailContent(for: section)
                        .navigationTitle(section.tabTitle)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button {
                                    showFileImporter = true
                                } label: {
                                    Label(KinemaCopy.openFiles, systemImage: "doc.badge.plus")
                                }
                            }
                        }
                }
                .tabItem {
                    Label(section.tabTitle, systemImage: section.icon)
                }
                .tag(section)
            }
        }
    }
    #endif

    // MARK: - iPad / Mac: sidebar only

    private var splitShell: some View {
        NavigationSplitView {
            librarySidebar
        } detail: {
            NavigationStack {
                detailContent(for: viewModel.librarySection)
            }
        }
    }

    @ViewBuilder
    private func detailContent(for section: LibrarySection) -> some View {
        switch section {
        case .collection:
            LibraryBrowserView(viewModel: viewModel)
        case .continueWatching:
            RecentLibraryView(viewModel: viewModel)
        case .stream:
            OpenStreamView(viewModel: viewModel)
        case .preferences:
            SettingsView(isStandalone: false)
        }
    }

    private var librarySidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            KinemaBrandHeader()
            .padding(.horizontal, 18)
            .padding(.top, 22)

            VStack(spacing: 8) {
                ForEach(LibrarySection.primaryCases) { section in
                    sidebarButton(
                        title: section.rawValue,
                        icon: section.icon,
                        isSelected: viewModel.librarySection == section
                    ) {
                        viewModel.librarySection = section
                    }
                }
            }
            .padding(.horizontal, 12)

            librarySourcesSection

            VStack(alignment: .leading, spacing: 8) {
                Text(KinemaCopy.openSection)
                    .font(KinemaType.eyebrow)
                    .tracking(1.4)
                    .foregroundStyle(KinemaTheme.secondaryText)
                    .padding(.horizontal, 8)

                sidebarButton(title: KinemaCopy.openFiles, icon: "doc.badge.plus", isSelected: false) {
                    #if os(macOS)
                    openFilePanel()
                    #else
                    showFileImporter = true
                    #endif
                }

                sidebarButton(
                    title: KinemaCopy.openStream,
                    icon: "link",
                    isSelected: viewModel.librarySection == .stream
                ) {
                    viewModel.librarySection = .stream
                }
            }
            .padding(.horizontal, 12)

            #if os(macOS)
            if PreferencesStore.shared.preferences.musicModeEnabled {
                sidebarButton(title: "Music Mode", icon: "music.note.list", isSelected: false) {
                    openWindow(id: "music-mode")
                }
                .padding(.horizontal, 12)
            }
            #endif

            Spacer(minLength: 0)
        }
        .background {
            ZStack {
                KinemaTheme.sidebarBackground
                LinearGradient(
                    stops: [
                        .init(color: KinemaTheme.velvet.opacity(0.22), location: 0),
                        .init(color: KinemaTheme.velvet.opacity(0.06), location: 0.34),
                        .init(color: .clear, location: 0.72)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .ignoresSafeArea()
        }
        .safeAreaInset(edge: .bottom) {
            sidebarButton(
                title: KinemaCopy.preferences,
                icon: "slider.horizontal.3",
                isSelected: viewModel.librarySection == .preferences
            ) {
                viewModel.librarySection = .preferences
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
    }

    private func sidebarButton(
        title: String,
        icon: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(KinemaType.bodyStrong)
                    .frame(width: 24)
                    .foregroundStyle(isSelected ? accent : .secondary)
                Text(title)
                    .font(KinemaType.label.weight(isSelected ? .semibold : .medium))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .foregroundStyle(isSelected ? .primary : .secondary)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? accent.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private var librarySourcesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(KinemaCopy.sources)
                    .font(KinemaType.eyebrow)
                    .tracking(1.4)
                    .foregroundStyle(KinemaTheme.secondaryText)
                Spacer()
                Button {
                    showFolderPicker = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(KinemaCopy.addSource)
            }
            .padding(.horizontal, 8)

            sidebarButton(
                title: KinemaCopy.allSources,
                icon: "square.grid.2x2.fill",
                isSelected: browse.isAtLibraryHome && viewModel.librarySection == .collection
            ) {
                viewModel.librarySection = .collection
                browse.goToLibraryHome()
            }

            ForEach(rootStore.roots) { root in
                sidebarRootButton(root)
            }
        }
        .padding(.horizontal, 12)
    }

    private func sidebarRootButton(_ root: LibraryRoot) -> some View {
        let isSelected = browse.selectedRootID == root.id && viewModel.librarySection == .collection
        return Button {
            viewModel.librarySection = .collection
            browse.openRoot(root)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "externaldrive.fill")
                    .font(KinemaType.bodyStrong)
                    .frame(width: 24)
                    .foregroundStyle(isSelected ? accent : .secondary)
                Text(root.name)
                    .font(KinemaType.label.weight(isSelected ? .semibold : .medium))
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .foregroundStyle(isSelected ? .primary : .secondary)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? accent.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                browse.openRoot(root)
            } label: {
                Label(KinemaCopy.open, systemImage: "folder")
            }

            Button(role: .destructive) {
                removeRootTarget = root
            } label: {
                Label(KinemaCopy.removeSource, systemImage: "folder.badge.minus")
            }
        }
    }

    #if os(iOS) || os(macOS)
    private func handleFolderImport(_ result: Result<[URL], Error>) {
        if case .success(let urls) = result, let folder = urls.first {
            _ = folder.startAccessingSecurityScopedResource()
            if let root = rootStore.addRoot(from: folder) {
                viewModel.librarySection = .collection
                browse.openRoot(root)
            }
        }
    }

    private func commitRemoveRoot() {
        guard let root = removeRootTarget else { return }
        if browse.selectedRootID == root.id {
            browse.goToLibraryHome()
        }
        rootStore.removeRoot(id: root.id)
        removeRootTarget = nil
    }

    private func handleImportedFiles(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            let mediaItems = urls.compactMap { url -> MediaItem? in
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { return nil }
                return MediaItem(url: url)
            }
            for url in urls { viewModel.session.grantFileAccess(to: url) }
            guard !mediaItems.isEmpty else { return }
            Task { await viewModel.openItems(mediaItems) }
        case .failure(let error):
            viewModel.showOSD("Could not open file: \(error.localizedDescription)")
        }
    }
    #endif

    #if os(macOS)
    private func openFilePanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie, .audio]
        if panel.runModal() == .OK {
            let items = panel.urls.compactMap { url -> MediaItem? in
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                guard !isDir.boolValue else { return nil }
                return MediaItem(url: url)
            }
            guard !items.isEmpty else { return }
            Task { await viewModel.openItems(items) }
        }
    }
    #endif
}

public struct OpenStreamView: View {
    @Bindable var viewModel: PlayerViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var urlText = ""
    @State private var recentStreams: [WatchProgressEntry] = []
    @FocusState private var focused: Bool

    private var accent: Color { KinemaTheme.accent }

    public init(viewModel: PlayerViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ZStack {
            KinemaBackdrop()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    streamHero
                    streamComposer

                    if !recentStreams.isEmpty {
                        recentStreamsSection
                    }
                }
                .padding(.horizontal, pageHorizontalPadding)
                .padding(.top, 18)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(iOS)
        .toolbarBackground(.hidden, for: .navigationBar)
        #endif
        .onAppear {
            reloadRecentStreams()
            focused = urlText.isEmpty
        }
        .onChange(of: viewModel.isInPlayer) { wasInPlayer, isInPlayer in
            if wasInPlayer && !isInPlayer {
                reloadRecentStreams()
            }
        }
    }

    private var streamHero: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("A SCREENING FROM ANYWHERE")
                .font(KinemaType.eyebrow)
                .tracking(2.2)
                .foregroundStyle(KinemaTheme.brass)
            Text(KinemaCopy.openStreamTitle)
                .font(KinemaType.pageTitle)
                .foregroundStyle(KinemaTheme.paper)
            Text(KinemaCopy.openStreamHeroSubtitle)
                .font(KinemaType.label)
                .foregroundStyle(KinemaTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 620, alignment: .leading)
        }
        .padding(.vertical, 12)
    }

    private var streamComposer: some View {
        KinemaCard(title: KinemaCopy.openStreamFieldLabel, icon: "link") {
            HStack(spacing: 10) {
                Image(systemName: "link")
                    .font(KinemaType.bodyStrong)
                    .foregroundStyle(parsedURL == nil ? KinemaTheme.secondaryText : accent)

                TextField(KinemaCopy.openStreamPlaceholder, text: $urlText)
                    .textFieldStyle(.plain)
                    .font(KinemaType.code)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.go)
                    #endif
                    .focused($focused)
                    .onSubmit { openURL() }

                if !urlText.isEmpty {
                    Button {
                        urlText = ""
                        focused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(KinemaTheme.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear address")
                }

                Button(action: pasteAddress) {
                    Label("Paste", systemImage: "doc.on.clipboard")
                        .font(KinemaType.labelStrong)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 54)
            .background(KinemaTheme.raisedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        focused ? accent.opacity(0.72) : KinemaTheme.hairline.opacity(0.82),
                        lineWidth: focused ? 1.4 : 0.6
                    )
            }
            .animation(.easeOut(duration: 0.16), value: focused)

            streamAddressStatus

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { streamActions }
                VStack(spacing: 10) { streamActions }
            }

            HStack(spacing: 8) {
                protocolChip("HTTPS")
                protocolChip("HLS")
                protocolChip("RTSP")
                protocolChip("RTMP")
                protocolChip("KINEMA")
            }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var streamActions: some View {
        Button(action: openURL) {
            HStack(spacing: 9) {
                if viewModel.isOpeningMedia {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "play.fill")
                }
                Text(viewModel.isOpeningMedia ? "Opening…" : KinemaCopy.openStreamPlay)
            }
            .font(KinemaType.control)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
        }
        .buttonStyle(.borderedProminent)
        .tint(accent)
        .disabled(parsedURL == nil || viewModel.isOpeningMedia)

        Button(action: downloadURL) {
            Label(KinemaCopy.downloadToLibrary, systemImage: "arrow.down.circle")
                .font(KinemaType.control)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
        }
        .buttonStyle(.bordered)
        .tint(accent)
        .disabled(!canDownload)
        .help(canDownload ? "Download this address into Kinema" : "Downloads require an HTTP or HTTPS address")
    }

    @ViewBuilder
    private var streamAddressStatus: some View {
        if urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Label(KinemaCopy.openStreamHint, systemImage: "info.circle")
                .font(KinemaType.metadata)
                .foregroundStyle(KinemaTheme.secondaryText)
        } else if let url = parsedURL {
            HStack(spacing: 7) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(accent)
                Text(url.scheme?.uppercased() ?? "LINK")
                    .font(KinemaType.microBold)
                    .foregroundStyle(accent)
                Text(url.host ?? url.absoluteString)
                    .font(KinemaType.metadata)
                    .lineLimit(1)
                    .foregroundStyle(KinemaTheme.secondaryText)
            }
        } else {
            Label("Enter a complete address including its protocol.", systemImage: "exclamationmark.triangle.fill")
                .font(KinemaType.metadata)
                .foregroundStyle(accent)
        }
    }

    private func protocolChip(_ title: String) -> some View {
        Text(title)
            .font(KinemaType.microStrong)
            .foregroundStyle(KinemaTheme.secondaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(KinemaTheme.raisedBackground.opacity(0.72), in: Capsule())
    }

    private var recentStreamsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            KinemaSectionTitle("Recent Streams", systemImage: "clock.arrow.circlepath")

            LazyVGrid(columns: recentColumns, alignment: .leading, spacing: 12) {
                ForEach(recentStreams) { entry in
                    Button {
                        guard let url = entry.url else { return }
                        urlText = url.absoluteString
                        focused = false
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "play.rectangle.fill")
                                .font(KinemaType.bodyStrong)
                                .foregroundStyle(accent)
                                .frame(width: 40, height: 40)
                                .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.title)
                                    .font(KinemaType.posterTitle)
                                    .foregroundStyle(KinemaTheme.paper)
                                    .lineLimit(1)
                                HStack(spacing: 5) {
                                    Text(entry.url?.host ?? entry.url?.scheme?.uppercased() ?? "Stream")
                                    Text("·")
                                    Text(entry.lastPlayedAt, style: .relative)
                                }
                                .font(KinemaType.metadata)
                                .foregroundStyle(KinemaTheme.secondaryText)
                                .lineLimit(1)
                            }

                            Spacer(minLength: 6)
                            Image(systemName: "arrow.up.left")
                                .font(KinemaType.metadataStrong)
                                .foregroundStyle(KinemaTheme.secondaryText)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(KinemaTheme.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(KinemaTheme.hairline.opacity(0.78), lineWidth: 0.6)
                        }
                        .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var pageHorizontalPadding: CGFloat {
        horizontalSizeClass == .compact ? 18 : 28
    }

    private var recentColumns: [GridItem] {
        if horizontalSizeClass == .compact {
            return [GridItem(.flexible(), spacing: 12)]
        }
        return [GridItem(.adaptive(minimum: 300, maximum: 520), spacing: 12)]
    }

    private var parsedURL: URL? {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let candidate: String
        if trimmed.contains("://") || trimmed.lowercased().hasPrefix("kinema:") {
            candidate = trimmed
        } else if trimmed.contains(".") && !trimmed.contains(" ") {
            candidate = "https://\(trimmed)"
        } else {
            return nil
        }

        guard let url = URL(string: candidate), let scheme = url.scheme, scheme.lowercased() != "file" else {
            return nil
        }
        return url
    }

    private var canDownload: Bool {
        guard let scheme = parsedURL?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    private func openURL() {
        guard let url = parsedURL, !viewModel.isOpeningMedia else { return }
        Task { await viewModel.open(url) }
    }

    private func downloadURL() {
        guard let url = parsedURL, canDownload else { return }
        _ = LibraryDownloadService.shared.enqueue(url: url)
        viewModel.showOSD(KinemaCopy.downloadStarted)
    }

    private func pasteAddress() {
        #if os(iOS)
        guard let value = UIPasteboard.general.string else { return }
        #elseif os(macOS)
        guard let value = NSPasteboard.general.string(forType: .string) else { return }
        #else
        return
        #endif
        urlText = value.trimmingCharacters(in: .whitespacesAndNewlines)
        focused = false
    }

    private func reloadRecentStreams() {
        recentStreams = WatchProgressStore.recentEntries(limit: 40)
            .filter { entry in
                guard let url = entry.url else { return false }
                return !url.isFileURL
            }
            .prefix(6)
            .map { $0 }
    }
}
