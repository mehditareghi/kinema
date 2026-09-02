import SwiftUI
import KinemaCore
import KinemaMedia
import KinemaPlaybill
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

struct PlaybillPosterCard: View {
    let entry: CatalogEntry
    let accent: Color
    var badge: String?
    var repeatCount: Int = 0
    var progress: TitlePlaybackProgress?

    private var effectiveRepeatCount: Int {
        if repeatCount > 1 {
            return repeatCount
        }
        if entry.kind == .episode,
           let showTargetID = entry.parentShowID,
           let season = entry.seasonNumber,
           let episode = entry.episodeNumber {
            return PlaybillStore.episodeRepeatWatchCount(
                showTargetID: showTargetID,
                season: season,
                episode: episode
            )
        }
        return PlaybillStore.repeatWatchCount(for: entry.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Match Kinema's library-card geometry across films, series, and episodes.
            PlaybillPosterThumb(
                path: entry.backdropPath ?? entry.posterPath,
                kind: entry.kind,
                aspectOverride: MediaLibraryLayout.posterAspect
            )
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: MediaLibraryLayout.posterCornerRadius, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if let badge {
                        Text(badge.uppercased())
                            .font(KinemaType.microBold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(accent.opacity(0.92), in: Capsule())
                            .padding(8)
                    }
                }
                .overlay {
                    if let progress, progress.hasPartialResume {
                        progressStrip(progress.fraction)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if effectiveRepeatCount > 1 {
                        PlaybillRepeatBadge(count: effectiveRepeatCount, scale: .poster)
                            .padding(8)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: MediaLibraryLayout.posterCornerRadius, style: .continuous)
                        .strokeBorder(KinemaTheme.hairline.opacity(0.84), lineWidth: 0.6)
                }
                .shadow(color: .black.opacity(0.38), radius: 12, y: 6)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.displayTitle)
                    .font(KinemaType.posterTitle)
                    .foregroundStyle(KinemaTheme.paper)
                    .lineLimit(2)
                if let progress, progress.hasPartialResume {
                    Text("Resume \(formatTime(progress.position))")
                        .font(KinemaType.metadata)
                        .foregroundStyle(accent)
                        .lineLimit(1)
                } else if !entry.genres.isEmpty {
                    Text(entry.genres.prefix(2).joined(separator: " · "))
                        .font(KinemaType.metadata)
                        .foregroundStyle(KinemaTheme.secondaryText)
                        .lineLimit(1)
                }
            }
        }
    }

    private func progressStrip(_ fraction: Double) -> some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                ZStack(alignment: .leading) {
                    Rectangle().fill(.black.opacity(0.35))
                    Rectangle()
                        .fill(accent.opacity(0.92))
                        .frame(width: max(geo.size.width * fraction, fraction > 0 ? 4 : 0))
                }
                .frame(height: 4)
            }
        }
        .allowsHitTesting(false)
    }
}

struct PlaybillRepeatBadge: View {
    enum Scale {
        case poster
        case row
        case chip
    }

    let count: Int
    var scale: Scale = .chip

    private var font: Font {
        switch scale {
        case .poster: .system(size: 13, weight: .black, design: .rounded)
        case .row: .system(size: 11, weight: .heavy, design: .rounded)
        case .chip: .system(size: 10, weight: .heavy, design: .rounded)
        }
    }

    private var padding: (horizontal: CGFloat, vertical: CGFloat) {
        switch scale {
        case .poster: (9, 5)
        case .row: (7, 4)
        case .chip: (7, 3)
        }
    }

