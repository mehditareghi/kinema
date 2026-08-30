import SwiftUI
import KinemaCore
import KinemaMedia
import KinemaPlaybill
#if os(iOS)
import UIKit
#endif

// MARK: - The programme

/// A single, continuous watching timeline. Past entries live above the playhead;
/// upcoming episodes live below it, so opening Playbill always answers “what next?”
/// while a natural upward scroll reveals where the viewer has been.
struct PlaybillProgrammeTimeline: View {
    static let nowAnchor = "playbill-programme-now"

    let feeds: [PlaybillShowFeed]
    let history: [PlaybillTimelineRow]
    @Bindable var viewModel: PlayerViewModel

    private var watched: [PlaybillTimelineRow] {
        history.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
    }

    private var upcoming: [PlaybillShowFeed] {
        feeds.filter { $0.nextEpisode != nil }
    }

    private var hasUnavailableProgramme: Bool {
        feeds.contains { !$0.hasEpisodeMetadata }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                KinemaSectionTitle("Your programme", systemImage: "play.square.stack")
                Spacer()
                Text("\(upcoming.count) up next")
                    .font(KinemaType.metadataStrong)
                    .foregroundStyle(KinemaTheme.brass)
            }

            Text("Scroll up for what you watched. Your next episodes are waiting below the playhead.")
                .font(KinemaType.metadata)
                .foregroundStyle(KinemaTheme.secondaryText)

