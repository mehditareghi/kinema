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
    var progress: TitlePlaybackProgress?

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

    private var hasLocalMedia: Bool { !localMedia.isEmpty }
    private var hasPartialProgress: Bool { titleProgress?.hasPartialResume == true }

    var body: some View {
        ZStack {
            KinemaBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .top, spacing: 18) {
                        PlaybillPosterThumb(path: item.entry.posterPath, kind: item.entry.kind)
                            .frame(width: 120, height: item.entry.kind == .movie ? 180 : 68)

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

                    KinemaSectionTitle("Watch history", systemImage: "clock")

                    if history.isEmpty {
                        Text("No entries yet.")
                            .font(KinemaType.metadata)
                            .foregroundStyle(KinemaTheme.secondaryText)
                    } else {
                        ForEach(history) { activity in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(activity.watchedAt, style: .date)
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
                                    PlaybillStore.removeActivity(id: activity.id)
                                    reloadHistory()
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(12)
                            .background(KinemaTheme.cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }

                    Button(role: .destructive) {
                        PlaybillStore.clearWatches(for: item.entry.id)
                        dismiss()
                    } label: {
                        Text("Clear all watches for this title")
                            .font(KinemaType.controlLabel)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .kinemaComposerButtonStyle()
                }
                .padding(20)
            }
        }
        .navigationTitle(KinemaCopy.playbillDetailTitle)
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
}

struct PlaybillShowDetailView: View {
    let show: CatalogEntry
    @Bindable var viewModel: PlayerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var summary: PlaybillShowProgressSummary?
    @State private var seasonRows: [(season: TMDBSeasonSummary, episodes: [TMDBEpisodeSummary])] = []
    @State private var isLoading = true
    @State private var watchedEpisodeIDs: Set<String> = []
    @State private var catchUpRequest: PlaybillEpisodeCatchUpRequest?
    @State private var playbillToken: UUID?
    @State private var connectivity = PlaybillConnectivity.shared

    private var isTracked: Bool { PlaybillStore.isTracked(targetID: show.id) }

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
        if summary.watchedEpisodeCount == 0 { return .planToWatch }
        if summary.missedAiredCount > 0 { return .watching }
        let normalized = summary.show.seriesStatus?.lowercased() ?? show.seriesStatus?.lowercased() ?? ""
        let source = summary.show.seriesStatus == nil ? show : summary.show
        let ended = normalized == "ended"
            || normalized == "canceled"
            || (source.seriesInProduction == false && source.nextEpisodeAirDate == nil)
        return ended ? .completed : .waiting
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

        return Button {
            guard !watched else { return }
            requestMark(season: season, episode: episode.episodeNumber, episodeID: episodeID)
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
                    if let airDate = episode.airDate {
                        Text(airDate, style: .date)
                            .font(KinemaType.micro)
                            .foregroundStyle(KinemaTheme.secondaryText.opacity(watched ? 0.45 : 0.75))
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: watched ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(watched ? KinemaTheme.accent : KinemaTheme.secondaryText.opacity(0.35))
                    .frame(width: 22)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(watched)
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

        if isTracked {
            Button(role: .destructive) {
                PlaybillStore.untrackShow(targetID: show.id)
                dismiss()
            } label: {
                Text(KinemaCopy.playbillUntrackSeries)
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
        _ = await PlaybillShowProgress.reconcileTrackingState(for: show.id)
        let fetchedSummary = await PlaybillShowProgress.progressSummary(for: show.id)
        let fetchedSeasons = await PlaybillShowProgress.seasonRows(for: show.id)
        summary = fetchedSummary
        seasonRows = fetchedSeasons
        watchedEpisodeIDs = PlaybillShowProgress.watchedEpisodeIDs(for: show.id)
        isLoading = false
    }

    private func refreshWatchedState() {
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

    private func requestMark(season: Int, episode: Int, episodeID: String) {
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

    private func commitMark(_ request: PlaybillEpisodeCatchUpRequest, includePrior: Bool) {
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
            PlaybillShowProgress.markEpisodeWatched(
                showTargetID: show.id,
                season: request.season,
                episode: request.episode,
                includePriorUnwatched: includePrior
            )
            _ = await PlaybillShowProgress.reconcileTrackingState(for: show.id)
        }
    }
}

private struct PlaybillEpisodeCatchUpRequest: Identifiable {
    let id = UUID()
    let season: Int
    let episode: Int
    let episodeID: String
    let priorCount: Int
}
