import SwiftUI
import UniformTypeIdentifiers
import KinemaCore
import KinemaMedia
import KinemaPlayback

public struct LibraryBrowserView: View {
    @Bindable var viewModel: PlayerViewModel
    @Bindable private var browse: LibraryBrowseState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var items: [LibraryItem] = []
    @State private var organizedContent: SeriesBrowseContent = .empty
    @State private var showFolderPicker = false
    @State private var removeRootTarget: LibraryRoot?
    @State private var renameTarget: LibraryItem?
    @State private var renameRootTarget: LibraryRoot?
    @State private var renameText = ""
    @State private var deleteTarget: LibraryItem?
    @State private var infoTitle = ""
    @State private var infoMessage = ""
    @State private var showInfo = false
    @State private var fullyWatchedFolderPaths: Set<String> = []
    @State private var progressToken: UUID?
    @State private var searchText = ""
    @State private var showNewFolderAlert = false
    @State private var newFolderName = ""
    @State private var isReloading = false
    @State private var pendingReloadTask: Task<Void, Never>?
    @State private var listingTask: Task<Void, Never>?
    @State private var listingGeneration = 0
    /// Path of the directory whose listing currently backs `items` (nil = not listed yet).
    @State private var listedDirectoryPath: String?

    private var accent: Color { KinemaTheme.accent }
    private var rootStore: LibraryRootStore { browse.rootStore }

    private var realFolders: [LibraryItem] {
        guard browse.virtualPath.isEmpty else { return [] }
        return filterBySearch(items.filter(\.isDirectory))
    }

    private var virtualFolders: [VirtualSeriesFolder] {
        let folders = organizedContent.virtualFolders
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return folders }
        return folders.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    /// Real folders and spotlight folders in one A→Z list.
    private var sortedFolderRows: [BrowseFolderRow] {
        var rows: [BrowseFolderRow] = []
        rows.append(contentsOf: realFolders.map { .real($0) })
        rows.append(contentsOf: virtualFolders.map { .virtual($0) })
        return rows.sorted {
            $0.sortName.localizedStandardCompare($1.sortName) == .orderedAscending
        }
    }

    private var displayedVideos: [LibraryItem] {
        let lookup = Dictionary(uniqueKeysWithValues: items.filter { !$0.isDirectory }.map { ($0.url, $0) })
        let videos = organizedContent.videoURLs.compactMap { lookup[$0] }
        return filterBySearch(videos)
    }

    private var hasVisibleContent: Bool {
        if browse.isAtLibraryHome {
            return !rootStore.roots.isEmpty
        }
        return !realFolders.isEmpty || !virtualFolders.isEmpty || !displayedVideos.isEmpty
    }

    /// True once we've finished listing the directory currently on screen.
    private var hasListedCurrentDirectory: Bool {
        guard let directory = browse.currentDirectory else { return false }
        return listedDirectoryPath == directory.standardizedFileURL.path
    }

    private var isBuiltInLibraryRoot: Bool {
        browse.selectedRoot?.isBuiltIn == true
            && browse.folderTrail.isEmpty
            && browse.virtualPath.isEmpty
    }