            VStack(spacing: 0) {
                ForEach(watched) { item in
                    watchedRow(item)
                }

                playhead
                    .id(Self.nowAnchor)

                ForEach(upcoming) { feed in
                    if let episode = feed.nextEpisode {
                        upcomingRow(feed: feed, episode: episode)
                    }
                }

                if upcoming.isEmpty {
                    Label(
                        hasUnavailableProgramme ? "Up Next is unavailable until saved episode data can refresh." : "You’re all caught up.",
                        systemImage: hasUnavailableProgramme ? "wifi.slash" : "checkmark.circle"
                    )
                    .font(KinemaType.label)
                    .foregroundStyle(KinemaTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 58)
                    .padding(.vertical, 22)
                }
            }
            .background(KinemaTheme.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(KinemaTheme.hairline.opacity(0.72), lineWidth: 0.6)
            }
            .background(alignment: .leading) {
                Rectangle()
                    .fill(KinemaTheme.hairline.opacity(0.72))
                    .frame(width: 1)
                    .padding(.leading, 29)
                    .padding(.vertical, 34)
                    .allowsHitTesting(false)
            }
        }
    }

    private func watchedRow(_ item: PlaybillTimelineRow) -> some View {
        NavigationLink(value: PlaybillRoute.title(item.entry, item.activityID)) {
            HStack(spacing: 14) {
                timelineDot(systemName: "checkmark", active: false)
                PlaybillPosterThumb(path: item.entry.posterPath, kind: item.entry.kind, aspectOverride: 16/9)
                    .frame(width: 72, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .saturation(0.55)
                    .opacity(0.62)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.showEntry?.title ?? item.entry.title)
                        .font(KinemaType.labelStrong)
                        .foregroundStyle(KinemaTheme.paper.opacity(0.66))
                        .lineLimit(1)
                    Text(item.subtitle)
                        .font(KinemaType.metadata)
                        .foregroundStyle(KinemaTheme.secondaryText.opacity(0.72))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if let date = item.date {
                    Text(date, style: .date)
                        .font(KinemaType.micro)
                        .foregroundStyle(KinemaTheme.secondaryText.opacity(0.6))
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(KinemaTheme.secondaryText.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var playhead: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(KinemaTheme.brass)
                .frame(width: 13, height: 13)
                .overlay(Circle().stroke(KinemaTheme.brass.opacity(0.25), lineWidth: 7))
                .frame(width: 26)
            Text("UP NEXT")
                .font(KinemaType.eyebrow)
                .tracking(2)
                .foregroundStyle(KinemaTheme.brass)
            Rectangle().fill(KinemaTheme.brass.opacity(0.38)).frame(height: 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(KinemaTheme.brass.opacity(0.075))
                .padding(.horizontal, 10)
        }
    }

    private func upcomingRow(feed: PlaybillShowFeed, episode: CatalogEntry) -> some View {
        HStack(spacing: 14) {
            timelineDot(systemName: "play.fill", active: true)

            NavigationLink(value: PlaybillRoute.show(feed.show)) {
                HStack(spacing: 14) {
                    PlaybillPosterThumb(path: episode.posterPath ?? feed.show.backdropPath, kind: .episode)
                        .frame(width: 72, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(feed.show.title)
                            .font(KinemaType.posterTitle)
                            .foregroundStyle(KinemaTheme.paper)
                            .lineLimit(1)
                        Text(episodeLabel(episode))
                            .font(KinemaType.metadata)
                            .foregroundStyle(KinemaTheme.secondaryText)
                            .lineLimit(1)
                        if feed.missedCount > 1 {
                            Text("\(feed.missedCount) episodes waiting")
                                .font(KinemaType.microStrong)
                                .foregroundStyle(KinemaTheme.brass)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 4)

            if PlaybillLibraryResolver.hasLinkedMedia(for: episode.id) {
                PlaybillTimelineIconButton(
                    systemName: "play.fill",
                    tint: KinemaTheme.accent,
                    accessibilityLabel: KinemaCopy.playbillPlayInKinema
                ) {
                    playShowEntry(episode, viewModel: viewModel)
                }
            }

            PlaybillTimelineIconButton(
                systemName: "checkmark",
                tint: KinemaTheme.brass,
                accessibilityLabel: KinemaCopy.playbillStampWatched
            ) {
                markWatched(episode, in: feed.show)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private func timelineDot(systemName: String, active: Bool) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(active ? KinemaTheme.auditorium : KinemaTheme.secondaryText)
            .frame(width: 22, height: 22)
            .background(active ? KinemaTheme.brass : KinemaTheme.raisedBackground, in: Circle())
            .frame(width: 26)
            .zIndex(1)
    }

    private func episodeLabel(_ entry: CatalogEntry) -> String {
        let code: String
        if let season = entry.seasonNumber, let episode = entry.episodeNumber {
            code = String(format: "S%02dE%02d", season, episode)
        } else {
            code = "Episode"
        }
        guard let subtitle = entry.subtitle, !subtitle.isEmpty else { return code }
        return "\(code) · \(subtitle)"
    }

    private func markWatched(_ episode: CatalogEntry, in show: CatalogEntry) {
        guard let season = episode.seasonNumber, let number = episode.episodeNumber else { return }
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        _ = PlaybillStore.upsertCatalog(episode)
        Task {
            PlaybillShowProgress.markEpisodeWatched(
                showTargetID: show.id,
                season: season,
                episode: number,
                includePriorUnwatched: false
            )
            _ = await PlaybillShowProgress.reconcileTrackingState(for: show.id)
        }
    }
}

// MARK: - Per-show cinema reel

struct PlaybillShowFeedCard: View {
    @Bindable var viewModel: PlayerViewModel
    let sourceFeed: PlaybillShowFeed
    @State private var feed: PlaybillShowFeed
    @State private var catchUpRequest: PlaybillCatchUpRequest?
    let onOpenShow: () -> Void

    private var accent: Color { KinemaTheme.accent }

    init(sourceFeed: PlaybillShowFeed, viewModel: PlayerViewModel, onOpenShow: @escaping () -> Void) {
        self.sourceFeed = sourceFeed
        self._feed = State(initialValue: sourceFeed)
        self.viewModel = viewModel
        self.onOpenShow = onOpenShow
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            showHeader
            reelDivider
            episodeReel
            if feed.nextEpisode != nil {
                reelDivider
                activeSlot
            } else if !feed.hasEpisodeMetadata || feed.recentWatched.isEmpty {
                emptyReelHint
            }
        }
        .background(KinemaTheme.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(KinemaTheme.hairline.opacity(0.72), lineWidth: 0.6)
        }
        .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
        .onChange(of: sourceFeed) { _, newFeed in
            feed = newFeed
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
                    commitStamp(request.episode, includePrior: true, priorCount: request.priorCount)
                }
                catchUpRequest = nil
            }
            Button(KinemaCopy.playbillCatchUpJustOne) {
                if let request = catchUpRequest {
                    commitStamp(request.episode, includePrior: false, priorCount: request.priorCount)
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

    private var showHeader: some View {
        Button(action: onOpenShow) {
            HStack(spacing: 14) {
                PlaybillPosterThumb(path: feed.show.posterPath, kind: .tvShow)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(feed.show.title)
                        .font(KinemaType.cardTitle)
                        .foregroundStyle(KinemaTheme.paper)
                        .lineLimit(1)
                    if feed.missedCount > 0 {
                        Text("\(feed.missedCount) episodes since last visit")
                            .font(KinemaType.metadata)
                            .foregroundStyle(KinemaTheme.brass)
                    } else {
                        Text("On your programme")
                            .font(KinemaType.metadata)
                            .foregroundStyle(KinemaTheme.secondaryText)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(KinemaType.metadata)
                    .foregroundStyle(KinemaTheme.secondaryText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var reelDivider: some View {
        Rectangle()
            .fill(KinemaTheme.hairline.opacity(0.55))
            .frame(height: 0.6)
            .padding(.horizontal, 16)
    }

    private var episodeReel: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(displayedHistory) { episode in
                    watchedEpisodeRow(episode)
                }
            }
        }
        .frame(maxHeight: feed.recentWatched.isEmpty ? 0 : min(CGFloat(feed.recentWatched.count) * 36 + 6, 160))
        .clipped()
        .animation(.easeOut(duration: 0.22), value: feed.recentWatched.map(\.id))
    }

    private var displayedHistory: [PlaybillFeedEpisode] {
        Array(feed.recentWatched.reversed())
    }

    private func watchedEpisodeRow(_ episode: PlaybillFeedEpisode) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "ticket.fill")
                .font(.system(size: 11))
                .foregroundStyle(KinemaTheme.brass.opacity(0.55))
                .rotationEffect(.degrees(-18))

            Text(episodeCode(episode.entry))
                .font(KinemaType.metadataStrong)
                .foregroundStyle(KinemaTheme.secondaryText)

            if let name = episode.entry.subtitle, !name.isEmpty {
                Text(name)
                    .font(KinemaType.metadata)
                    .foregroundStyle(KinemaTheme.secondaryText.opacity(0.75))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text(episode.watchedAt, style: .date)
                .font(KinemaType.micro)
                .foregroundStyle(KinemaTheme.secondaryText.opacity(0.6))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .opacity(0.48)
    }

    @ViewBuilder
    private var activeSlot: some View {
        if let next = feed.nextEpisode {
            activeEpisodeRow(next)
                .id(next.id)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private func activeEpisodeRow(_ episode: CatalogEntry) -> some View {
        let hasLocal = PlaybillLibraryResolver.hasLinkedMedia(for: episode.id)

        return HStack(alignment: .center, spacing: 12) {
            PlaybillPosterThumb(path: episode.posterPath, kind: .episode)
                .frame(width: 64, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(KinemaTheme.brass.opacity(0.35), lineWidth: 0.8)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text("UP NEXT")
                    .font(KinemaType.eyebrow)
                    .tracking(1.4)
                    .foregroundStyle(KinemaTheme.brass)
                Text(episodeCode(episode))
                    .font(KinemaType.labelStrong)
                    .foregroundStyle(KinemaTheme.paper)
                if let name = episode.subtitle, !name.isEmpty {
                    Text(name)
                        .font(KinemaType.metadata)
                        .foregroundStyle(KinemaTheme.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                if hasLocal {
                    PlaybillTimelineIconButton(
                        systemName: "play.fill",
                        tint: accent,
                        accessibilityLabel: KinemaCopy.playbillPlayInKinema
                    ) {
                        playShowEntry(episode, viewModel: viewModel)
                    }
                }

                PlaybillTimelineIconButton(
                    systemName: "checkmark",
                    tint: KinemaTheme.brass,
                    accessibilityLabel: KinemaCopy.playbillStampWatched
                ) {
                    requestStamp(episode)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        #if os(iOS)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button { requestStamp(episode) } label: {
                Label(KinemaCopy.playbillStampWatched, systemImage: "checkmark")
            }
            .tint(KinemaTheme.brass)
        }
        #endif
    }

    private var emptyReelHint: some View {
        Label(
            feed.hasEpisodeMetadata ? "Start the series to fill your reel." : "Episode data is not saved yet. Connect once to prepare this series for offline use.",
            systemImage: feed.hasEpisodeMetadata ? "play.circle" : "wifi.slash"
        )
        .font(KinemaType.metadata)
        .foregroundStyle(KinemaTheme.secondaryText)
        .padding(14)
    }

    private func requestStamp(_ episode: CatalogEntry) {
        guard let season = episode.seasonNumber,
              let episodeNumber = episode.episodeNumber else { return }

        let prior = PlaybillShowProgress.priorUnwatchedEpisodes(
            for: feed.show.id,
            upToSeason: season,
            upToEpisode: episodeNumber
        )
        if prior.isEmpty {
            commitStamp(episode, includePrior: false, priorCount: 0)
        } else {
            catchUpRequest = PlaybillCatchUpRequest(episode: episode, priorCount: prior.count)
        }
    }

    private func commitStamp(_ episode: CatalogEntry, includePrior: Bool, priorCount: Int) {
        guard let season = episode.seasonNumber,
              let episodeNumber = episode.episodeNumber else { return }

        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif

        _ = PlaybillStore.upsertCatalog(episode)

        let priorRefs = includePrior
            ? PlaybillShowProgress.priorUnwatchedEpisodes(
                for: feed.show.id,
                upToSeason: season,
                upToEpisode: episodeNumber
            )
            : []

        var watched = PlaybillShowProgress.watchedEpisodeIDs(for: feed.show.id)
        for ref in priorRefs { watched.insert(ref.episodeID) }
        watched.insert(episode.id)

        let stampedCount = max(1, includePrior ? priorCount + 1 : 1)
        let instantNext = PlaybillShowProgress.peekNextEpisode(for: feed.show.id, watched: watched)
        if let instantNext {
            _ = PlaybillStore.upsertCatalog(instantNext)
        }

        let stamped = PlaybillFeedEpisode(entry: episode, watchedAt: Date())
        withAnimation(.easeOut(duration: 0.22)) {
            feed = PlaybillShowFeed(
                show: feed.show,
                recentWatched: [stamped] + feed.recentWatched,
                nextEpisode: instantNext,
                missedCount: max(0, feed.missedCount - stampedCount),
                hasEpisodeMetadata: feed.hasEpisodeMetadata
            )
        }

        Task(priority: .utility) {
            PlaybillShowProgress.markEpisodeWatched(
                showTargetID: feed.show.id,
                season: season,
                episode: episodeNumber,
                includePriorUnwatched: includePrior
            )
        }
    }

    private func episodeCode(_ entry: CatalogEntry) -> String {
        if let s = entry.seasonNumber, let e = entry.episodeNumber {
            return String(format: "S%02dE%02d", s, e)
        }
        return entry.displayTitle
    }
}

private struct PlaybillCatchUpRequest: Identifiable {
    let id = UUID()
    let episode: CatalogEntry
    let priorCount: Int
}

struct PlaybillTimelineIconButton: View {
    let systemName: String
    let tint: Color
    let accessibilityLabel: String
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.14), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
        .accessibilityLabel(accessibilityLabel)
        #if os(macOS)
        .help(accessibilityLabel)
        #endif
    }
}

struct PlaybillTimelineSimpleRow: View {
    let row: PlaybillTimelineRow
    let accent: Color
    var isWatched: Bool = false
    let onTap: () -> Void
    let onPlay: (() -> Void)?

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                PlaybillPosterThumb(path: row.entry.posterPath, kind: row.entry.kind)
                    .frame(width: 48, height: row.entry.kind == .movie ? 72 : 48)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .opacity(isWatched ? 0.5 : 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text(row.entry.displayTitle)
                        .font(KinemaType.posterTitle)
                        .foregroundStyle(KinemaTheme.paper.opacity(isWatched ? 0.55 : 1))
                        .lineLimit(2)
                    Text(row.subtitle)
                        .font(KinemaType.metadata)
                        .foregroundStyle(KinemaTheme.secondaryText.opacity(isWatched ? 0.5 : 0.85))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if let onPlay, PlaybillLibraryResolver.hasLinkedMedia(for: row.entry.id) {
                    PlaybillTimelineIconButton(
                        systemName: "play.fill",
                        tint: accent,
                        accessibilityLabel: KinemaCopy.playbillPlayInKinema,
                        action: onPlay
                    )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
        .buttonStyle(.plain)
        .opacity(isWatched ? 0.52 : 1)
    }
}

@MainActor
func playShowEntry(_ entry: CatalogEntry, viewModel: PlayerViewModel) {
    guard let media = PlaybillLibraryResolver.preferredPlayMedia(for: entry.id) else {
        viewModel.showOSD(KinemaCopy.playbillNoLocalFile)
        return
    }
    guard !viewModel.isOpeningMedia else { return }
    MediaWatchCoordinator.applyPlaybillProgress(to: media.url, targetID: entry.id)
    let selected = MediaItem(url: media.url, title: media.title)
    Task {
        await viewModel.openItems([selected], startingAt: selected, audioOnly: false)
    }
}

extension PlaybillTimelineSection {
    func removingItem(id: String) -> PlaybillTimelineSection? {
        let filtered = items.filter { $0.id != id }
        guard filtered.count != items.count else { return self }
        guard !filtered.isEmpty else { return nil }
        return PlaybillTimelineSection(
            id: self.id,
            title: title,
            subtitle: subtitle,
            kind: kind,
            items: filtered
        )
    }
}
