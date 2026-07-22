import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import KinemaCore
import KinemaPlayback

/// Kinema shell — tabs on iPhone (compact), sidebar on iPad / Mac (regular).
public struct LibraryShellView: View {
    @Bindable var viewModel: PlayerViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var showFileImporter = false
    @State private var showSettings = false
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
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
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
                            ToolbarItem(placement: .topBarTrailing) {
                                Button {
                                    showSettings = true
                                } label: {
                                    Label(KinemaCopy.preferences, systemImage: "gearshape")
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
                    .navigationTitle(viewModel.librarySection.tabTitle)
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
        }
    }

    private var librarySidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                KinemaMark(size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(KinemaCopy.appName)
                        .font(.title3.weight(.bold))
                    Text(KinemaCopy.tagline)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)

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
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
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
        .background(KinemaTheme.sidebarBackground)
        .safeAreaInset(edge: .bottom) {
            sidebarButton(title: KinemaCopy.preferences, icon: "gearshape", isSelected: false) {
                showSettings = true
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
                    .font(.body.weight(.semibold))
                    .frame(width: 24)
                    .foregroundStyle(isSelected ? accent : .secondary)
                Text(title)
                    .font(.subheadline.weight(isSelected ? .semibold : .medium))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .foregroundStyle(isSelected ? .primary : .secondary)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? accent.opacity(0.14) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private var librarySourcesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(KinemaCopy.sources)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
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
                    .font(.body.weight(.semibold))
                    .frame(width: 24)
                    .foregroundStyle(isSelected ? accent : .secondary)
                Text(root.name)
                    .font(.subheadline.weight(isSelected ? .semibold : .medium))
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .foregroundStyle(isSelected ? .primary : .secondary)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? accent.opacity(0.14) : Color.clear)
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

#if os(macOS)
import AppKit
#endif

public struct OpenStreamView: View {
    @Bindable var viewModel: PlayerViewModel
    @State private var urlText = ""
    @FocusState private var focused: Bool

    private var accent: Color { KinemaTheme.accent }

    public init(viewModel: PlayerViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                KinemaSheetHero(
                    icon: "link",
                    title: KinemaCopy.openStreamTitle,
                    subtitle: KinemaCopy.openStreamHeroSubtitle
                )

                KinemaCard(title: KinemaCopy.openStreamFieldLabel, icon: "globe") {
                    TextField(KinemaCopy.openStreamPlaceholder, text: $urlText)
                        .textFieldStyle(.plain)
                        .font(.body.monospaced())
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .submitLabel(.go)
                        #endif
                        .focused($focused)
                        .onSubmit { openURL() }

                    Text(KinemaCopy.openStreamHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    openURL()
                } label: {
                    Label(KinemaCopy.openStreamPlay, systemImage: "play.fill")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .disabled(parsedURL == nil || viewModel.isOpeningMedia)
                .padding(.top, 4)
            }
            .padding(20)
        }
        .background(KinemaTheme.settingsBackground)
        .onAppear { focused = true }
    }

    private var parsedURL: URL? {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    private func openURL() {
        guard let url = parsedURL, !viewModel.isOpeningMedia else { return }
        Task { await viewModel.open(url) }
    }
}
