import SwiftUI
import KinemaCore
import KinemaMedia
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
                Section {
                    Picker(KinemaCopy.playlistMode, selection: playlistModeBinding) {
                        ForEach(PlaylistPlaybackMode.allCases) { mode in
                            Label(mode.displayName, systemImage: mode.systemImage)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.inline)
                }

                Section {
                    ForEach(Array(viewModel.session.playlist.enumerated()), id: \.element.id) { _, item in
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

    private var playlistModeBinding: Binding<PlaylistPlaybackMode> {
        Binding(
            get: { viewModel.session.playlistMode },
            set: { mode in
                let message = viewModel.session.setPlaylistMode(mode)
                viewModel.showOSD(message)
            }
        )
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
    @State private var results: [OnlineSubtitleResult] = []
    @State private var searchLanguage = SubtitlePreferenceCatalog.language(
        id: PreferencesStore.shared.preferences.preferredSubtitleLanguage
    ).id
    @State private var isSearchingOnline = false
    @State private var localMatches: [SubtitleMatch] = []
    @State private var showFileImporter = false
    @State private var pendingLoadURLs: [URL] = []
    @State private var showEncodingPicker = false
    @State private var loadEncodingID = PreferencesStore.shared.preferences.subtitleEncodingID
    @State private var downloadMessage: String?
    @State private var isDownloading = false
    @State private var downloadingResultID: String?
    @Environment(\.dismiss) private var dismiss

    private var accent: Color { KinemaTheme.accent }
    private var prefs: PreferencesStore { PreferencesStore.shared }

    public init(viewModel: PlayerViewModel) {
        self.viewModel = viewModel
    }

    private var session: PlayerSession { viewModel.session }

    private var detectedEpisode: MediaEpisodeIdentity? {
        guard let url = session.currentItem?.url else { return nil }
        return MediaSeriesOrganizer.episodeIdentity(from: url)
    }

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
            .onAppear {
                session.refreshCaptionTracks()
                session.applyLiveSubtitlePreferences()
                refreshLocalMatches()
                session.refreshRememberedSubtitles()
                loadEncodingID = prefs.preferences.subtitleEncodingID
                searchLanguage = SubtitlePreferenceCatalog.language(
                    id: prefs.preferences.preferredSubtitleLanguage
                ).id
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: Self.subtitleTypes,
                allowsMultipleSelection: true
            ) { result in
                guard case .success(let urls) = result, !urls.isEmpty else { return }
                pendingLoadURLs = urls
                showEncodingPicker = true
            }
            .sheet(isPresented: $showEncodingPicker) {
                EncodingLoadSheet(
                    currentEncodingID: prefs.preferences.subtitleEncodingID,
                    onLoad: { encodingID in
                        loadEncodingID = encodingID
                        showEncodingPicker = false
                        commitPendingLoads()
                    },
                    onCancel: {
                        pendingLoadURLs = []
                        showEncodingPicker = false
                    }
                )
                .presentationDetents([.medium])
            }
            .tint(accent)
        }
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 560, minHeight: 640)
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
        primaryTracksCard
        secondaryTracksCard
        onlineSearchCard
        rememberedCard
        addSubtitlesCard
        syncCard
        layoutCard
        appearanceCard
    }

    private var primaryTracksCard: some View {
        KinemaCard(title: "Primary track", icon: "list.bullet") {
            captionRow(
                title: KinemaCopy.captionsOff,
                subtitle: "Hide primary captions",
                isSelected: !session.subtitlesAreActive
            ) {
                session.disableSubtitles()
            }

            ForEach(session.embeddedSubtitleTracks) { track in
                captionRow(
                    title: SubtitleLabels.displayName(for: track),
                    subtitle: trackSubtitle(for: track, role: "Embedded"),
                    isSelected: session.isPrimaryTrackSelected(track.id)
                ) {
                    session.selectSubtitleTrack(id: track.id)
                }
            }

            ForEach(uniqueExternalSubtitleTracks) { track in
                captionRow(
                    title: SubtitleLabels.displayName(for: track),
                    subtitle: trackSubtitle(for: track, role: "External"),
                    isSelected: session.isPrimaryTrackSelected(track.id)
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
                    pendingLoadURLs = [match.url]
                    showEncodingPicker = true
                }
            }

            if session.embeddedSubtitleTracks.isEmpty,
               uniqueExternalSubtitleTracks.isEmpty,
               unloadedLocalMatches.isEmpty {
                Text(KinemaCopy.captionsNoneAvailable)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var secondaryTracksCard: some View {
        KinemaCard(title: "Secondary track", icon: "rectangle.split.1x2") {
            captionRow(
                title: KinemaCopy.captionsOff,
                subtitle: "Hide secondary captions",
                isSelected: session.activeSecondarySubtitleTrackID == nil
            ) {
                session.disableSecondarySubtitles()
            }

            ForEach(session.subtitleTracks) { track in
                captionRow(
                    title: SubtitleLabels.displayName(for: track),
                    subtitle: "Show with primary",
                    isSelected: session.isSecondaryTrackSelected(track.id)
                ) {
                    session.selectSecondarySubtitleTrack(id: track.id)
                }
            }
        }
    }

    private var addSubtitlesCard: some View {
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
            Text("Supports SRT, ASS/SSA, VTT, VobSub (.idx), SAMI, MicroDVD, MPL2, PGS (.sup), and more.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var syncCard: some View {
        KinemaCard(title: "Sync", icon: "clock.arrow.2.circlepath") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Apply to")
                    .font(.subheadline.weight(.medium))
                Picker("Apply to", selection: Binding(
                    get: { session.syncTarget },
                    set: { session.syncTarget = $0 }
                )) {
                    ForEach(SubtitleSyncTarget.allCases) { target in
                        Text(target.displayName).tag(target)
                    }
                }
                .pickerStyle(.segmented)
                .tint(accent)
            }

            HStack {
                Text(delayLabel)
                Spacer()
                Text(String(format: "%+.2fs", displayedDelay))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Button("-0.1s") { session.adjustSubtitleDelay(by: -0.1) }
                Button("+0.1s") { session.adjustSubtitleDelay(by: 0.1) }
                Button("Reset") { session.setSubtitleDelay(0) }
            }
            .buttonStyle(.bordered)
            .tint(accent)

            HStack {
                Text("Audio delay")
                Spacer()
                Text(String(format: "%+.2fs", session.audioDelay))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Button("-0.1s") { session.adjustAudioDelay(by: -0.1) }
                Button("+0.1s") { session.adjustAudioDelay(by: 0.1) }
                Button("Reset") { session.setAudioDelay(0) }
            }
            .buttonStyle(.bordered)
            .tint(accent)

            HStack {
                Text("Subtitle speed")
                Spacer()
                Text(String(format: "%.2fx", session.subtitleSpeed))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { session.subtitleSpeed },
                    set: { session.setSubtitleSpeed($0) }
                ),
                in: 0.5...2.0,
                step: 0.05
            )
            .tint(accent)

            Text("Bookmark sync")
                .font(.subheadline.weight(.semibold))
            Text("Mark when you hear a line, mark when you see it, then apply — uses the target above.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("Mark audio") { session.markBookmarkAudio() }
                Button("Mark subtitle") { session.markBookmarkSubtitle() }
                Button("Apply") { session.applyBookmarkSync() }
            }
            .buttonStyle(.bordered)
            .tint(accent)

            SettingsMenuRowInline(
                title: "Encoding",
                value: SubtitlePreferenceCatalog.encoding(id: prefs.preferences.subtitleEncodingID).displayName
            ) {
                ForEach(SubtitlePreferenceCatalog.encodings) { encoding in
                    Button(encoding.displayName) {
                        session.setSubtitleEncoding(encoding.id)
                    }
                }
            }
        }
    }

    private var delayLabel: String {
        switch session.syncTarget {
        case .primary: return "Primary delay"
        case .secondary: return "Secondary delay"
        case .both: return "Delay (both)"
        }
    }

    private var displayedDelay: Double {
        switch session.syncTarget {
        case .primary, .both: return session.subtitleDelay
        case .secondary: return session.secondarySubtitleDelay
        }
    }

    private var rememberedCard: some View {
        KinemaCard(title: "Saved for this title", icon: "pin.fill") {
            if uniqueRememberedSubtitles.isEmpty {
                Text("Subtitles you browse and add are remembered here for next time.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(uniqueRememberedSubtitles) { item in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.displayName)
                                .font(.subheadline.weight(.medium))
                            Text(
                                abs(item.delay) > 0.001
                                    ? String(format: "Saved · delay %+.2fs", item.delay)
                                    : "Saved with this video"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Button(role: .destructive) {
                            session.removeRememberedSubtitle(item)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.bordered)
                        .tint(accent)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var layoutCard: some View {
        KinemaCard(title: "Placement", icon: "arrow.up.and.down.and.arrow.left.and.right") {
            SubtitlePlacementGrid(
                title: "Position",
                selection: SubtitlePlacementAnchor.nearest(
                    alignX: prefs.preferences.subtitleAlignX,
                    verticalPos: prefs.preferences.subtitlePos
                )
            ) { anchor in
                session.setSubtitlePlacement(anchor)
            }

            Text("Primary and secondary share this spot. When both are on, libmpv stacks them (MX-style).")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text("Vertical fine-tune")
                Spacer()
                Text("\(prefs.preferences.subtitlePos)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { Double(prefs.preferences.subtitlePos) },
                    set: { session.setSubtitlePos(Int($0.rounded())) }
                ),
                in: 0...100,
                step: 1
            )
            .tint(accent)
        }
    }

    private var appearanceCard: some View {
        KinemaCard(title: "Appearance", icon: "textformat") {
            HStack {
                Text(KinemaCopy.captionsSize)
                Spacer()
                Text("\(prefs.preferences.subtitleFontSize)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { Double(prefs.preferences.subtitleFontSize) },
                    set: { session.setSubtitleFontSize(Int($0.rounded())) }
                ),
                in: 24...80,
                step: 1
            )
            .tint(accent)

            HStack {
                Text("Text opacity")
                Spacer()
                Text("\(Int(subtitleColorOpacity(prefs.preferences.subtitleColorHex) * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { subtitleColorOpacity(prefs.preferences.subtitleColorHex) },
                    set: {
                        session.setSubtitleColorHex(
                            applyingSubtitleOpacity(prefs.preferences.subtitleColorHex, opacity: $0)
                        )
                    }
                ),
                in: 0.2...1,
                step: 0.05
            )
            .tint(accent)

            HStack {
                Text("Outline size")
                Spacer()
                Text(String(format: "%.1f", prefs.preferences.subtitleBorderSize))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { prefs.preferences.subtitleBorderSize },
                    set: { session.setSubtitleBorderSize($0) }
                ),
                in: 0...8,
                step: 0.5
            )
            .tint(accent)

            HStack {
                Text("Shadow")
                Spacer()
                Text(String(format: "%.1f", prefs.preferences.subtitleShadowOffset))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { prefs.preferences.subtitleShadowOffset },
                    set: { session.setSubtitleShadowOffset($0) }
                ),
                in: 0...8,
                step: 0.5
            )
            .tint(accent)

            Toggle("Bold", isOn: Binding(
                get: { prefs.preferences.subtitleBold },
                set: { session.setSubtitleBold($0) }
            ))
            .tint(accent)

            Toggle("Italic", isOn: Binding(
                get: { prefs.preferences.subtitleItalic },
                set: { session.setSubtitleItalic($0) }
            ))
            .tint(accent)

            Toggle("Fade-out (ASS soft blur)", isOn: Binding(
                get: { prefs.preferences.subtitleFadeOut },
                set: { session.setSubtitleFadeOut($0) }
            ))
            .tint(accent)

            SettingsMenuRowInline(
                title: "ASS override",
                value: prefs.preferences.subtitleASSOverride.displayName
            ) {
                ForEach(SubtitleASSOverrideMode.allCases) { mode in
                    Button(mode.displayName) {
                        session.setSubtitleASSOverride(mode)
                    }
                }
            }

            Text("Backdrop / outline colors are in Preferences → Subtitles.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var onlineSearchCard: some View {
        KinemaCard(title: KinemaCopy.captionsSearchOnline, icon: "globe") {
            if let episode = detectedEpisode {
                VStack(alignment: .leading, spacing: 12) {
                    Text(episode.displayLabel)
                        .font(.subheadline.weight(.semibold))
                    if let first = results.first, let title = first.episodeTitle, !title.isEmpty {
                        Text(title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    SettingsMenuRowInline(
                        title: "Language",
                        value: SubtitlePreferenceCatalog.language(id: searchLanguage).displayName
                    ) {
                        ForEach(SubtitlePreferenceCatalog.popularLanguages) { language in
                            Button(language.displayName) {
                                searchLanguage = language.id
                                prefs.preferences.preferredSubtitleLanguage = language.id
                            }
                        }
                    }

                    Button {
                        Task { await searchOnline(for: episode) }
                    } label: {
                        HStack {
                            Spacer()
                            if isSearchingOnline {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("Search")
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .disabled(isSearchingOnline || isDownloading || searchLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Text("Saves the subtitle next to the video and remembers it for next time.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let downloadMessage {
                        Text(downloadMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(results) { result in
                        Button {
                            Task { await downloadAndLoad(result) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.version)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                    Text(result.detailLine)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if downloadingResultID == result.id {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.down.circle")
                                        .foregroundStyle(accent)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                        .disabled(isDownloading)
                    }
                }
            } else {
                Text("Online search works for TV episodes named like Show.S01E02.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var loadedSubtitlePaths: Set<String> {
        session.loadedExternalSubtitlePaths
    }

    /// One row per unique external subtitle file path (mpv can otherwise surface duplicates).
    private var uniqueExternalSubtitleTracks: [Track] {
        var seen = Set<String>()
        var unique: [Track] = []
        for track in session.externalSubtitleTracks {
            let key: String
            if let filename = track.externalFilename, !filename.isEmpty {
                key = URL(fileURLWithPath: filename).standardizedFileURL.path
            } else {
                key = "track:\(track.id)"
            }
            guard seen.insert(key).inserted else { continue }
            unique.append(track)
        }
        return unique
    }

    /// Sidecars next to the video that are not already loaded — still offered in the list.
    private var unloadedLocalMatches: [SubtitleMatch] {
        localMatches.filter { !loadedSubtitlePaths.contains($0.url.standardizedFileURL.path) }
    }

    /// Remembered entries that are not already represented by a loaded external file.
    private var uniqueRememberedSubtitles: [ManualSubtitleAssociation] {
        session.rememberedSubtitles.filter {
            !loadedSubtitlePaths.contains(URL(fileURLWithPath: $0.path).standardizedFileURL.path)
        }
    }

    private func trackSubtitle(for track: Track, role: String) -> String {
        var parts = [role]
        if track.isForced { parts.append("Forced") }
        if track.isLikelySDH { parts.append("SDH/CC") }
        if let badge = track.codecBadge { parts.append(badge) }
        return parts.joined(separator: " · ")
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

    private func commitPendingLoads() {
        let urls = pendingLoadURLs
        pendingLoadURLs = []
        for url in urls {
            session.grantFileAccess(to: url)
        }
        session.loadExternalSubtitles(urls: urls, encodingID: loadEncodingID, remember: true)
        refreshLocalMatches()
        session.refreshRememberedSubtitles()
    }

    private func searchOnline(for episode: MediaEpisodeIdentity) async {
        isSearchingOnline = true
        downloadMessage = nil
        results = []
        defer { isSearchingOnline = false }

        let language = GestdownClient.normalizeLanguageCode(searchLanguage)
        searchLanguage = SubtitlePreferenceCatalog.language(id: language).id
        prefs.preferences.preferredSubtitleLanguage = searchLanguage

        do {
            let client = GestdownClient()
            results = try await client.search(
                showTitle: episode.showTitle,
                season: episode.season,
                episode: episode.episode,
                language: language
            )
            downloadMessage = "\(results.count) subtitle\(results.count == 1 ? "" : "s") found — tap to save & load."
        } catch {
            downloadMessage = error.localizedDescription
        }
    }

    private func downloadAndLoad(_ result: OnlineSubtitleResult) async {
        isDownloading = true
        downloadingResultID = result.id
        downloadMessage = nil
        defer {
            isDownloading = false
            downloadingResultID = nil
        }

        do {
            let client = GestdownClient()
            let downloaded = try await client.download(result)
            let loadURL: URL
            var remember = true
            if let mediaURL = session.currentItem?.url, mediaURL.isFileURL {
                do {
                    loadURL = try GestdownClient.installSidecar(
                        downloadedURL: downloaded,
                        nextTo: mediaURL,
                        languageCode: result.languageCode,
                        version: result.version
                    )
                    session.grantFileAccess(to: loadURL)
                    // Sidecar next to the video is auto-discovered — don't also pin it in "Saved".
                    remember = false
                    downloadMessage = "Saved \(loadURL.lastPathComponent) next to the video."
                } catch {
                    loadURL = downloaded
                    downloadMessage = "Loaded \(result.displayName). Couldn’t write next to the video — kept in app cache."
                }
            } else {
                loadURL = downloaded
                downloadMessage = "Loaded \(result.displayName)."
            }
            session.loadExternalSubtitle(url: loadURL, remember: remember)
            refreshLocalMatches()
            session.refreshRememberedSubtitles()
        } catch {
            downloadMessage = error.localizedDescription
        }
    }

    private static let subtitleTypes: [UTType] = SubtitleFileMatcher.extensions
        .compactMap { UTType(filenameExtension: $0) }

    #if os(macOS)
    private func openMacSubtitlePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = Self.subtitleTypes
        if panel.runModal() == .OK, !panel.urls.isEmpty {
            pendingLoadURLs = panel.urls
            showEncodingPicker = true
        }
    }
    #endif
}

private struct EncodingLoadSheet: View {
    let currentEncodingID: String
    let onLoad: (String) -> Void
    let onCancel: () -> Void
    @State private var selectedEncodingID: String

    init(
        currentEncodingID: String,
        onLoad: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.currentEncodingID = currentEncodingID
        self.onLoad = onLoad
        self.onCancel = onCancel
        _selectedEncodingID = State(initialValue: currentEncodingID)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Load with your current encoding, or pick another only if the text looks wrong.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button {
                    onLoad(selectedEncodingID)
                } label: {
                    Text("Load · \(SubtitlePreferenceCatalog.encoding(id: selectedEncodingID).displayName)")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(KinemaTheme.accent)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Other encoding (optional)")
                        .font(.subheadline.weight(.medium))
                    Picker("Encoding", selection: $selectedEncodingID) {
                        ForEach(SubtitlePreferenceCatalog.encodings) { encoding in
                            Text(encoding.displayName).tag(encoding.id)
                        }
                    }
                    #if os(iOS)
                    .pickerStyle(.wheel)
                    .frame(maxHeight: 140)
                    #else
                    .pickerStyle(.menu)
                    #endif
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle("Text encoding")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(KinemaCopy.cancel, action: onCancel)
                }
            }
        }
    }
}

private struct SettingsMenuRowInline<Content: View>: View {
    let title: String
    let value: String
    @ViewBuilder let content: Content

    init(title: String, value: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.value = value
        self.content = content()
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            Menu {
                content
            } label: {
                HStack(spacing: 6) {
                    Text(value)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(KinemaTheme.accent)
                }
            }
            .buttonStyle(.plain)
        }
    }
}