    var body: some View {
        Text("\(count)x")
            .font(font)
            .monospacedDigit()
            .foregroundStyle(KinemaTheme.auditorium)
            .padding(.horizontal, padding.horizontal)
            .padding(.vertical, padding.vertical)
            .background {
                Capsule()
                    .fill(LinearGradient(
                        colors: [KinemaTheme.brass, KinemaTheme.accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
            }
            .overlay {
                Capsule()
                    .strokeBorder(.white.opacity(0.32), lineWidth: 0.7)
            }
            .shadow(color: KinemaTheme.brass.opacity(0.28), radius: 8, y: 3)
            .accessibilityLabel("Watched \(count) times")
    }
}

struct PlaybillPosterThumb: View {
    let path: String?
    let kind: PlaybillMediaKind
    var aspectOverride: CGFloat? = nil

    @State private var image: PlatformImage?

    private var aspect: CGFloat {
        aspectOverride ?? (kind == .movie ? 2/3 : 16/9)
    }

    var body: some View {
        Color.clear
            .aspectRatio(aspect, contentMode: .fit)
            .overlay {
                ZStack {
                    placeholder
                    if let image {
                        #if canImport(AppKit)
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                        #else
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                        #endif
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .task(id: path) {
                await loadImage()
            }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [KinemaTheme.velvet.opacity(0.5), KinemaTheme.auditorium.opacity(0.9)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: kind == .movie ? "film" : "tv")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(KinemaTheme.brass.opacity(0.8))
        }
    }

    private func loadImage() async {
        guard let url = TMDBClient.posterURL(path: path) else {
            image = nil
            return
        }
        do {
            let data = try await PlaybillArtworkCache.shared.data(for: url)
            guard !Task.isCancelled else { return }
            #if canImport(AppKit)
            image = NSImage(data: data)
            #else
            image = UIImage(data: data)
            #endif
        } catch {
            image = nil
        }
    }
}

struct PlaybillTitleDetailView: View {
    let item: PlaybillDiaryItem
    @Bindable var viewModel: PlayerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var history: [WatchActivity] = []
    @State private var editingActivity: WatchActivity?
    @State private var editedWatchedAt = Date()
    @State private var playbillToken: UUID?
    @State private var titleProgress: TitlePlaybackProgress?
    @State private var localMedia: [PlaybillLocalMedia] = []
    @State private var undoToast: PlaybillUndoToast?
    @State private var pendingActivityRemoval: WatchActivity?
    @State private var confirmsTitleRecordsRemoval = false
    @State private var isAddingWatchDate = false
    @State private var newWatchedAt = Date()

    private var hasLocalMedia: Bool { !localMedia.isEmpty }
    private var hasPartialProgress: Bool { titleProgress?.hasPartialResume == true }
    private var earliestWatchDate: Date { item.entry.episodeAirDate ?? .distantPast }
    private var repeatCount: Int {
        if item.entry.kind == .episode,
           let showTargetID = item.entry.parentShowID,
           let season = item.entry.seasonNumber,
           let episode = item.entry.episodeNumber {
            return PlaybillStore.episodeRepeatWatchCount(
                showTargetID: showTargetID,
                season: season,
                episode: episode
            )
        }
        return PlaybillStore.repeatWatchCount(for: item.entry.id)
    }

    var body: some View {
        ZStack {
            KinemaBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .top, spacing: 18) {
                        PlaybillPosterThumb(path: item.entry.posterPath, kind: item.entry.kind)
                            .frame(width: 120, height: item.entry.kind == .movie ? 180 : 68)
                            .overlay(alignment: .bottomTrailing) {
                                if repeatCount > 1 {
                                    PlaybillRepeatBadge(count: repeatCount, scale: .poster)
                                        .padding(8)
                                }
                            }

                        VStack(alignment: .leading, spacing: 8) {
                            Text(item.entry.displayTitle)
                                .font(KinemaType.title)
                                .foregroundStyle(KinemaTheme.paper)
                            if let overview = item.entry.overview, !overview.isEmpty {
                                Text(overview)
                                    .font(KinemaType.label)
                                    .foregroundStyle(KinemaTheme.secondaryText)
                                    .lineLimit(6)
                            }
                            HStack(spacing: 8) {
                                metaChip("\(PlaybillStore.watchCount(for: item.entry.id)) watches")
                                if repeatCount > 1 {
                                    PlaybillRepeatBadge(count: repeatCount)
                                }
                                if let runtime = item.entry.runtimeMinutes {
                                    metaChip("\(runtime) min")
                                }
                            }
                        }
                    }

                    if hasPartialProgress, let titleProgress {
                        KinemaSectionTitle(KinemaCopy.playbillInProgress, systemImage: "play.circle")
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Resume \(formatTime(titleProgress.position))")
                                    .font(KinemaType.labelStrong)
                                Spacer()
                                if titleProgress.duration > 0 {
                                    Text("\(formatTime(max(0, titleProgress.duration - titleProgress.position))) left")
                                        .font(KinemaType.metadata)
                                        .foregroundStyle(KinemaTheme.secondaryText)
                                }
                            }
                            ProgressView(value: titleProgress.fraction)
                                .tint(KinemaTheme.accent)
                        }
                        .padding(12)
                        .background(KinemaTheme.cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    if hasLocalMedia {
                        Button(action: playInKinema) {
                            Label(
                                hasPartialProgress ? KinemaCopy.playbillResumeInKinema : KinemaCopy.playbillPlayInKinema,
                                systemImage: hasPartialProgress ? "play.circle.fill" : "play.fill"
                            )
                            .font(KinemaType.controlLabel)
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(KinemaTheme.accent)
                        .kinemaComposerButtonStyle()

                        if localMedia.count > 1 {
                            Text("\(localMedia.count) matching files in your library")
                                .font(KinemaType.metadata)
                                .foregroundStyle(KinemaTheme.secondaryText)
                        }
                    }

                    HStack {
                        KinemaSectionTitle("Watch history", systemImage: "clock")
                        Spacer()
                        Menu {
                            Button {
                                newWatchedAt = Date()
                                isAddingWatchDate = true
                            } label: {
                                Label("Add watch date", systemImage: "calendar.badge.plus")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(KinemaTheme.secondaryText)
                        }
                        .help("Watch history options")
                        .accessibilityLabel("Watch history options")
                    }

                    if history.isEmpty {
                        Text("No entries yet.")
                            .font(KinemaType.metadata)
                            .foregroundStyle(KinemaTheme.secondaryText)
                    } else {
                        ForEach(history) { activity in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(activity.watchedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(KinemaType.labelStrong)
                                    Text(activity.source.rawValue.capitalized)
                                        .font(KinemaType.metadata)
                                        .foregroundStyle(KinemaTheme.secondaryText)
                                }
                                Spacer()
                                Button {
                                    editingActivity = activity
                                    editedWatchedAt = activity.watchedAt
                                } label: {
                                    Image(systemName: "calendar")
                                }
                                .buttonStyle(.borderless)
                                .help(KinemaCopy.playbillEditWatchedDate)
                                Button(role: .destructive) {
                                    pendingActivityRemoval = activity
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(12)
                            .background(KinemaTheme.cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }

                    if !history.isEmpty || hasPartialProgress {
                        Button(role: .destructive) {
                            confirmsTitleRecordsRemoval = true
                        } label: {
                            Text("Remove watch records for this title")
                                .font(KinemaType.controlLabel)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .kinemaComposerButtonStyle()
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle(KinemaCopy.playbillDetailTitle)
        .overlay(alignment: .bottom) {
            if let undoToast {
                PlaybillUndoToastView(toast: undoToast) {
                    PlaybillStore.restoreWatchRecords(undoToast.snapshot)
                    reloadDetail()
                    self.undoToast = nil
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .confirmationDialog(
            "Remove watch entry?",
            isPresented: Binding(
                get: { pendingActivityRemoval != nil },
                set: { if !$0 { pendingActivityRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove watch entry", role: .destructive) {
                commitRemoveActivity()
            }
            Button(KinemaCopy.cancel, role: .cancel) {
                pendingActivityRemoval = nil
            }
        } message: {
            Text("This removes this single history entry from Playbill and stats.")
        }
        .confirmationDialog(
            "Remove watch records?",
            isPresented: $confirmsTitleRecordsRemoval,
            titleVisibility: .visible
        ) {
            Button("Remove watch records", role: .destructive) {
                commitRemoveTitleRecords()
            }
            Button(KinemaCopy.cancel, role: .cancel) {}
        } message: {
            Text("This removes this title's watch history and resume progress from Playbill and stats.")
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            reloadDetail()
            playbillToken = EventBus.shared.subscribe { event in
                switch event {
                case .playbillUpdated, .watchProgressUpdated:
                    reloadDetail()
                default:
                    break
                }
            }
        }
        .onDisappear {
            if let playbillToken {
                EventBus.shared.unsubscribe(playbillToken)
            }
        }
        .sheet(item: $editingActivity) { activity in
            NavigationStack {
                Form {
                    DatePicker(
                        KinemaCopy.playbillWatchedDate,
                        selection: $editedWatchedAt,
                        in: earliestWatchDate...Date(),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }
                .navigationTitle(KinemaCopy.playbillEditWatchedDate)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(KinemaCopy.cancel) { editingActivity = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(KinemaCopy.playbillSaveDate) {
                            PlaybillStore.updateActivity(id: activity.id, watchedAt: editedWatchedAt)
                            editingActivity = nil
                            reloadHistory()
                        }
                    }
                }
            }
            #if os(macOS)
            .frame(minWidth: 320)
            #endif
        }
        .sheet(isPresented: $isAddingWatchDate) {
            NavigationStack {
                Form {
                    DatePicker(
                        KinemaCopy.playbillWatchedDate,
                        selection: $newWatchedAt,
                        in: earliestWatchDate...Date(),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    Section {
                        Text("Power user option · adds another entry without playing the title.")
                            .font(KinemaType.metadata)
                            .foregroundStyle(KinemaTheme.secondaryText)
                    }
                }
                .navigationTitle("Add watch date")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(KinemaCopy.cancel) { isAddingWatchDate = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") {
                            _ = PlaybillStore.logWatch(
                                targetID: item.entry.id,
                                watchedAt: newWatchedAt,
                                source: .manual
                            )
                            isAddingWatchDate = false
                            reloadHistory()
                        }
                    }
                }
            }
            #if os(macOS)
            .frame(minWidth: 360)
            #endif
        }
    }

    private func metaChip(_ text: String) -> some View {
        Text(text)
            .font(KinemaType.microStrong)
            .foregroundStyle(KinemaTheme.secondaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(KinemaTheme.raisedBackground, in: Capsule())
    }

    private func reloadDetail() {
        history = PlaybillStore.activities(for: item.entry.id)
        titleProgress = PlaybillStore.playbackProgress(for: item.entry.id)
        localMedia = PlaybillLibraryResolver.localMedia(for: item.entry.id)
    }

    private func playInKinema() {
        guard let media = PlaybillLibraryResolver.preferredPlayMedia(for: item.entry.id) else {
            viewModel.showOSD(KinemaCopy.playbillNoLocalFile)
            return
        }
        guard !viewModel.isOpeningMedia else { return }
        MediaWatchCoordinator.applyPlaybillProgress(to: media.url, targetID: item.entry.id)
        let selected = MediaItem(url: media.url, title: media.title)
        Task {
            await viewModel.openItems([selected], startingAt: selected, audioOnly: false)
        }
        dismiss()
    }

    private func reloadHistory() {
        history = PlaybillStore.activities(for: item.entry.id)
    }

    private func commitRemoveActivity() {
        guard let activity = pendingActivityRemoval else { return }
        pendingActivityRemoval = nil
        if let snapshot = PlaybillStore.removeActivity(id: activity.id) {
            showUndoToast("Removed watch entry", snapshot: snapshot)
        }
        reloadHistory()
    }

    private func commitRemoveTitleRecords() {
        confirmsTitleRecordsRemoval = false
        if let snapshot = PlaybillStore.removeWatchRecords(for: item.entry.id) {
            showUndoToast("Removed watch records", snapshot: snapshot)
        }
        reloadDetail()
    }

    private func showUndoToast(_ message: String, snapshot: PlaybillWatchRemovalSnapshot) {
        let toast = PlaybillUndoToast(message: message, snapshot: snapshot)
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            undoToast = toast
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard undoToast?.id == toast.id else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                undoToast = nil
            }
        }
    }
}

struct PlaybillShowDetailView: View {
    let show: CatalogEntry
    @Bindable var viewModel: PlayerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var summary: PlaybillShowProgressSummary?
    @State private var seasonRows: [(season: TMDBSeasonSummary, episodes: [TMDBEpisodeSummary])] = []
    @State private var isLoading = true
    @State private var watchedEpisodeIDs: Set<String> = []
    /// Watch-date edits can change latest/repeat UI without changing the set of
    /// watched episode IDs. Keep an explicit revision so those rows still redraw.
    @State private var watchHistoryRevision = 0
    @State private var catchUpRequest: PlaybillEpisodeCatchUpRequest?
    @State private var playbillToken: UUID?
    @State private var connectivity = PlaybillConnectivity.shared
    @State private var undoToast: PlaybillUndoToast?
    @State private var confirmsSeriesRecordsRemoval = false
    @State private var confirmsStopTracking = false
    @State private var episodeHistoryRequest: PlaybillEpisodeHistoryRequest?

    private var isTracked: Bool { PlaybillStore.isTracked(targetID: show.id) }
    private var hasWatchedRecords: Bool { !watchedEpisodeIDs.isEmpty }

    var body: some View {
        ZStack {
            KinemaBackdrop()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    header
                    progressCard
                    trackingBlock
                    seasonsBlock
                    actionsBlock
                }
                .padding(24)
            }
        }
        .navigationTitle(show.title)
        .overlay(alignment: .bottom) {
            if let undoToast {
                PlaybillUndoToastView(toast: undoToast) {
                    PlaybillStore.restoreWatchRecords(undoToast.snapshot)
                    refreshWatchedState()
                    self.undoToast = nil
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task(id: show.id) {
            await PlaybillShowProgress.warmCache(for: show.id)
            await loadInitial()
        }
        .onAppear {
            playbillToken = EventBus.shared.subscribe { event in
                if case .playbillUpdated = event {
                    refreshWatchedState()
                    Task { await refreshProgressState() }
                }
            }
        }
        .onDisappear {
            if let playbillToken { EventBus.shared.unsubscribe(playbillToken) }
        }
        .confirmationDialog(
            KinemaCopy.playbillCatchUpTitle,
            isPresented: Binding(
                get: { catchUpRequest != nil },
                set: { if !$0 { catchUpRequest = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(KinemaCopy.playbillCatchUpMarkAll) {
                if let request = catchUpRequest {
                    commitMark(request, includePrior: true)
                }
                catchUpRequest = nil
            }
            Button(KinemaCopy.playbillCatchUpJustOne) {
                if let request = catchUpRequest {
                    commitMark(request, includePrior: false)
                }
                catchUpRequest = nil
            }
            Button(KinemaCopy.cancel, role: .cancel) {
                catchUpRequest = nil
            }
        } message: {
            if let request = catchUpRequest {
                Text(KinemaCopy.playbillCatchUpMessage(count: request.priorCount))
            }
        }
        .confirmationDialog(
            "Remove series watch records?",
            isPresented: $confirmsSeriesRecordsRemoval,
            titleVisibility: .visible
        ) {
            Button("Remove series records", role: .destructive) {
                commitRemoveSeriesRecords()
            }
            Button(KinemaCopy.cancel, role: .cancel) {}
        } message: {
            Text("This removes this series' watched episode records and resume progress from Playbill and stats.")
        }
        .confirmationDialog(
            "Stop tracking series?",
            isPresented: $confirmsStopTracking,
            titleVisibility: .visible
        ) {
            Button(KinemaCopy.playbillUntrackSeries, role: .destructive) {
                PlaybillStore.untrackShow(targetID: show.id)
                dismiss()
            }
            Button(KinemaCopy.cancel, role: .cancel) {}
        } message: {
            Text("This removes the series from your tracked list. It is only available because there are no watch records for it.")
        }
        .sheet(item: $episodeHistoryRequest) { request in
            PlaybillEpisodeWatchHistorySheet(
                entry: request.entry,
                showTargetID: show.id,
                startAdding: request.startAdding
            ) {
                refreshWatchedState()
                Task { await refreshProgressState() }
            }
        }
    }

    @ViewBuilder
    private var trackingBlock: some View {
        if isTracked, let summary {
            let status = derivedDisplayStatus(summary)
            HStack(spacing: 14) {
                Image(systemName: status.icon)
                    .foregroundStyle(status.tint)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Series status")
                        .font(KinemaType.metadata)
                        .foregroundStyle(KinemaTheme.secondaryText)
                    Text(status.label)
                        .font(KinemaType.labelStrong)
                        .foregroundStyle(KinemaTheme.paper)
                }
                Spacer()
                Text("Automatic")
                    .font(KinemaType.microBold)
                    .foregroundStyle(KinemaTheme.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(KinemaTheme.raisedBackground, in: Capsule())
            }
            .padding(14)
            .background(KinemaTheme.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(KinemaTheme.hairline.opacity(0.6), lineWidth: 0.6)
            }
        } else if let tracked = PlaybillStore.trackedShow(for: show.id) {
            HStack(spacing: 14) {
                Image(systemName: tracked.status.icon)
                    .foregroundStyle(tracked.status.tint)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Series status")
                        .font(KinemaType.metadata)
                        .foregroundStyle(KinemaTheme.secondaryText)
                    Text(tracked.status.label)
                        .font(KinemaType.labelStrong)
                        .foregroundStyle(KinemaTheme.paper)
                }
                Spacer()
                Text("Last confirmed")
                    .font(KinemaType.microBold)
                    .foregroundStyle(KinemaTheme.secondaryText)
            }
            .padding(14)
            .background(KinemaTheme.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func derivedDisplayStatus(_ summary: PlaybillShowProgressSummary) -> TrackedShowStatus {
        PlaybillShowProgress.derivedTrackingStatus(for: show.id, summary: summary)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            PlaybillPosterThumb(path: show.posterPath, kind: .tvShow)
                .frame(width: 120, height: 68)

            VStack(alignment: .leading, spacing: 8) {
                Text(show.displayTitle)
                    .font(KinemaType.title)
                    .foregroundStyle(KinemaTheme.paper)
                if let overview = show.overview, !overview.isEmpty {
                    Text(overview)
                        .font(KinemaType.label)
                        .foregroundStyle(KinemaTheme.secondaryText)
                        .lineLimit(6)
                }
            }
        }
    }

    @ViewBuilder
    private var progressCard: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if let summary {
            KinemaCard(title: KinemaCopy.playbillNextEpisode, icon: "play.tv") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(summary.watchedEpisodeCount) episodes watched")
                        .font(KinemaType.labelStrong)
                    if summary.missedAiredCount > 0 {
                        Text("\(summary.missedAiredCount) \(KinemaCopy.playbillMissedEpisodes.lowercased())")
                            .font(KinemaType.metadata)
                            .foregroundStyle(KinemaTheme.accent)
                    }
                    if let next = summary.nextEpisode,
                       let season = next.seasonNumber,
                       let episode = next.episodeNumber {
                        Text("\(next.subtitle ?? "Episode") · S\(String(format: "%02d", season))E\(String(format: "%02d", episode))")
                            .font(KinemaType.metadata)
                            .foregroundStyle(KinemaTheme.secondaryText)
                        nextEpisodeAvailabilityLabel(next)
                    } else if summary.watchedEpisodeCount > 0 {
                        Text("You're caught up.")
                            .font(KinemaType.metadata)
                            .foregroundStyle(KinemaTheme.secondaryText)
                    }
                }
            }
        } else {
            KinemaCard(title: "Episode data unavailable", icon: "wifi.slash") {
                Text(connectivity.isOnline
                    ? "Kinema could not refresh this series. Its last confirmed status has been preserved."
                    : "This series was not fully prepared for offline use. Its last confirmed status has been preserved.")
                    .font(KinemaType.metadata)
                    .foregroundStyle(KinemaTheme.secondaryText)
                if let updatedAt = PlaybillStore.showMetadataSnapshot(for: show.id)?.updatedAt {
                    Text("Saved episode data updated \(updatedAt.formatted(date: .abbreviated, time: .shortened)).")
                        .font(KinemaType.micro)
                        .foregroundStyle(KinemaTheme.secondaryText.opacity(0.75))
                }
            }
        }
    }

    @ViewBuilder
    private var seasonsBlock: some View {
        if !isLoading, !seasonRows.isEmpty {
            KinemaSectionTitle("Episodes", systemImage: "list.number")

            ForEach(seasonRows, id: \.season.seasonNumber) { row in
                VStack(alignment: .leading, spacing: 0) {
                    Text(row.season.name ?? "Season \(row.season.seasonNumber)")
                        .font(KinemaType.labelStrong)
                        .foregroundStyle(KinemaTheme.paper)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        ForEach(row.episodes, id: \.episodeNumber) { episode in
                            episodeRow(season: row.season.seasonNumber, episode: episode)
                            if episode.episodeNumber != row.episodes.last?.episodeNumber {
                                Divider()
                                    .overlay(KinemaTheme.hairline.opacity(0.45))
                                    .padding(.leading, 44)
                            }
                        }
                    }
                    .background(KinemaTheme.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(KinemaTheme.hairline.opacity(0.55), lineWidth: 0.6)
                    }
                }
                .padding(.bottom, 14)
            }
        } else if !isLoading {
            Label(
                connectivity.isOnline ? "Episode information could not be loaded." : "Connect once to save this series' episode list for offline use.",
                systemImage: "wifi.slash"
            )
            .font(KinemaType.metadata)
            .foregroundStyle(KinemaTheme.secondaryText)
        }
    }

    private func episodeRow(season: Int, episode: TMDBEpisodeSummary) -> some View {
        let episodeID = CatalogEntry.episodeID(showTmdbID: show.tmdbID, season: season, episode: episode.episodeNumber)
        let watched = watchedEpisodeIDs.contains(episodeID)
        let availability = PlaybillShowProgress.episodeAvailability(
            for: show.id,
            season: season,
            episode: episode.episodeNumber,
            airDate: episode.airDate
        )
        let canMark = availability.canMarkWatched
        let entry = episodeCatalogEntry(season: season, episode: episode)
        let latestWatch = PlaybillStore.activities(for: episodeID).first
        let repeatCount = PlaybillStore.episodeRepeatWatchCount(
            showTargetID: show.id,
            season: season,
            episode: episode.episodeNumber
        )

        return Button {
            if watched {
                episodeHistoryRequest = PlaybillEpisodeHistoryRequest(entry: entry, startAdding: false)
            } else if canMark {
                requestMark(season: season, episode: episode.episodeNumber, episodeID: episodeID)
            }
        } label: {
            HStack(spacing: 12) {
                Text(String(format: "%02d", episode.episodeNumber))
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(watched ? KinemaTheme.secondaryText : KinemaTheme.brass)
                    .frame(width: 28, alignment: .trailing)

                VStack(alignment: .leading, spacing: 2) {
                    Text(episode.name)
                        .font(KinemaType.label)
                        .foregroundStyle(KinemaTheme.paper.opacity(watched ? 0.55 : 1))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if case .upcoming(let airDate) = availability {
                        Text("Airs \(airDate.formatted(date: .abbreviated, time: .omitted))")
                            .font(KinemaType.microStrong)
                            .foregroundStyle(KinemaTheme.brass)
                    } else if availability == .unscheduled {
                        Text("Announced · air date TBA")
                            .font(KinemaType.microStrong)
                            .foregroundStyle(KinemaTheme.secondaryText)
                    } else if let airDate = episode.airDate {
                        Text(airDate, style: .date)
                            .font(KinemaType.micro)
                            .foregroundStyle(KinemaTheme.secondaryText.opacity(watched ? 0.45 : 0.75))
                    }
                    if watched, let latestWatch {
                        Text("Watched \(latestWatch.watchedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(KinemaType.microStrong)
                            .foregroundStyle(KinemaTheme.accent.opacity(0.82))
                    }
                }

                Spacer(minLength: 0)

                if repeatCount > 1 {
                    PlaybillRepeatBadge(count: repeatCount, scale: .row)
                }

                if watched {
                    Button {
                        episodeHistoryRequest = PlaybillEpisodeHistoryRequest(entry: entry, startAdding: false)
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(KinemaTheme.secondaryText)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.borderless)
                    .help("View watch history")
                } else {
                    Image(systemName: canMark ? "circle" : "calendar.badge.clock")
                        .foregroundStyle(canMark ? KinemaTheme.secondaryText.opacity(0.35) : KinemaTheme.brass.opacity(0.8))
                        .frame(width: 22)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id("\(episodeID):history:\(watchHistoryRevision)")
        .accessibilityHint(watched ? "View watch history" : (canMark ? "Mark episode watched" : "This episode has not aired yet"))
        .contextMenu {
            if watched {
                Button {
                    episodeHistoryRequest = PlaybillEpisodeHistoryRequest(entry: entry, startAdding: false)
                } label: {
                    Label("View watch history", systemImage: "clock.arrow.circlepath")
                }
            }
            if canMark {
                Button {
                    episodeHistoryRequest = PlaybillEpisodeHistoryRequest(entry: entry, startAdding: true)
                } label: {
                    Label(watched ? "Add another watch date" : "Mark watched with date", systemImage: "calendar.badge.plus")
                }
            }
        }
    }

    @ViewBuilder
    private var actionsBlock: some View {
        if let next = summary?.nextEpisode,
           PlaybillLibraryResolver.hasLinkedMedia(for: next.id) {
            Button {
                playShowEntry(next, viewModel: viewModel)
                dismiss()
            } label: {
                Label(KinemaCopy.playbillPlayInKinema, systemImage: "play.fill")
                    .font(KinemaType.controlLabel)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(KinemaTheme.accent)
            .kinemaComposerButtonStyle()
        }

        if isTracked, !hasWatchedRecords {
            Button(role: .destructive) {
                confirmsStopTracking = true
            } label: {
                Text(KinemaCopy.playbillUntrackSeries)
                    .font(KinemaType.controlLabel)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .kinemaComposerButtonStyle()
        } else if hasWatchedRecords {
            Button(role: .destructive) {
                confirmsSeriesRecordsRemoval = true
            } label: {
                Text("Remove watch records for this series")
                    .font(KinemaType.controlLabel)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .kinemaComposerButtonStyle()
        } else {
            Button {
                _ = PlaybillStore.trackShow(targetID: show.id)
            } label: {
                Text(KinemaCopy.playbillTrackSeries)
                    .font(KinemaType.controlLabel)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(KinemaTheme.accent)
            .kinemaComposerButtonStyle()
        }
    }

    private func loadInitial() async {
        isLoading = true
        _ = await PlaybillShowProgress.reconcileTrackingState(for: show.id, allowNetwork: true)
        let fetchedSummary = await PlaybillShowProgress.progressSummary(for: show.id, allowNetwork: true)
        let fetchedSeasons = await PlaybillShowProgress.seasonRows(for: show.id)
        summary = fetchedSummary
        seasonRows = fetchedSeasons
        watchedEpisodeIDs = PlaybillShowProgress.watchedEpisodeIDs(for: show.id)
        isLoading = false
    }

    private func refreshWatchedState() {
        watchHistoryRevision &+= 1
        watchedEpisodeIDs = PlaybillShowProgress.watchedEpisodeIDs(for: show.id)
        guard let current = summary else { return }
        summary = PlaybillShowProgressSummary(
            show: current.show,
            watchedEpisodeCount: watchedEpisodeIDs.count,
            nextEpisode: PlaybillShowProgress.peekNextEpisode(for: show.id),
            nextEpisodeAirDate: current.nextEpisodeAirDate,
            missedAiredCount: current.missedAiredCount
        )
    }

    private func refreshProgressState() async {
        _ = await PlaybillShowProgress.reconcileTrackingState(for: show.id, allowNetwork: true)
        watchedEpisodeIDs = PlaybillShowProgress.watchedEpisodeIDs(for: show.id)
        if let refreshed = await PlaybillShowProgress.progressSummary(for: show.id, allowNetwork: true) {
            summary = refreshed
        }
    }

    private func commitRemoveSeriesRecords() {
        confirmsSeriesRecordsRemoval = false
        if let snapshot = PlaybillStore.removeWatchRecordsForShow(targetID: show.id) {
            showUndoToast("Removed series watch records", snapshot: snapshot)
        }
        refreshWatchedState()
    }

    private func showUndoToast(_ message: String, snapshot: PlaybillWatchRemovalSnapshot) {
        let toast = PlaybillUndoToast(message: message, snapshot: snapshot)
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            undoToast = toast
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard undoToast?.id == toast.id else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                undoToast = nil
            }
        }
    }

    private func requestMark(season: Int, episode: Int, episodeID: String) {
        guard PlaybillShowProgress.episodeAvailability(
            for: show.id,
            season: season,
            episode: episode
        ).canMarkWatched else { return }
        let prior = PlaybillShowProgress.priorUnwatchedEpisodes(
            for: show.id,
            upToSeason: season,
            upToEpisode: episode
        )
        if prior.isEmpty {
            commitMark(
                PlaybillEpisodeCatchUpRequest(
                    season: season,
                    episode: episode,
                    episodeID: episodeID,
                    priorCount: 0
                ),
                includePrior: false
            )
        } else {
            catchUpRequest = PlaybillEpisodeCatchUpRequest(
                season: season,
                episode: episode,
                episodeID: episodeID,
                priorCount: prior.count
            )
        }
    }

    private func episodeCatalogEntry(season: Int, episode: TMDBEpisodeSummary) -> CatalogEntry {
        let episodeID = CatalogEntry.episodeID(
            showTmdbID: show.tmdbID,
            season: season,
            episode: episode.episodeNumber
        )
        if let existing = PlaybillStore.entry(for: episodeID) {
            return existing
        }
        return CatalogEntry(
            id: episodeID,
            kind: .episode,
            tmdbID: show.tmdbID,
            parentShowID: show.id,
            title: show.title,
            subtitle: episode.name,
            posterPath: episode.stillPath,
            backdropPath: episode.stillPath,
            runtimeMinutes: episode.runtimeMinutes,
            seasonNumber: season,
            episodeNumber: episode.episodeNumber,
            episodeAirDate: episode.airDate
        )
    }

    private func commitMark(_ request: PlaybillEpisodeCatchUpRequest, includePrior: Bool) {
        guard PlaybillShowProgress.episodeAvailability(
            for: show.id,
            season: request.season,
            episode: request.episode
        ).canMarkWatched else { return }
        catchUpRequest = nil

        var idsToMark = Set<String>([request.episodeID])
        if includePrior {
            for ref in PlaybillShowProgress.priorUnwatchedEpisodes(
                for: show.id,
                upToSeason: request.season,
                upToEpisode: request.episode
            ) {
                idsToMark.insert(ref.episodeID)
            }
        }
        watchedEpisodeIDs.formUnion(idsToMark)
        if let current = summary {
            summary = PlaybillShowProgressSummary(
                show: current.show,
                watchedEpisodeCount: watchedEpisodeIDs.count,
                nextEpisode: PlaybillShowProgress.peekNextEpisode(for: show.id),
                nextEpisodeAirDate: current.nextEpisodeAirDate,
                missedAiredCount: current.missedAiredCount
            )
        }

        Task(priority: .utility) {
            _ = PlaybillShowProgress.markEpisodeWatched(
                showTargetID: show.id,
                season: request.season,
                episode: request.episode,
                includePriorUnwatched: includePrior
            )
            _ = await PlaybillShowProgress.reconcileTrackingState(for: show.id, allowNetwork: true)
        }
    }

    @ViewBuilder
    private func nextEpisodeAvailabilityLabel(_ episode: CatalogEntry) -> some View {
        switch PlaybillShowProgress.episodeAvailability(for: episode, in: show.id) {
        case .upcoming(let date):
            Label("Airs \(date.formatted(date: .abbreviated, time: .omitted))", systemImage: "calendar.badge.clock")
                .font(KinemaType.microStrong)
                .foregroundStyle(KinemaTheme.brass)
        case .unscheduled:
            Label("Announced · air date TBA", systemImage: "calendar.badge.clock")
                .font(KinemaType.microStrong)
                .foregroundStyle(KinemaTheme.secondaryText)
        case .released, .unknown:
            EmptyView()
        }
    }
}

private struct PlaybillEpisodeHistoryRequest: Identifiable {
    let id = UUID()
    let entry: CatalogEntry
    let startAdding: Bool
}

private struct PlaybillWatchDateEditorRequest: Identifiable {
    let id = UUID()
    let activity: WatchActivity?
    var watchedAt: Date
}

private struct PlaybillEpisodeWatchHistorySheet: View {
    let entry: CatalogEntry
    let showTargetID: String
    let startAdding: Bool
    let onChanged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var history: [WatchActivity] = []
    @State private var editor: PlaybillWatchDateEditorRequest?
    @State private var editorDate = Date()
    @State private var didPresentInitialEditor = false
    @State private var pendingRemoval: WatchActivity?

    private var earliestDate: Date { entry.episodeAirDate ?? .distantPast }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if history.isEmpty {
                        ContentUnavailableView(
                            "No watch dates",
                            systemImage: "calendar.badge.plus",
                            description: Text("Add a date when you watched this episode.")
                        )
                    } else {
                        ForEach(history) { activity in
                            HStack(spacing: 12) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(KinemaTheme.accent)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(activity.watchedAt.formatted(date: .long, time: .shortened))
                                        .font(KinemaType.labelStrong)
                                    Text(activity.source.rawValue.capitalized)
                                        .font(KinemaType.micro)
                                        .foregroundStyle(KinemaTheme.secondaryText)
                                }
                                Spacer()
                                Menu {
                                    Button {
                                        editorDate = activity.watchedAt
                                        editor = PlaybillWatchDateEditorRequest(
                                            activity: activity,
                                            watchedAt: activity.watchedAt
                                        )
                                    } label: {
                                        Label("Edit date", systemImage: "calendar")
                                    }
                                    Button(role: .destructive) {
                                        pendingRemoval = activity
                                    } label: {
                                        Label("Remove entry", systemImage: "trash")
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                        .foregroundStyle(KinemaTheme.secondaryText)
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    }
                } header: {
                    Text(entry.displayTitle)
                } footer: {
                    Text("Watch dates affect Playbill history and statistics. Adding one does not alter your video file.")
                }
            }
            .navigationTitle("Watch history")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        presentAddEditor()
                    } label: {
                        Label("Add watch date", systemImage: "calendar.badge.plus")
                    }
                }
            }
            .onAppear {
                reload()
                guard startAdding, !didPresentInitialEditor else { return }
                didPresentInitialEditor = true
                presentAddEditor()
            }
            .confirmationDialog(
                "Remove watch entry?",
                isPresented: Binding(
                    get: { pendingRemoval != nil },
                    set: { if !$0 { pendingRemoval = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Remove watch entry", role: .destructive) {
                    if let activity = pendingRemoval {
                        _ = PlaybillStore.removeActivity(id: activity.id)
                    }
                    pendingRemoval = nil
                    reload()
                    onChanged()
                }
                Button(KinemaCopy.cancel, role: .cancel) { pendingRemoval = nil }
            }
            .sheet(item: $editor) { request in
                NavigationStack {
                    Form {
                        DatePicker(
                            KinemaCopy.playbillWatchedDate,
                            selection: $editorDate,
                            in: earliestDate...Date(),
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        Section {
                            Text("Power user option · record the actual date without playing the episode.")
                                .font(KinemaType.metadata)
                                .foregroundStyle(KinemaTheme.secondaryText)
                        }
                    }
                    .navigationTitle(request.activity == nil ? "Add watch date" : KinemaCopy.playbillEditWatchedDate)
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(KinemaCopy.cancel) { editor = nil }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button(request.activity == nil ? "Add" : KinemaCopy.playbillSaveDate) {
                                save(request)
                            }
                        }
                    }
                }
                #if os(macOS)
                .frame(minWidth: 360)
                #endif
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
    }

    private func presentAddEditor() {
        let proposed = max(earliestDate, Date())
        editorDate = min(proposed, Date())
        editor = PlaybillWatchDateEditorRequest(activity: nil, watchedAt: editorDate)
    }

    private func save(_ request: PlaybillWatchDateEditorRequest) {
        if let activity = request.activity {
            _ = PlaybillStore.updateActivity(id: activity.id, watchedAt: editorDate)
        } else {
            _ = PlaybillStore.upsertCatalog(entry)
            _ = PlaybillStore.logWatch(targetID: entry.id, watchedAt: editorDate, source: .manual)
        }
        editor = nil
        reload()
        onChanged()
    }

    private func reload() {
        history = PlaybillStore.activities(for: entry.id)
    }
}

private struct PlaybillEpisodeCatchUpRequest: Identifiable {
    let id = UUID()
    let season: Int
    let episode: Int
    let episodeID: String
    let priorCount: Int
}

private struct PlaybillUndoToast: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let snapshot: PlaybillWatchRemovalSnapshot
}

private struct PlaybillUndoToastView: View {
    let toast: PlaybillUndoToast
    let undo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(toast.message)
                .font(KinemaType.labelStrong)
                .foregroundStyle(KinemaTheme.paper)
                .lineLimit(2)

            Spacer(minLength: 12)

            Button("Undo", action: undo)
                .font(KinemaType.controlLabel)
                .buttonStyle(.borderedProminent)
                .tint(KinemaTheme.accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(KinemaTheme.hairline.opacity(0.7), lineWidth: 0.6)
        }
        .shadow(color: .black.opacity(0.25), radius: 18, y: 10)
    }
}
