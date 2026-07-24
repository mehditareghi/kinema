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
    @State private var pendingLoadURLs: [URL] = []
    @State private var showEncodingPicker = false
    @State private var loadEncodingID = PreferencesStore.shared.preferences.subtitleEncodingID
    @State private var downloadMessage: String?
    @State private var isDownloading = false
    @Environment(\.dismiss) private var dismiss

    private var accent: Color { KinemaTheme.accent }
    private var prefs: PreferencesStore { PreferencesStore.shared }

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
                    let client = OpenSubtitlesClient(apiKey: prefs.preferences.openSubtitlesAPIKey)
                    results = (try? await client.search(
                        query: searchQuery,
                        language: prefs.preferences.preferredSubtitleLanguage
                    )) ?? []
                }
            }
            .onAppear {
                session.refreshCaptionTracks()
                session.applyLiveSubtitlePreferences()
                refreshLocalMatches()
                session.refreshRememberedSubtitles()
                loadEncodingID = prefs.preferences.subtitleEncodingID
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
        rememberedCard
        addSubtitlesCard
        syncCard
        layoutCard
        appearanceCard
        onlineSearchCard
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

            ForEach(session.externalSubtitleTracks) { track in
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
               session.externalSubtitleTracks.isEmpty,
               localMatches.isEmpty {
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
            if session.rememberedSubtitles.isEmpty {
                Text("Subtitles you browse and add are remembered here for next time.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(session.rememberedSubtitles) { item in
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
        if !results.isEmpty || !searchQuery.isEmpty || downloadMessage != nil {
            KinemaCard(title: KinemaCopy.captionsSearchOnline, icon: "globe") {
                if let downloadMessage {
                    Text(downloadMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if results.isEmpty {
                    Text("Search by title to browse OpenSubtitles results. Download needs an API key in Preferences.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(results) { result in
                    Button {
                        Task { await downloadAndLoad(result) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.fileName)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                Text(result.language.uppercased())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if isDownloading {
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
        }
    }

    private var unloadedLocalMatches: [SubtitleMatch] {
        let loadedTitles = Set(session.externalSubtitleTracks.map(\.title))
        return localMatches.filter { !loadedTitles.contains($0.label) }
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

    private func downloadAndLoad(_ result: OpenSubtitlesResult) async {
        isDownloading = true
        downloadMessage = nil
        defer { isDownloading = false }
        do {
            let client = OpenSubtitlesClient(apiKey: prefs.preferences.openSubtitlesAPIKey)
            let url = try await client.download(result)
            session.loadExternalSubtitle(url: url)
            downloadMessage = "Loaded \(result.fileName)"
            refreshLocalMatches()
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
