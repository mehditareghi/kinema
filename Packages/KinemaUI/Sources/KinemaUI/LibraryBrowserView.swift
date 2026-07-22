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

    private var accent: Color { KinemaTheme.accent }
    private var rootStore: LibraryRootStore { browse.rootStore }

    private var organizedContent: SeriesBrowseContent {
        MediaSeriesOrganizer.organize(
            videoURLs: items.filter { !$0.isDirectory }.map(\.url),
            virtualPath: browse.virtualPath
        )
    }

    private var realFolders: [LibraryItem] {
        guard browse.virtualPath.isEmpty else { return [] }
        return items.filter(\.isDirectory)
    }

    private var virtualFolders: [VirtualSeriesFolder] {
        organizedContent.virtualFolders
    }

    private var displayedVideos: [LibraryItem] {
        let lookup = Dictionary(uniqueKeysWithValues: items.filter { !$0.isDirectory }.map { ($0.url, $0) })
        return organizedContent.videoURLs.compactMap { lookup[$0] }
    }

    private var hasVisibleContent: Bool {
        if browse.isAtLibraryHome {
            return !rootStore.roots.isEmpty
        }
        return !realFolders.isEmpty || !virtualFolders.isEmpty || !displayedVideos.isEmpty
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
            } else if !hasVisibleContent {
                ContentUnavailableView(
                    browse.virtualPath.isEmpty ? KinemaCopy.nothingHereTitle : KinemaCopy.nothingInSpotlightTitle,
                    systemImage: browse.virtualPath.isEmpty ? "folder" : "rectangle.stack",
                    description: Text(browse.virtualPath.isEmpty
                        ? KinemaCopy.nothingHereMessage
                        : KinemaCopy.nothingInSpotlightMessage)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                folderContents
            }
        }
        .onAppear {
            reloadIfNeeded()
            progressToken = EventBus.shared.subscribe { event in
                if case .watchProgressUpdated = event {
                    Task { @MainActor in reloadIfNeeded() }
                }
            }
        }
        .onDisappear {
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
            reloadIfNeeded()
        }
        .onChange(of: browse.currentDirectory) { _, _ in
            reloadIfNeeded()
        }
        .onChange(of: browse.virtualPath) { _, _ in
            ThumbnailPrefetcher.schedule(displayedVideos.map(\.url))
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

                if rootStore.roots.isEmpty {
                    emptyLibraryHome
                } else {
                    libraryRootsSection
                }
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

    private var emptyLibraryHome: some View {
        VStack(spacing: 16) {
            ContentUnavailableView(
                KinemaCopy.noSourcesTitle,
                systemImage: "folder.badge.plus",
                description: Text(KinemaCopy.noSourcesMessage)
            )

            Button {
                showFolderPicker = true
            } label: {
                Label(KinemaCopy.addFirstSource, systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
        }
        .padding(.top, 8)
    }

    private var libraryRootsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(KinemaCopy.sources, systemImage: "externaldrive.fill")

            VStack(spacing: 8) {
                ForEach(rootStore.roots) { root in
                    Button {
                        browse.openRoot(root)
                    } label: {
                        MediaFolderTile(
                            name: root.name,
                            accent: accent,
                            systemImage: "externaldrive.fill",
                            subtitle: rootSubtitle(for: root),
                            isFullyWatched: isFolderFullyWatched(rootURL(for: root))
                        )
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
                if !realFolders.isEmpty || !virtualFolders.isEmpty {
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
                ForEach(realFolders) { item in
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
                }

                ForEach(virtualFolders) { folder in
                    Button { browse.openVirtual(folder.segment) } label: {
                        MediaFolderTile(
                            name: folder.title,
                            accent: accent,
                            systemImage: "rectangle.stack.fill",
                            subtitle: KinemaCopy.spotlightBadge,
                            isFullyWatched: WatchProgressStore.areAllWatched(folder.videoURLs)
                        )
                    }
                    .buttonStyle(.plain)
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

    @ViewBuilder
    private func folderContextMenu(for item: LibraryItem) -> some View {
        Button {
            open(item)
        } label: {
            Label("Open", systemImage: "folder")
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

    private func reloadIfNeeded() {
        if browse.isAtLibraryHome {
            items = []
            refreshFullyWatchedFolders(directoryFolders: [], includeRoots: true)
            return
        }
        guard let directory = browse.currentDirectory else {
            items = []
            fullyWatchedFolderPaths = []
            return
        }
        reload(directory: directory)
    }

    private func reload(directory: URL) {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        items = urls
            .filter { MediaFileTypes.isBrowsable($0) }
            .sorted { lhs, rhs in
                let lDir = (try? lhs.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                let rDir = (try? rhs.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if lDir != rDir { return lDir && !rDir }
                return lhs.lastPathComponent.localizedCaseInsensitiveCompare(rhs.lastPathComponent) == .orderedAscending
            }
            .map { url in
                let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                let progress = isDir ? nil : WatchProgressStore.entry(for: url)
                return LibraryItem(url: url, isDirectory: isDir, progress: progress)
            }

        refreshFullyWatchedFolders(
            directoryFolders: items.filter(\.isDirectory).map(\.url),
            includeRoots: false
        )
        ThumbnailPrefetcher.schedule(displayedVideos.map(\.url))
    }

    private func refreshFullyWatchedFolders(directoryFolders: [URL], includeRoots: Bool) {
        var watched = Set<String>()

        for folder in directoryFolders {
            let videos = WatchProgressStore.mediaURLs(under: folder)
            if WatchProgressStore.areAllWatched(videos) {
                watched.insert(folder.standardizedFileURL.path)
            }
        }

        if includeRoots {
            for root in rootStore.roots {
                guard let url = rootStore.resolveURL(for: root) else { continue }
                let videos = WatchProgressStore.mediaURLs(under: url)
                if WatchProgressStore.areAllWatched(videos) {
                    watched.insert(url.standardizedFileURL.path)
                }
            }
        }

        fullyWatchedFolderPaths = watched
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
        let mediaItems = displayedVideos.map { MediaItem(url: $0.url) }
        let selected = mediaItems.first { $0.url == item.url } ?? MediaItem(url: item.url)
        Task { await viewModel.openItems(mediaItems, startingAt: selected, audioOnly: audioOnly) }
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

    private func beginRename(_ item: LibraryItem) {
        renameTarget = item
        renameText = item.url.deletingPathExtension().lastPathComponent
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
        guard let root = removeRootTarget else { return }
        if browse.selectedRootID == root.id {
            browse.goToLibraryHome()
        }
        rootStore.removeRoot(id: root.id)
        removeRootTarget = nil
    }

    private func commitDelete() {
        guard let item = deleteTarget else { return }

        var coordinationError: NSError?
        var deleteError: Error?
        NSFileCoordinator().coordinate(writingItemAt: item.url, options: .forDeleting, error: &coordinationError) { url in
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                deleteError = error
            }
        }

        deleteTarget = nil
        if let error = deleteError ?? coordinationError {
            viewModel.showOSD("Delete failed: \(error.localizedDescription)")
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

struct LibraryItem: Identifiable {
    let url: URL
    let isDirectory: Bool
    let progress: WatchProgressEntry?

    var id: String { url.path }
}

#if os(macOS)
import AppKit
#endif
