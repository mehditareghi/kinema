import SwiftUI
import KinemaCore
import KinemaMedia
import KinemaPlayback

struct RecentLibraryView: View {
    @Bindable var viewModel: PlayerViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var entries: [WatchProgressEntry] = []
    @State private var progressToken: UUID?
    @State private var renameEntry: WatchProgressEntry?
    @State private var renameText = ""
    @State private var deleteEntry: WatchProgressEntry?
    @State private var infoTitle = ""
    @State private var infoMessage = ""
    @State private var showInfo = false

    private var accent: Color { KinemaTheme.accent }

    var body: some View {
        Group {
            if entries.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "play.circle")
                        .font(.system(size: 42, weight: .light))
                        .foregroundStyle(KinemaTheme.brass)
                    Text(KinemaCopy.nothingToContinueTitle)
                        .font(KinemaType.title)
                        .foregroundStyle(KinemaTheme.paper)
                    Text(KinemaCopy.nothingToContinueMessage)
                        .font(KinemaType.label)
                        .foregroundStyle(KinemaTheme.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(30)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("RETURN TO THE STORY")
                                .font(KinemaType.eyebrow)
                                .tracking(2.1)
                                .foregroundStyle(KinemaTheme.brass)
                            Text(KinemaCopy.continue)
                                .font(KinemaType.pageTitle)
                                .foregroundStyle(KinemaTheme.paper)
                        }

                        LazyVGrid(
                            columns: MediaLibraryLayout.posterColumns(horizontalSizeClass: horizontalSizeClass),
                            spacing: MediaLibraryLayout.gridSpacing(horizontalSizeClass: horizontalSizeClass)
                        ) {
                            ForEach(entries) { entry in
                                Button {
                                    guard entry.url != nil, !viewModel.isOpeningMedia else { return }
                                    playFrom(entry, audioOnly: false)
                                } label: {
                                    if let url = entry.url {
                                        MediaPosterCard(
                                            url: url,
                                            title: entry.title,
                                            progress: entry,
                                            accent: accent
                                        )
                                    }
                                }
                                .buttonStyle(.plain)
                                .disabled(entry.url == nil)
                                .contextMenu {
                                    recentContextMenu(for: entry)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 24)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KinemaBackdrop())
        .alert("Rename", isPresented: Binding(
            get: { renameEntry != nil },
            set: { if !$0 { renameEntry = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renameEntry = nil }
            Button("Rename") { commitRename() }
        } message: {
            Text("Enter a new name for this file.")
        }
        .confirmationDialog(
            deleteDialogTitle,
            isPresented: Binding(
                get: { deleteEntry != nil },
                set: { if !$0 { deleteEntry = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(deleteDialogAction, role: .destructive) { commitDelete() }
            Button("Cancel", role: .cancel) { deleteEntry = nil }
        } message: {
            Text(deleteDialogMessage)
        }
        .alert(infoTitle, isPresented: $showInfo) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(infoMessage)
        }
        .onAppear {
            reload()
            progressToken = EventBus.shared.subscribe { event in
                if case .watchProgressUpdated = event {
                    Task { @MainActor in reload() }
                }
            }
        }
    }

    @ViewBuilder
    private func recentContextMenu(for entry: WatchProgressEntry) -> some View {
        if let url = entry.url {
            Button {
                playFrom(entry, audioOnly: false)
            } label: {
                Label("Play", systemImage: "play.fill")
            }

            Button {
                viewModel.playNext(MediaItem(url: url, title: entry.title))
            } label: {
                Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
            }

            Button {
                viewModel.appendToQueue(MediaItem(url: url, title: entry.title))
            } label: {
                Label("Append to Queue", systemImage: "text.badge.plus")
            }

            Button {
                playFrom(entry, audioOnly: true)
            } label: {
                Label("Play as Audio", systemImage: "speaker.wave.2")
            }

            Divider()

            if entry.isMostlyFinished {
                Button {
                    markUnwatched(entry)
                } label: {
                    Label(KinemaCopy.markUnwatched, systemImage: "arrow.uturn.backward.circle")
                }
            } else if entry.duration > 0 {
                Button {
                    markWatched(entry)
                } label: {
                    Label(KinemaCopy.markWatched, systemImage: "checkmark.circle")
                }
            }

            ShareLink(item: url) {
                Label("Share", systemImage: "square.and.arrow.up")
            }

            if url.isFileURL {
                Button {
                    renameEntry = entry
                    renameText = url.deletingPathExtension().lastPathComponent
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
            }

            Button {
                showInfo(for: entry)
            } label: {
                Label("Information", systemImage: "info.circle")
            }

            Button(role: .destructive) {
                deleteEntry = entry
            } label: {
                Label(url.isFileURL ? "Delete" : "Remove from Continue", systemImage: "trash")
            }
        }
    }

    private var deleteDialogTitle: String {
        guard let url = deleteEntry?.url, !url.isFileURL else { return "Delete File?" }
        return "Remove from Continue?"
    }

    private var deleteDialogAction: String {
        guard let url = deleteEntry?.url, !url.isFileURL else { return "Delete" }
        return "Remove"
    }

    private var deleteDialogMessage: String {
        guard let url = deleteEntry?.url, !url.isFileURL else {
            return "This removes the file from disk."
        }
        return "This removes the stream from Continue. The link itself is unchanged."
    }

    private func reload() {
        entries = WatchProgressStore.recentEntries(limit: 50)
        let urls = entries.compactMap(\.url)
        ThumbnailPrefetcher.schedule(urls)
    }

    private func playFrom(_ entry: WatchProgressEntry, audioOnly: Bool) {
        guard let url = entry.url, !viewModel.isOpeningMedia else { return }
        let items = entries.compactMap { entry -> MediaItem? in
            guard let url = entry.url else { return nil }
            return MediaItem(url: url, title: entry.title)
        }
        let selected = items.first { $0.url == url } ?? MediaItem(url: url, title: entry.title)
        Task { await viewModel.openItems(items, startingAt: selected, audioOnly: audioOnly) }
    }

    private func markWatched(_ entry: WatchProgressEntry) {
        guard let url = entry.url, entry.duration > 0 else { return }
        WatchProgressStore.markWatched(item: MediaItem(url: url, title: entry.title), duration: entry.duration)
        reload()
        viewModel.showOSD(KinemaCopy.markedWatched)
    }

    private func markUnwatched(_ entry: WatchProgressEntry) {
        guard let url = entry.url else { return }
        WatchProgressStore.clearProgress(for: url)
        reload()
        viewModel.showOSD(KinemaCopy.markedUnwatched)
    }

    private func commitRename() {
        guard let entry = renameEntry, let url = entry.url else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            renameEntry = nil
            return
        }

        let destinationName = URL(fileURLWithPath: trimmed).pathExtension.isEmpty
            ? "\(trimmed).\(url.pathExtension)"
            : trimmed
        let destination = url.deletingLastPathComponent().appendingPathComponent(destinationName)

        var coordinationError: NSError?
        var moveError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forMoving, error: &coordinationError) { sourceURL in
            do {
                try FileManager.default.moveItem(at: sourceURL, to: destination)
            } catch {
                moveError = error
            }
        }

        renameEntry = nil
        if let error = moveError ?? coordinationError {
            viewModel.showOSD("Rename failed: \(error.localizedDescription)")
        }
        reload()
    }

    private func commitDelete() {
        guard let entry = deleteEntry, let url = entry.url else { return }
        deleteEntry = nil

        if url.isFileURL {
            var coordinationError: NSError?
            var deleteError: Error?
            NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) { url in
                do {
                    try FileManager.default.removeItem(at: url)
                } catch {
                    deleteError = error
                }
            }
            if let error = deleteError ?? coordinationError {
                viewModel.showOSD("Delete failed: \(error.localizedDescription)")
            } else {
                WatchProgressStore.clearProgress(for: url)
            }
        } else {
            WatchProgressStore.clearProgress(for: url)
        }
        reload()
    }

    private func showInfo(for entry: WatchProgressEntry) {
        infoTitle = entry.title
        var lines = [
            "Duration: \(formatTime(entry.duration))",
            "Resume: \(formatTime(entry.lastPosition))"
        ]
        if let url = entry.url {
            if url.isFileURL {
                if let size = fileSizeString(for: url) {
                    lines.append("Size: \(size)")
                }
                lines.append("Location: \(url.deletingLastPathComponent().path)")
            } else {
                lines.append("Stream: \(url.absoluteString)")
            }
        }
        infoMessage = lines.joined(separator: "\n")
        showInfo = true
    }

    private func fileSizeString(for url: URL) -> String? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}
