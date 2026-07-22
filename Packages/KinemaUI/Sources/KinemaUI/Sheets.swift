import SwiftUI
import KinemaCore
import KinemaPlayback
import KinemaSubtitles
import UniformTypeIdentifiers

public struct PlaylistSheet: View {
    @Bindable var viewModel: PlayerViewModel
    @Environment(\.dismiss) private var dismiss

    public init(viewModel: PlayerViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            List {
                ForEach(Array(viewModel.session.playlist.enumerated()), id: \.element.id) { index, item in
                    Button {
                        Task {
                            try? await viewModel.session.load(item)
                            viewModel.session.play()
                        }
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.title).font(.headline)
                                Text(item.url.lastPathComponent)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if viewModel.session.currentItem?.id == item.id {
                                Image(systemName: "speaker.wave.2.fill")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
                .onMove { from, to in
                    viewModel.session.movePlaylist(fromOffsets: from, toOffset: to)
                }
            }
            .navigationTitle(KinemaCopy.lineup)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                #if os(iOS) || os(macOS)
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Files") { openFilePicker() }
                }
                #endif
            }
        }
    }

    #if os(iOS) || os(macOS)
    private func openFilePicker() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie, .audio]
        if panel.runModal() == .OK {
            let items = panel.urls.map { MediaItem(url: $0) }
            viewModel.session.addToPlaylist(items)
        }
        #endif
    }
    #endif
}

#if os(macOS)
import AppKit
#endif

public struct SubtitlePickerSheet: View {
    @Bindable var viewModel: PlayerViewModel
    @State private var searchQuery = ""
    @State private var results: [OpenSubtitlesResult] = []
    @State private var localMatches: [SubtitleMatch] = []
    @State private var showFileImporter = false
    @Environment(\.dismiss) private var dismiss

    private let client = OpenSubtitlesClient()
    private var accent: Color { KinemaTheme.accent }

    public init(viewModel: PlayerViewModel) {
        self.viewModel = viewModel
    }

    private var session: PlayerSession { viewModel.session }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    captionsHero
                    captionsCards
                }
                .padding(20)
            }
            .background(KinemaTheme.settingsBackground)
            .navigationTitle(KinemaCopy.captions)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(KinemaCopy.done) { dismiss() }
                }
            }
            .searchable(text: $searchQuery, prompt: "Search OpenSubtitles")
            .onSubmit(of: .search) {
                Task {
                    results = (try? await client.search(query: searchQuery)) ?? []
                }
            }
            .onAppear {
                session.refreshCaptionTracks()
                refreshLocalMatches()
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: Self.subtitleTypes,
                allowsMultipleSelection: false
            ) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                session.grantFileAccess(to: url)
                session.loadExternalSubtitle(url: url)
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 520, minHeight: 520)
        #endif
    }

    private var captionsHero: some View {
        KinemaSheetHero(
            icon: session.subtitlesAreActive ? "captions.bubble.fill" : "captions.bubble",
            title: session.subtitlesAreActive
                ? (session.activeSubtitleTrack.map { SubtitleLabels.displayName(for: $0) } ?? KinemaCopy.captions)
                : KinemaCopy.captionsOff,
            subtitle: session.subtitlesAreActive
                ? KinemaCopy.captionsNowPlaying
                : "Choose a track below or load a sidecar file."
        )
    }

    @ViewBuilder
    private var captionsCards: some View {
        KinemaCard(title: "Tracks", icon: "list.bullet") {
            captionRow(
                title: KinemaCopy.captionsOff,
                subtitle: "Hide captions for this title",
                isSelected: !session.subtitlesAreActive
            ) {
                session.disableSubtitles()
            }

            ForEach(session.embeddedSubtitleTracks) { track in
                captionRow(
                    title: SubtitleLabels.displayName(for: track),
                    subtitle: track.isForced ? "Forced · embedded" : "Embedded in this video",
                    isSelected: session.activeSubtitleTrackID == track.id
                ) {
                    session.selectSubtitleTrack(id: track.id)
                }
            }

            ForEach(session.externalSubtitleTracks) { track in
                captionRow(
                    title: SubtitleLabels.displayName(for: track),
                    subtitle: "External subtitle track",
                    isSelected: session.activeSubtitleTrackID == track.id
                ) {
                    session.selectSubtitleTrack(id: track.id)
                }
            }

            ForEach(unloadedLocalMatches) { match in
                captionRow(
                    title: SubtitleLabels.displayName(for: match),
                    subtitle: "Sidecar file next to the video",
                    isSelected: false
                ) {
                    session.loadExternalSubtitle(url: match.url)
                }
            }

            if session.embeddedSubtitleTracks.isEmpty,
               session.externalSubtitleTracks.isEmpty,
               localMatches.isEmpty {
                Text(KinemaCopy.captionsNoneAvailable)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }

        KinemaCard(title: "Add subtitles", icon: "doc.badge.plus") {
            Button {
                #if os(macOS)
                openMacSubtitlePicker()
                #else
                showFileImporter = true
                #endif
            } label: {
                Label(KinemaCopy.captionsBrowse, systemImage: "folder.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
        }

        KinemaCard(title: KinemaCopy.captionsSize, icon: "textformat.size") {
            HStack {
                Text(KinemaCopy.captionsSize)
                Spacer()
                Text("\(PreferencesStore.shared.preferences.subtitleFontSize)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { Double(PreferencesStore.shared.preferences.subtitleFontSize) },
                    set: { session.setSubtitleFontSize(Int($0.rounded())) }
                ),
                in: 24...80,
                step: 1
            )
            .tint(accent)
        }

        if !results.isEmpty || !searchQuery.isEmpty {
            KinemaCard(title: KinemaCopy.captionsSearchOnline, icon: "globe") {
                if results.isEmpty {
                    Text("Search by title to browse OpenSubtitles results.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(results) { result in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.fileName)
                            .font(.subheadline.weight(.medium))
                        Text(result.language.uppercased())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var unloadedLocalMatches: [SubtitleMatch] {
        let loadedTitles = Set(session.externalSubtitleTracks.map(\.title))
        return localMatches.filter { !loadedTitles.contains($0.label) }
    }

    private func captionRow(
        title: String,
        subtitle: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(isSelected ? .semibold : .medium))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(accent)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? accent.opacity(0.12) : Color.primary.opacity(0.04))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected ? accent.opacity(0.28) : Color.primary.opacity(0.05),
                        lineWidth: 0.5
                    )
            }
        }
        .buttonStyle(.plain)
    }

    private func refreshLocalMatches() {
        guard let url = session.currentItem?.url, url.isFileURL else {
            localMatches = []
            return
        }
        localMatches = SubtitleFileMatcher.findLocalSubtitles(for: url)
    }

    private static let subtitleTypes: [UTType] = ["srt", "ass", "ssa", "vtt", "sub"]
        .compactMap { UTType(filenameExtension: $0) }

    #if os(macOS)
    private func openMacSubtitlePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = Self.subtitleTypes
        if panel.runModal() == .OK, let url = panel.url {
            session.grantFileAccess(to: url)
            session.loadExternalSubtitle(url: url)
        }
    }
    #endif
}