    @ViewBuilder
    private var emptyFolderContent: some View {
        if isBuiltInLibraryRoot {
            ContentUnavailableView {
                Label(KinemaCopy.builtInEmptyTitle, systemImage: "film.stack.fill")
            } description: {
                Text(KinemaCopy.builtInEmptyMessage)
            } actions: {
                Button {
                    newFolderName = ""
                    showNewFolderAlert = true
                } label: {
                    Label(KinemaCopy.newFolder, systemImage: "plus.rectangle.on.folder")
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if browse.virtualPath.isEmpty {
            ContentUnavailableView(
                KinemaCopy.nothingHereTitle,
                systemImage: "folder",
                description: Text(KinemaCopy.nothingHereMessage)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView(
                KinemaCopy.nothingInSpotlightTitle,
                systemImage: "rectangle.stack",
                description: Text(KinemaCopy.nothingInSpotlightMessage)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    public init(viewModel: PlayerViewModel) {
        self.viewModel = viewModel
        self._browse = Bindable(wrappedValue: viewModel.libraryBrowse)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            breadcrumbBar
            Divider()

            if browse.isAtLibraryHome {
                libraryHomeContent
            } else if hasVisibleContent {
                folderContents
            } else if hasListedCurrentDirectory {
                emptyFolderContent
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .searchable(text: $searchText, prompt: KinemaCopy.searchLibrary)
        .onAppear {
            reloadIfNeeded()
            progressToken = EventBus.shared.subscribe { event in
                switch event {
                case .watchProgressUpdated, .libraryChanged:
                    Task { @MainActor in scheduleReload() }
                default:
                    break
                }
            }
        }
        .onDisappear {
            pendingReloadTask?.cancel()
            pendingReloadTask = nil
            listingTask?.cancel()
            listingTask = nil
            if let progressToken {
                EventBus.shared.unsubscribe(progressToken)
            }
        }
        .onChange(of: viewModel.isInPlayer) { wasInPlayer, isInPlayer in
            if wasInPlayer && !isInPlayer {
                reloadIfNeeded()
            }
        }
        .onChange(of: browse.selectedRootID) { _, _ in
            // Navigation must reload immediately — debouncing flashes the empty state.
            reloadIfNeeded()
        }
        .onChange(of: browse.currentDirectory) { _, _ in
            reloadIfNeeded()
        }
        .onChange(of: browse.virtualPath) { _, _ in
            recomputeOrganizedContent()
            ThumbnailPrefetcher.schedule(Array(displayedVideos.prefix(48).map(\.url)))
            refreshWatchedBadgesAfterListing()
        }
        .alert(KinemaCopy.rename, isPresented: Binding(
            get: { renameTarget != nil || renameRootTarget != nil },
            set: { if !$0 { renameTarget = nil; renameRootTarget = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button(KinemaCopy.cancel, role: .cancel) {
                renameTarget = nil
                renameRootTarget = nil
            }
            Button(KinemaCopy.rename) { commitRename() }
        } message: {
            Text(KinemaCopy.renamePrompt)
        }
        .alert(KinemaCopy.newFolder, isPresented: $showNewFolderAlert) {
            TextField("Name", text: $newFolderName)
            Button(KinemaCopy.cancel, role: .cancel) { newFolderName = "" }
            Button(KinemaCopy.newFolder) { commitNewFolder() }
        } message: {
            Text(KinemaCopy.newFolderPrompt)
        }
        .confirmationDialog(
            KinemaCopy.removeSourceTitle,
            isPresented: Binding(
                get: { removeRootTarget != nil },
                set: { if !$0 { removeRootTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(KinemaCopy.removeSource, role: .destructive) { commitRemoveRoot() }
            Button(KinemaCopy.cancel, role: .cancel) { removeRootTarget = nil }
        } message: {
            Text(KinemaCopy.removeSourceMessage)
        }
        .confirmationDialog(
            KinemaCopy.deleteFileTitle,
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(KinemaCopy.delete, role: .destructive) { commitDelete() }
            Button(KinemaCopy.cancel, role: .cancel) { deleteTarget = nil }
        } message: {
            Text(KinemaCopy.deleteFileMessage)
        }
        .alert(infoTitle, isPresented: $showInfo) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(infoMessage)
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
    }

    private var libraryHomeContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                homeHeader
                libraryRootsSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    private var homeHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(KinemaCopy.collectionIntroTitle)
                .font(.title3.weight(.bold))
            Text(KinemaCopy.collectionIntroBody)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var libraryRootsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(KinemaCopy.sources, systemImage: "externaldrive.fill")

            VStack(spacing: 8) {
                ForEach(rootStore.roots) { root in
                    Button {
                        browse.openRoot(root)
                    } label: {
                        if root.isBuiltIn {
                            BuiltInLibrarySourceTile(
                                accent: accent,
                                isFullyWatched: isFolderFullyWatched(rootURL(for: root))
                            )
                        } else {
                            MediaFolderTile(
                                name: root.name,
                                accent: accent,
                                systemImage: "externaldrive.fill",
                                subtitle: rootSubtitle(for: root),
                                isFullyWatched: isFolderFullyWatched(rootURL(for: root))
                            )
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        rootContextMenu(for: root)
                    }
                }

                Button {
                    showFolderPicker = true
                } label: {
                    AddLibraryFolderTile(accent: accent)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var folderContents: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !sortedFolderRows.isEmpty {
                    foldersSection
                }
                if !displayedVideos.isEmpty {
                    videosSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    private var foldersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(sectionFoldersTitle, systemImage: "folder")

            VStack(spacing: 8) {
                ForEach(sortedFolderRows) { row in
                    switch row {
                    case .real(let item):
                        Button { open(item) } label: {
                            MediaFolderTile(
                                name: item.url.lastPathComponent,
                                accent: accent,
                                isFullyWatched: isFolderFullyWatched(item.url)
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            folderContextMenu(for: item)
                        }

                    case .virtual(let folder):
                        Button { browse.openVirtual(folder.segment) } label: {
                            MediaFolderTile(
                                name: folder.title,
                                accent: accent,
                                systemImage: "rectangle.stack.fill",
                                subtitle: KinemaCopy.spotlightBadge,
                                isFullyWatched: isVirtualFolderFullyWatched(folder)
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                playFolderURLs(folder.videoURLs)
                            } label: {
                                Label(KinemaCopy.playFolder, systemImage: "play.fill")
                            }

                            if !folder.videoURLs.isEmpty {
                                if WatchProgressStore.areAllWatched(folder.videoURLs) {
                                    Button {
                                        markAllUnwatched(folder.videoURLs)
                                    } label: {
                                        Label(KinemaCopy.markAllUnwatched, systemImage: "arrow.uturn.backward.circle")
                                    }
                                } else {
                                    Button {
                                        markAllWatched(folder.videoURLs)
                                    } label: {
                                        Label(KinemaCopy.markAllWatched, systemImage: "checkmark.circle")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var sectionFoldersTitle: String {
        if realFolders.isEmpty {
            return KinemaCopy.spotlights
        }
        if virtualFolders.isEmpty {
            return KinemaCopy.folders
        }
        return KinemaCopy.foldersAndSpotlights
    }

    private var videosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(KinemaCopy.titles, systemImage: "film")

            LazyVGrid(
                columns: MediaLibraryLayout.posterColumns(horizontalSizeClass: horizontalSizeClass),
                spacing: MediaLibraryLayout.gridSpacing(horizontalSizeClass: horizontalSizeClass)
            ) {
                ForEach(displayedVideos) { item in
                    Button { open(item) } label: {
                        MediaPosterCard(
                            url: item.url,
                            title: item.url.deletingPathExtension().lastPathComponent,
                            progress: item.progress,
                            accent: accent
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        videoContextMenu(for: item)
                    }
                }
            }
        }
    }

    private var breadcrumbBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    showFolderPicker = true
                } label: {
                    Label(KinemaCopy.addSource, systemImage: "folder.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)

                if !browse.isAtLibraryHome, browse.virtualPath.isEmpty {
                    Button {
                        newFolderName = ""
                        showNewFolderAlert = true
                    } label: {
                        Label(KinemaCopy.newFolder, systemImage: "plus.rectangle.on.folder")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.bordered)
                    .tint(accent)
                }

                Button {
                    forceRescan()
                } label: {
                    Label(KinemaCopy.rescan, systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .tint(accent)

                Button {
                    browse.goUp()
                } label: {
                    Label("Up", systemImage: "arrow.up")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .tint(accent)
                .disabled(!browse.canGoUp)

                if !browse.isAtLibraryHome {
                    Button {
                        browse.goToLibraryHome()
                    } label: {
                        Label(KinemaCopy.backToCollection, systemImage: "square.grid.2x2")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.bordered)
                    .tint(accent)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(browse.breadcrumbs) { crumb in
                        if crumb.id != browse.breadcrumbs.first?.id {
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }

                        breadcrumbButton(crumb: crumb)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
            }
            .background(KinemaTheme.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(KinemaTheme.settingsBackground)
    }

    private func breadcrumbButton(crumb: BrowseBreadcrumb) -> some View {
        Button {
            browse.navigateToBreadcrumb(crumb)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: crumb.systemImage)
                    .foregroundStyle(crumb.isCurrent ? accent : .secondary)
                Text(crumb.title)
                    .font(.subheadline.weight(crumb.isCurrent ? .semibold : .medium))
                    .foregroundStyle(crumb.isCurrent ? .primary : .secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, crumb.isCurrent ? 8 : 0)
            .padding(.vertical, crumb.isCurrent ? 4 : 0)
            .background {
                if crumb.isCurrent {
                    Capsule().fill(accent.opacity(0.12))
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(crumb.isCurrent)
    }

    @ViewBuilder
    private func rootContextMenu(for root: LibraryRoot) -> some View {
        Button {
            browse.openRoot(root)
        } label: {
            Label(KinemaCopy.open, systemImage: "folder")
        }

        if root.isBuiltIn {
            #if os(macOS)
            Button {
                revealInFinder(root)
            } label: {
                Label(KinemaCopy.revealInFinder, systemImage: "finder")
            }
            #endif
        } else {
            Button {
                renameRootTarget = root
                renameText = root.name
            } label: {
                Label(KinemaCopy.rename, systemImage: "pencil")
            }

            Button(role: .destructive) {
                removeRootTarget = root
            } label: {
                Label(KinemaCopy.removeSource, systemImage: "folder.badge.minus")
            }
        }
    }

    @ViewBuilder
    private func folderContextMenu(for item: LibraryItem) -> some View {
        Button {
            open(item)
        } label: {
            Label("Open", systemImage: "folder")
        }

        Button {
            playFolderURLs(WatchProgressStore.mediaURLs(under: item.url))
        } label: {
            Label(KinemaCopy.playFolder, systemImage: "play.fill")
        }

        let folderVideos = WatchProgressStore.mediaURLs(under: item.url)
        if !folderVideos.isEmpty {
            if WatchProgressStore.areAllWatched(folderVideos) {
                Button {
                    markAllUnwatched(folderVideos)
                } label: {
                    Label(KinemaCopy.markAllUnwatched, systemImage: "arrow.uturn.backward.circle")
                }
            } else {
                Button {
                    markAllWatched(folderVideos)
                } label: {
                    Label(KinemaCopy.markAllWatched, systemImage: "checkmark.circle")
                }
            }
        }

        Button {
            beginRename(item)
        } label: {
            Label("Rename", systemImage: "pencil")
        }

        Button {
            showInfo(for: item)
        } label: {
            Label("Information", systemImage: "info.circle")
        }

        Button(role: .destructive) {
            deleteTarget = item
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    @ViewBuilder
    private func videoContextMenu(for item: LibraryItem) -> some View {
        Button {
            playFrom(item, audioOnly: false)
        } label: {
            Label("Play", systemImage: "play.fill")
        }

        Button {
            viewModel.playNext(MediaItem(url: item.url))
        } label: {
            Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
        }

        Button {
            viewModel.appendToQueue(MediaItem(url: item.url))
        } label: {
            Label("Append to Queue", systemImage: "text.badge.plus")
        }

        Button {
            playFrom(item, audioOnly: true)
        } label: {
            Label("Play as Audio", systemImage: "speaker.wave.2")
        }

        Divider()

        if item.progress?.isMostlyFinished == true {
            Button {
                markUnwatched(item)
            } label: {
                Label(KinemaCopy.markUnwatched, systemImage: "arrow.uturn.backward.circle")
            }
        } else {
            Button {
                markWatched(item)
            } label: {
                Label(KinemaCopy.markWatched, systemImage: "checkmark.circle")
            }
        }

        ShareLink(item: item.url) {
            Label("Share", systemImage: "square.and.arrow.up")
        }

        Button {
            beginRename(item)
        } label: {
            Label("Rename", systemImage: "pencil")
        }

        Button {
            showInfo(for: item)
        } label: {
            Label("Information", systemImage: "info.circle")
        }

        Button(role: .destructive) {
            deleteTarget = item
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private func rootSubtitle(for root: LibraryRoot) -> String {
        if root.isBuiltIn {
            return KinemaCopy.builtInSourceSubtitle
        }
        if let path = root.path {
            let url = URL(fileURLWithPath: path)
            let parent = url.deletingLastPathComponent().path
            if parent.isEmpty || parent == "/" {
                return path
            }
            return parent
        }
        return KinemaCopy.savedSource
    }

    private func rootURL(for root: LibraryRoot) -> URL? {
        rootStore.resolveURL(for: root)
    }

    private func isFolderFullyWatched(_ url: URL?) -> Bool {
        guard let url else { return false }
        return fullyWatchedFolderPaths.contains(url.standardizedFileURL.path)
    }

    private func isVirtualFolderFullyWatched(_ folder: VirtualSeriesFolder) -> Bool {
        fullyWatchedFolderPaths.contains(Self.virtualWatchedKey(folder.id))
    }

    private static func virtualWatchedKey(_ folderID: String) -> String {
        "virtual:\(folderID)"
    }

    private func filterBySearch(_ values: [LibraryItem]) -> [LibraryItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return values }
        return values.filter {
            $0.url.lastPathComponent.localizedCaseInsensitiveContains(query)
                || $0.url.deletingPathExtension().lastPathComponent.localizedCaseInsensitiveContains(query)
        }
    }

    private func forceRescan() {
        isReloading = false
        pendingReloadTask?.cancel()
        pendingReloadTask = nil
        listingTask?.cancel()
        listingTask = nil
        LibraryDirectoryWatcher.shared.suppressEvents(for: 1.0)
        reloadIfNeeded()
        #if os(iOS) || os(macOS)
        Task(priority: .utility) {
            LibrarySpotlightIndexer.shared.indexBuiltInLibrary()
        }
        #endif
        viewModel.showOSD(KinemaCopy.rescan)
    }

    private func scheduleReload() {
        pendingReloadTask?.cancel()
        pendingReloadTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            reloadIfNeeded()
        }
    }

    private func reloadIfNeeded() {
        if browse.isAtLibraryHome {
            listingTask?.cancel()
            listedDirectoryPath = nil
            if !items.isEmpty {
                items = []
            }
            if !organizedContent.virtualFolders.isEmpty || !organizedContent.videoURLs.isEmpty {
                organizedContent = .empty
            }
            if !fullyWatchedFolderPaths.isEmpty {
                fullyWatchedFolderPaths = []
            }
            return
        }
        guard let directory = browse.currentDirectory ?? browse.libraryRootURL else {
            listingTask?.cancel()
            listedDirectoryPath = nil
            if !items.isEmpty { items = [] }
            if !organizedContent.virtualFolders.isEmpty || !organizedContent.videoURLs.isEmpty {
                organizedContent = .empty
            }
            if !fullyWatchedFolderPaths.isEmpty { fullyWatchedFolderPaths = [] }
            return
        }
        let path = directory.standardizedFileURL.path
        if listedDirectoryPath != path {
            listedDirectoryPath = nil
        }
        reload(directory: directory)
    }

    private func reload(directory: URL) {
        listingTask?.cancel()
        listingGeneration += 1
        let generation = listingGeneration
        let path = directory.standardizedFileURL.path

        isReloading = true
        LibraryDirectoryWatcher.shared.suppressEvents(for: 1.0)

        listingTask = Task { @MainActor in
            let rawItems = await Task.detached(priority: .userInitiated) {
                Self.scanDirectory(directory)
            }.value

            guard !Task.isCancelled, generation == listingGeneration else { return }
            let stillHere = browse.currentDirectory?.standardizedFileURL.path == path
                || (browse.currentDirectory == nil && browse.libraryRootURL?.standardizedFileURL.path == path)
            guard stillHere else { return }

            let listed = rawItems.map { raw in
                LibraryItem(
                    url: raw.url,
                    isDirectory: raw.isDirectory,
                    progress: raw.isDirectory ? nil : WatchProgressStore.entry(for: raw.url)
                )
            }
            items = listed
            recomputeOrganizedContent()
            listedDirectoryPath = path
            isReloading = false

            ThumbnailPrefetcher.schedule(Array(displayedVideos.prefix(48).map(\.url)))
            refreshWatchedBadgesAfterListing(generation: generation)
        }
    }

    private func recomputeOrganizedContent() {
        organizedContent = MediaSeriesOrganizer.organize(
            videoURLs: items.filter { !$0.isDirectory }.map(\.url),
            virtualPath: browse.virtualPath
        )
    }

    private func refreshWatchedBadgesAfterListing(generation: Int? = nil) {
        let expectedGeneration = generation ?? listingGeneration
        let folderURLs = items.filter(\.isDirectory).map(\.url)
        let virtuals = organizedContent.virtualFolders.map { ($0.id, $0.videoURLs) }

        Task(priority: .utility) { @MainActor in
            let shallowVideos = await Task.detached(priority: .utility) {
                folderURLs.map { folder -> (String, [URL]) in
                    let videos = Self.shallowMediaURLs(in: folder)
                    return (folder.standardizedFileURL.path, videos)
                }
            }.value

            guard !Task.isCancelled, expectedGeneration == listingGeneration else { return }

            var watched = Set<String>()
            for (path, videos) in shallowVideos {
                if WatchProgressStore.areAllWatched(videos) {
                    watched.insert(path)
                }
            }
            for (folderID, videoURLs) in virtuals {
                if WatchProgressStore.areAllWatched(videoURLs) {
                    watched.insert(Self.virtualWatchedKey(folderID))
                }
            }
            fullyWatchedFolderPaths = watched
        }
    }

    private struct ScannedLibraryEntry: Sendable {
        let url: URL
        let isDirectory: Bool
    }

    /// Filesystem scan off the main actor — progress is attached afterward.
    private static func scanDirectory(_ directory: URL) -> [ScannedLibraryEntry] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .nameKey, .isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var entries: [ScannedLibraryEntry] = []
        entries.reserveCapacity(urls.count)

        for url in urls {
            if LibraryMediaPaths.isIgnoredName(url.lastPathComponent) { continue }
            let values = try? url.resourceValues(forKeys: [
                .isDirectoryKey, .isRegularFileKey, .fileSizeKey
            ])
            let isDirectory = values?.isDirectory ?? false
            if isDirectory {
                entries.append(ScannedLibraryEntry(url: url, isDirectory: true))
                continue
            }
            guard MediaFileTypes.isMediaFile(url) else { continue }
            guard values?.isRegularFile == true,
                  let size = values?.fileSize,
                  size >= 4_096 else { continue }
            let lower = url.lastPathComponent.lowercased()
            if LibraryMediaPaths.incompleteNameSuffixes.contains(where: { lower.hasSuffix($0) }) {
                continue
            }
            entries.append(ScannedLibraryEntry(url: url, isDirectory: false))
        }

        entries.sort { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory && !rhs.isDirectory }
            return lhs.url.lastPathComponent.localizedStandardCompare(rhs.url.lastPathComponent) == .orderedAscending
        }
        return entries
    }

    private static func shallowMediaURLs(in folder: URL) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls.filter { MediaFileTypes.isMediaFile($0) }
    }

    private func open(_ item: LibraryItem) {
        if item.isDirectory {
            browse.openFolder(item.url)
            return
        }
        guard !viewModel.isOpeningMedia else { return }
        playFrom(item, audioOnly: false)
    }

    private func playFrom(_ item: LibraryItem, audioOnly: Bool) {
        guard !item.isDirectory, !viewModel.isOpeningMedia else { return }
        // Queue every title currently shown in this folder / spotlight, in on-screen order,
        // so playback continues automatically when one finishes.
        let mediaItems = playlistItemsForCurrentFolder()
        let selected = mediaItems.first { playlistURLsEqual($0.url, item.url) }
            ?? MediaItem(url: item.url)
        Task { await viewModel.openItems(mediaItems, startingAt: selected, audioOnly: audioOnly) }
    }

    private func playFolderURLs(_ urls: [URL]) {
        guard !urls.isEmpty, !viewModel.isOpeningMedia else { return }
        let ordered = urls.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
        let mediaItems = ordered.map { MediaItem(url: $0) }
        Task { await viewModel.openItems(mediaItems, startingAt: mediaItems.first, audioOnly: false) }
    }

    /// Titles in the current browse location, in the same order as the library UI.
    private func playlistItemsForCurrentFolder() -> [MediaItem] {
        displayedVideos.map { MediaItem(url: $0.url) }
    }

    private func playlistURLsEqual(_ lhs: URL, _ rhs: URL) -> Bool {
        if lhs == rhs { return true }
        guard lhs.isFileURL, rhs.isFileURL else { return false }
        return lhs.standardizedFileURL == rhs.standardizedFileURL
    }

    private func markWatched(_ item: LibraryItem) {
        let mediaItem = MediaItem(url: item.url)
        if let duration = item.progress?.duration, duration > 0 {
            WatchProgressStore.markWatched(item: mediaItem, duration: duration)
            reloadIfNeeded()
            viewModel.showOSD(KinemaCopy.markedWatched)
            return
        }

        Task {
            let preview = await VideoThumbnailLoader.loadPreview(url: item.url, at: VideoThumbnailLoader.canonicalTime)
            guard let duration = preview.duration, duration > 0 else {
                viewModel.showOSD(KinemaCopy.couldNotMarkWatched)
                return
            }
            WatchProgressStore.markWatched(item: mediaItem, duration: duration)
            reloadIfNeeded()
            viewModel.showOSD(KinemaCopy.markedWatched)
        }
    }

    private func markUnwatched(_ item: LibraryItem) {
        WatchProgressStore.clearProgress(for: item.url)
        reloadIfNeeded()
        viewModel.showOSD(KinemaCopy.markedUnwatched)
    }

    private func markAllWatched(_ urls: [URL]) {
        WatchProgressStore.markAllWatched(urls)
        reloadIfNeeded()
        viewModel.showOSD(KinemaCopy.markedAllWatched)
    }

    private func markAllUnwatched(_ urls: [URL]) {
        WatchProgressStore.markAllUnwatched(urls)
        reloadIfNeeded()
        viewModel.showOSD(KinemaCopy.markedAllUnwatched)
    }

    #if os(iOS) || os(macOS)
    private func handleFolderImport(_ result: Result<[URL], Error>) {
        if case .success(let urls) = result, let folder = urls.first {
            _ = folder.startAccessingSecurityScopedResource()
            if let root = rootStore.addRoot(from: folder) {
                browse.openRoot(root)
            }
        }
    }
    #endif

    #if os(macOS)
    private func revealInFinder(_ root: LibraryRoot) {
        guard let url = rootStore.resolveURL(for: root) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    #endif

    private func beginRename(_ item: LibraryItem) {
        renameTarget = item
        renameText = item.url.deletingPathExtension().lastPathComponent
    }

    private func commitNewFolder() {
        let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        newFolderName = ""
        guard !trimmed.isEmpty, let directory = browse.currentDirectory else { return }
        let destination = directory.appendingPathComponent(trimmed, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
            reloadIfNeeded()
        } catch {
            viewModel.showOSD("Couldn't create folder: \(error.localizedDescription)")
        }
    }

    private func commitRename() {
        if let root = renameRootTarget {
            rootStore.renameRoot(id: root.id, name: renameText)
            renameRootTarget = nil
            return
        }

        guard let item = renameTarget else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            renameTarget = nil
            return
        }

        let destinationName: String
        if item.isDirectory || !URL(fileURLWithPath: trimmed).pathExtension.isEmpty {
            destinationName = trimmed
        } else {
            destinationName = "\(trimmed).\(item.url.pathExtension)"
        }
        let destination = item.url.deletingLastPathComponent().appendingPathComponent(destinationName)

        var coordinationError: NSError?
        var moveError: Error?
        NSFileCoordinator().coordinate(writingItemAt: item.url, options: .forMoving, error: &coordinationError) { sourceURL in
            do {
                try FileManager.default.moveItem(at: sourceURL, to: destination)
            } catch {
                moveError = error
            }
        }

        renameTarget = nil
        if let error = moveError ?? coordinationError {
            viewModel.showOSD("Rename failed: \(error.localizedDescription)")
        }
        reloadIfNeeded()
    }

    private func commitRemoveRoot() {
        guard let root = removeRootTarget, !root.isBuiltIn else {
            removeRootTarget = nil
            return
        }
        if browse.selectedRootID == root.id {
            browse.goToLibraryHome()
        }
        rootStore.removeRoot(id: root.id)
        removeRootTarget = nil
    }

    private func commitDelete() {
        guard let item = deleteTarget else { return }
        let builtIn = LibraryMediaPaths.builtInMediaURL

        var coordinationError: NSError?
        var deleteError: Error?
        NSFileCoordinator().coordinate(writingItemAt: item.url, options: .forDeleting, error: &coordinationError) { url in
            do {
                try LibraryMediaPaths.deleteMediaAndCleanupParent(at: url, builtInRoot: builtIn)
            } catch {
                deleteError = error
            }
        }

        deleteTarget = nil
        if let error = deleteError ?? coordinationError {
            viewModel.showOSD("Delete failed: \(error.localizedDescription)")
        } else {
            #if os(iOS) || os(macOS)
            LibrarySpotlightIndexer.shared.remove(url: item.url)
            #endif
        }
        reloadIfNeeded()
    }

    private func showInfo(for item: LibraryItem) {
        infoTitle = item.url.lastPathComponent

        var lines: [String] = []
        if let progress = item.progress, progress.duration > 0 {
            lines.append("Duration: \(formatTime(progress.duration))")
            if progress.lastPosition > 0 {
                lines.append("Resume: \(formatTime(progress.lastPosition))")
            }
        }
        if let cached = VideoThumbnailLoader.cachedPreview(for: item.url) {
            if let duration = cached.duration, duration > 0, item.progress == nil {
                lines.append("Duration: \(formatTime(duration))")
            }
            if let quality = cached.qualityLabel, !quality.isEmpty {
                lines.append("Quality: \(quality)")
            }
        }
        if let size = fileSizeString(for: item.url) {
            lines.append("Size: \(size)")
        }
        lines.append("Location: \(item.url.deletingLastPathComponent().path)")

        infoMessage = lines.joined(separator: "\n")
        showInfo = true
    }

    private func fileSizeString(for url: URL) -> String? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}

private enum BrowseFolderRow: Identifiable {
    case real(LibraryItem)
    case virtual(VirtualSeriesFolder)

    var id: String {
        switch self {
        case .real(let item): return "real-\(item.id)"
        case .virtual(let folder): return "virtual-\(folder.id)"
        }
    }

    var sortName: String {
        switch self {
        case .real(let item): return item.url.lastPathComponent
        case .virtual(let folder): return folder.title
        }
    }
}

struct LibraryItem: Identifiable {
    let url: URL
    let isDirectory: Bool
    let progress: WatchProgressEntry?

    var id: String { url.path }
}

#if os(macOS)
import AppKit
#endif
