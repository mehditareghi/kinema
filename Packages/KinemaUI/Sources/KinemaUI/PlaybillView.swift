import SwiftUI
import KinemaPlaybill
import KinemaCore
import KinemaMedia
#if os(iOS) || os(macOS)
import UniformTypeIdentifiers
#endif
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import UIKit
#endif

enum PlaybillSection: String, CaseIterable, Identifiable {
    case timeline
    case diary
    case lists
    case search
    case stats

    var id: String { rawValue }

    var title: String {
        switch self {
        case .timeline: return KinemaCopy.playbillTimeline
        case .diary: return "My Playbill"
        case .lists: return KinemaCopy.playbillLists
        case .search: return KinemaCopy.playbillSearch
        case .stats: return "My Reel"
        }
    }

    var subtitle: String {
        switch self {
        case .timeline: return "What comes next, with your viewing history just behind the playhead."
        case .diary: return "Everything you follow, grouped by where it stands—not by individual episode."
        case .lists: return "Watchlists and collections, made for choosing what comes next."
        case .search: return "Find a film or series and bring it into your Playbill."
        case .stats: return "The story your viewing leaves behind."
        }
    }

    var icon: String {
        switch self {
        case .timeline: return "play.fill"
        case .diary: return "rectangle.stack.fill"
        case .lists: return "list.bullet.rectangle"
        case .search: return "magnifyingglass"
        case .stats: return "film.fill"
        }
    }
}


enum PlaybillRoute: Hashable {
    case title(CatalogEntry, UUID?)
    case show(CatalogEntry)
    case list(UUID)
}

extension TrackedShowStatus {
    var label: String {
        switch self {
        case .watching: return "Watching"
        case .planToWatch: return "Watch later"
        case .waiting: return "Waiting for more"
        case .completed: return "Completed"
        case .dropped: return "Dropped"
        }
    }

    var icon: String {
        switch self {
        case .watching: return "play.circle.fill"
        case .planToWatch: return "bookmark.fill"
        case .waiting: return "clock.badge.checkmark.fill"
        case .completed: return "checkmark.circle.fill"
        case .dropped: return "minus.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .watching: return KinemaTheme.accent
        case .planToWatch: return KinemaTheme.brass
        case .waiting: return .blue
        case .completed: return .green
        case .dropped: return KinemaTheme.secondaryText
        }
    }
}

public struct PlaybillView: View {
    @Bindable var viewModel: PlayerViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var section: PlaybillSection = .timeline
    @State private var apiKey = PlaybillPreferencesStore.tmdbAPIKey
    @State private var configured = PlaybillPreferencesStore.isConfigured
    @State private var connectivity = PlaybillConnectivity.shared
    @State private var pendingIdentificationCount = 0
    @State private var statusToken: UUID?

    private var accent: Color { KinemaTheme.accent }

    public init(viewModel: PlayerViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ZStack {
            KinemaBackdrop()
            content
            if let prompt = viewModel.playbillMatchPrompt {
                PlaybillMatchOverlay(
                    prompt: prompt,
                    accent: accent,
                    onConfirm: { viewModel.confirmPlaybillMatch($0) },
                    onSkip: { viewModel.skipPlaybillMatch() }
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .zIndex(10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-KinemaUITestMyReel") {
                section = .stats
            }
            #endif
            refreshConfigured()
            refreshOfflineStatus()
            statusToken = EventBus.shared.subscribe { event in
                if case .playbillUpdated = event { refreshOfflineStatus() }
            }
            if connectivity.isOnline {
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    await PendingWatchResolver.retryAll()
                }
            }
        }
        .onDisappear {
            if let statusToken { EventBus.shared.unsubscribe(statusToken) }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            masthead
            if !connectivity.isOnline || pendingIdentificationCount > 0 || !configured {
                offlineStatusStrip
            }
            sectionPicker
            pageContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationDestination(for: PlaybillRoute.self) { route in
            destination(for: route)
        }
    }

    private func refreshConfigured() {
        configured = PlaybillPreferencesStore.isConfigured
        apiKey = PlaybillPreferencesStore.tmdbAPIKey
    }

    private func refreshOfflineStatus() {
        pendingIdentificationCount = PlaybillStore.pendingWatchResolutions().count
    }

    private var offlineStatusStrip: some View {
        HStack(spacing: 9) {
            Image(systemName: !connectivity.isOnline ? "wifi.slash" : (pendingIdentificationCount > 0 ? "exclamationmark.arrow.triangle.2.circlepath" : "key"))
                .foregroundStyle(!connectivity.isOnline ? KinemaTheme.brass : KinemaTheme.secondaryText)
            Text(statusMessage)
                .font(KinemaType.metadata)
                .foregroundStyle(KinemaTheme.secondaryText)
                .lineLimit(2)
            Spacer(minLength: 8)
            if connectivity.isOnline && pendingIdentificationCount > 0 {
                Button("Retry") { Task { await PendingWatchResolver.retryAll() } }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else if !configured {
                Button("Set up") { viewModel.openPlaybillSettings() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, pagePadding)
        .padding(.vertical, 9)
        .background(KinemaTheme.brass.opacity(0.07))
        .overlay(alignment: .bottom) {
            Rectangle().fill(KinemaTheme.hairline.opacity(0.55)).frame(height: 0.6)
        }
    }

    private var statusMessage: String {
        if !connectivity.isOnline {
            return pendingIdentificationCount > 0
                ? "Offline · saved data remains available and \(pendingIdentificationCount) watch\(pendingIdentificationCount == 1 ? "" : "es") will be identified later."
                : "Offline · showing saved Playbill data. Watching and progress still work."
        }
        if pendingIdentificationCount > 0 {
            return "\(pendingIdentificationCount) saved watch\(pendingIdentificationCount == 1 ? " needs" : "es need") title identification."
        }
        return "Add a TMDB key to discover and refresh titles. Saved watching data remains available."
    }

    private var masthead: some View {
        HStack(alignment: .bottom, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "ticket.fill")
                        .foregroundStyle(KinemaTheme.brass)
                        .rotationEffect(.degrees(-12))
                    Text("PLAYBILL")
                        .font(KinemaType.eyebrow)
                        .tracking(2.4)
                        .foregroundStyle(KinemaTheme.brass)
                }
                Text(section.title)
                    .font(KinemaType.pageTitle)
                    .foregroundStyle(KinemaTheme.paper)
                    .contentTransition(.numericText())
                Text(section.subtitle)
                    .font(KinemaType.label)
                    .foregroundStyle(KinemaTheme.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            Text("YOUR WATCHING LIFE")
                .font(KinemaType.eyebrow)
                .tracking(1.8)
                .foregroundStyle(KinemaTheme.secondaryText.opacity(0.7))
                .padding(.bottom, 5)
        }
        .padding(.horizontal, pagePadding)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .background(KinemaTheme.cardBackground.opacity(0.34))
        .overlay(alignment: .bottom) {
            Rectangle().fill(KinemaTheme.hairline.opacity(0.75)).frame(height: 0.6)
        }
    }

    private var sectionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(PlaybillSection.allCases) { item in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            section = item
                        }
                    } label: {
                        VStack(spacing: 8) {
                            Label(item.title, systemImage: item.icon)
                                .font(section == item ? KinemaType.labelStrong : KinemaType.label)
                                .foregroundStyle(section == item ? KinemaTheme.paper : KinemaTheme.secondaryText)
                                .padding(.horizontal, 12)
                                .frame(height: 38)
                            Rectangle()
                                .fill(section == item ? accent : Color.clear)
                                .frame(height: 2)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(section == item ? .isSelected : [])
                }
            }
            .padding(.horizontal, pagePadding)
        }
        .background(KinemaTheme.cardBackground.opacity(0.18))
    }

    @ViewBuilder
    private var pageContent: some View {
        Group {
            if section == .timeline {
                PlaybillTimelineTab(viewModel: viewModel)
            } else {
                ScrollView {
                    sectionContent
                        .padding(.horizontal, pagePadding)
                        .padding(.top, 24)
                        .padding(.bottom, 36)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .id(section)
        .transition(.opacity.combined(with: .move(edge: .trailing)))
        .animation(.easeInOut(duration: 0.2), value: section)
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch section {
        case .timeline: EmptyView()
        case .diary: PlaybillMyPlaybillProfileSection(viewModel: viewModel)
        case .lists: PlaybillListsSection(viewModel: viewModel, horizontalSizeClass: horizontalSizeClass)
        case .search: PlaybillSearchSection(viewModel: viewModel)
        case .stats: PlaybillStatsSection()
        }
    }

    @ViewBuilder
    private func destination(for route: PlaybillRoute) -> some View {
        switch route {
        case let .show(show):
            PlaybillShowDetailView(show: show, viewModel: viewModel)
        case let .title(entry, activityID):
            PlaybillTitleDetailView(
                item: PlaybillDiaryItem(
                    activity: activityID.flatMap(PlaybillStore.activity(id:))
                        ?? WatchActivity(targetID: entry.id, source: .manual),
                    entry: entry
                ),
                viewModel: viewModel
            )
        case let .list(id):
            if let list = PlaybillStore.list(id: id) {
                PlaybillListDetailView(list: list, viewModel: viewModel, horizontalSizeClass: horizontalSizeClass)
            } else {
                ContentUnavailableView("List unavailable", systemImage: "list.bullet.rectangle")
            }
        }
    }

    private var pagePadding: CGFloat {
        horizontalSizeClass == .compact ? 18 : 28
    }
}

struct PlaybillTimelineTab: View {
    @Bindable var viewModel: PlayerViewModel
    @State private var showFeeds: [PlaybillShowFeed] = []
    @State private var auxSections: [PlaybillTimelineSection] = []
    @State private var isLoading = true
    @State private var playbillToken: UUID?
    @State private var feedSyncTask: Task<Void, Never>?
    @State private var auxSyncTask: Task<Void, Never>?
    @State private var didSetInitialPosition = false

    private var accent: Color { KinemaTheme.accent }
    private var isEmpty: Bool {
        !isLoading && showFeeds.isEmpty && auxSections.isEmpty
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if isLoading && showFeeds.isEmpty {
                        loadingProgramme
                    } else if isEmpty {
                        emptyTimeline
                    } else {
                        PlaybillProgrammeTimeline(
                            feeds: showFeeds,
                            history: auxSections
                                .filter { $0.kind == .history }
                                .flatMap(\.items),
                            viewModel: viewModel
                        )

                        ForEach(auxSections.filter { $0.kind == .continueWatching }) { section in
                            auxSectionBlock(section)
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 22)
                .padding(.bottom, 44)
            }
            .scrollContentBackground(.hidden)
            .onChange(of: isLoading) { wasLoading, loading in
                guard wasLoading, !loading, !didSetInitialPosition else { return }
                didSetInitialPosition = true
                DispatchQueue.main.async {
                    proxy.scrollTo(PlaybillProgrammeTimeline.nowAnchor, anchor: .top)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            await loadInitialFeeds()
        }
        .onAppear {
            playbillToken = EventBus.shared.subscribe { event in
                switch event {
                case .playbillUpdated:
                    syncShowFeedsLightweight()
                case .watchProgressUpdated:
                    reloadAuxSectionsDebounced()
                default:
                    break
                }
            }
        }
        .onDisappear {
            feedSyncTask?.cancel()
            auxSyncTask?.cancel()
            if let playbillToken { EventBus.shared.unsubscribe(playbillToken) }
        }
    }

    private var loadingProgramme: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(KinemaCopy.playbillLoadingProgramme)
                .font(KinemaType.metadata)
                .foregroundStyle(KinemaTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }

    private var emptyTimeline: some View {
        VStack(spacing: 14) {
            Text(KinemaCopy.playbillTimelineEmptyTitle)
                .font(KinemaType.cardTitle)
                .foregroundStyle(KinemaTheme.paper)
            Text(KinemaCopy.playbillTimelineEmptyMessage)
                .font(KinemaType.label)
                .foregroundStyle(KinemaTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func auxSectionBlock(_ section: PlaybillTimelineSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            KinemaSectionTitle(section.title, systemImage: icon(for: section.kind))
            if let subtitle = section.subtitle {
                Text(subtitle)
                    .font(KinemaType.metadata)
                    .foregroundStyle(KinemaTheme.secondaryText)
            }

            VStack(spacing: 0) {
                ForEach(section.items) { row in
                    PlaybillTimelineSimpleRow(
                        row: row,
                        accent: accent,
                        isWatched: section.kind == .history,
                        onTap: { openAuxRow(row, in: section) },
                        onPlay: playAction(for: row, in: section)
                    )
                    if row.id != section.items.last?.id {
                        Divider().padding(.leading, 62)
                    }
                }
            }
            .background(KinemaTheme.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(KinemaTheme.hairline.opacity(0.72), lineWidth: 0.6)
            }
        }
    }

    private func icon(for kind: PlaybillTimelineSectionKind) -> String {
        switch kind {
        case .catchUp, .upNext: return "play.circle"
        case .continueWatching: return "pause.circle"
        case .history: return "clock.arrow.circlepath"
        }
    }

    private func playAction(for row: PlaybillTimelineRow, in section: PlaybillTimelineSection) -> (() -> Void)? {
        guard section.kind == .continueWatching || section.kind == .history else { return nil }
        guard PlaybillLibraryResolver.hasLinkedMedia(for: row.entry.id) else { return nil }
        return { playShowEntry(row.entry, viewModel: viewModel) }
    }

    private func openAuxRow(_ row: PlaybillTimelineRow, in section: PlaybillTimelineSection) {
        if section.kind == .continueWatching {
            playShowEntry(row.entry, viewModel: viewModel)
        }
    }

    private func loadInitialFeeds() async {
        // Paint Playbill chrome first — never do store/TMDB work before the first frame.
        isLoading = true
        await Task.yield()

        let feeds = PlaybillShowFeedBuilder.buildLightweight()
        let aux = PlaybillTimelineBuilder.buildContinueAndHistory(limitHistory: 40)
        showFeeds = feeds
        auxSections = aux
        isLoading = false

        // Discover all matching episode files in one library walk. This makes the
        // Up Next play action deterministic even when a file has never been opened.
        await Task.yield()
        PlaybillLibraryResolver.indexLibraryMedia(
            forShowTargetIDs: feeds.map { $0.show.id }
        )
        showFeeds = PlaybillShowFeedBuilder.buildLightweight()

        // Single local write for false Completed — no per-show reconcile / TMDB.
        await Task.yield()
        if PlaybillStore.demoteIncompleteCompletedShows(notify: false) > 0 {
            showFeeds = PlaybillShowFeedBuilder.buildLightweight()
        }
    }

    private func reloadFeeds(reindexLibrary: Bool = false) {
        isLoading = showFeeds.isEmpty
        Task {
            if reindexLibrary {
                let lightweight = PlaybillShowFeedBuilder.buildLightweight()
                let auxiliary = PlaybillTimelineBuilder.buildContinueAndHistory()
                await MainActor.run {
                    showFeeds = lightweight
                    auxSections = auxiliary
                    isLoading = false
                }
                await PlaybillStore.reindexTrackedShowsLibraryMediaAsync()
            }
            // Never call build() here — that warms TMDB for every show and freezes the UI.
            let feeds = PlaybillShowFeedBuilder.buildLightweight()
            let auxiliary = PlaybillTimelineBuilder.buildContinueAndHistory()
            await MainActor.run {
                showFeeds = feeds
                auxSections = auxiliary
                isLoading = false
            }
        }
    }

    private func syncShowFeedsLightweight() {
        feedSyncTask?.cancel()
        feedSyncTask = Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            let refreshed = PlaybillShowFeedBuilder.buildLightweight()
            guard !Task.isCancelled else { return }
            await MainActor.run {
                showFeeds = refreshed
                isLoading = false
            }
        }
    }

    private func reloadAuxSectionsDebounced() {
        auxSyncTask?.cancel()
        auxSyncTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            let auxiliary = PlaybillTimelineBuilder.buildContinueAndHistory()
            guard !Task.isCancelled else { return }
            await MainActor.run {
                auxSections = auxiliary
            }
        }
    }

    private func syncShowFeeds() {
        feedSyncTask?.cancel()
        feedSyncTask = Task {
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            let feeds = PlaybillShowFeedBuilder.buildLightweight()
            guard !Task.isCancelled else { return }
            await MainActor.run {
                showFeeds = feeds
                isLoading = false
            }
        }
    }

    private func reloadAuxSections() {
        auxSections = PlaybillTimelineBuilder.buildContinueAndHistory()
    }
}

struct PlaybillListsSection: View {
    @Bindable var viewModel: PlayerViewModel
    var horizontalSizeClass: UserInterfaceSizeClass?
    @State private var lists: [PlaybillList] = []
    @State private var watchLaterEntries: [PlaybillListEntry] = []
    @State private var refreshID = UUID()
    @State private var playbillToken: UUID?
    @State private var showCreateList = false
    @State private var newListName = ""

    private var accent: Color { KinemaTheme.accent }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Choose with intention")
                        .font(KinemaType.cardTitle)
                        .foregroundStyle(KinemaTheme.paper)
                    Text("Watch Later is your queue. Lists are smaller collections for a mood, person, or occasion.")
                        .font(KinemaType.metadata)
                        .foregroundStyle(KinemaTheme.secondaryText)
                }
                Spacer()
                Button {
                    newListName = ""
                    showCreateList = true
                } label: {
                    Label(KinemaCopy.playbillCreateList, systemImage: "plus")
                        .font(KinemaType.controlLabel)
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
            }

            if !watchLaterEntries.isEmpty {
                watchLaterQueue
            }

            if lists.isEmpty && watchLaterEntries.isEmpty {
                emptyLists
            } else if !lists.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    KinemaSectionTitle("Your lists", systemImage: "square.stack.3d.up")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260, maximum: 420), spacing: 12)], spacing: 12) {
                    ForEach(lists) { list in
                        NavigationLink(value: PlaybillRoute.list(list.id)) {
                                PlaybillCollectionCard(list: list, accent: accent)
                        }
                        .buttonStyle(.plain)
                    }
                    }
                }
            }
        }
        .id(refreshID)
        .onAppear {
            reload()
            playbillToken = EventBus.shared.subscribe { event in
                if case .playbillUpdated = event { reload() }
            }
        }
        .onDisappear {
            if let playbillToken { EventBus.shared.unsubscribe(playbillToken) }
        }
        .sheet(isPresented: $showCreateList) {
            NavigationStack {
                Form {
                    TextField(KinemaCopy.playbillListNamePlaceholder, text: $newListName)
                }
                .navigationTitle(KinemaCopy.playbillCreateList)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(KinemaCopy.cancel) { showCreateList = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(KinemaCopy.save) {
                            let trimmed = newListName.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            _ = PlaybillStore.createList(name: trimmed)
                            showCreateList = false
                            reload()
                        }
                        .disabled(newListName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            #if os(macOS)
            .frame(minWidth: 300)
            #endif
        }
    }

    private var watchLaterQueue: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                KinemaSectionTitle("Watch later", systemImage: "bookmark.fill")
                Spacer()
                if let watchlist = PlaybillStore.lists().first(where: { $0.systemKind == .watchlist }) {
                    NavigationLink(value: PlaybillRoute.list(watchlist.id)) {
                        Text("See all \(watchLaterEntries.count)")
                            .font(KinemaType.controlLabel)
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("Your decision queue, ordered by what you added most recently.")
                .font(KinemaType.metadata)
                .foregroundStyle(KinemaTheme.secondaryText)

            VStack(spacing: 0) {
                ForEach(Array(watchLaterEntries.prefix(5))) { item in
                    NavigationLink(value: route(for: item.entry)) {
                        PlaybillQueueRow(entry: item.entry, addedAt: item.item.addedAt)
                    }
                    .buttonStyle(.plain)
                    if item.id != watchLaterEntries.prefix(5).last?.id {
                        Divider().padding(.leading, 84).overlay(KinemaTheme.hairline.opacity(0.4))
                    }
                }
            }
            .background(KinemaTheme.cardBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(KinemaTheme.hairline.opacity(0.62), lineWidth: 0.6)
            }
        }
    }

    private var emptyLists: some View {
        VStack(spacing: 14) {
            Text(KinemaCopy.playbillListsEmptyTitle)
                .font(KinemaType.cardTitle)
                .foregroundStyle(KinemaTheme.paper)
            Text(KinemaCopy.playbillListsEmptyMessage)
                .font(KinemaType.label)
                .foregroundStyle(KinemaTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
    }

    private func reload() {
        let allLists = PlaybillStore.lists()
        lists = allLists.filter { $0.systemKind == nil }
        if let watchlist = allLists.first(where: { $0.systemKind == .watchlist }) {
            watchLaterEntries = PlaybillStore.listEntries(for: watchlist.id)
        } else {
            watchLaterEntries = []
        }
        refreshID = UUID()
    }

    private func route(for entry: CatalogEntry) -> PlaybillRoute {
        entry.kind == .tvShow ? .show(entry) : .title(entry, nil)
    }
}

struct PlaybillQueueRow: View {
    let entry: CatalogEntry
    let addedAt: Date

    var body: some View {
        HStack(spacing: 12) {
            PlaybillPosterThumb(path: entry.backdropPath ?? entry.posterPath, kind: entry.kind, aspectOverride: 16/9)
                .frame(width: 64, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(KinemaType.labelStrong)
                    .foregroundStyle(KinemaTheme.paper)
                    .lineLimit(1)
                Text("\(entry.kind == .movie ? "Film" : "Series") · added \(addedAt.formatted(.relative(presentation: .named)))")
                    .font(KinemaType.metadata)
                    .foregroundStyle(KinemaTheme.secondaryText)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(KinemaTheme.secondaryText.opacity(0.55))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }
}

struct PlaybillCollectionCard: View {
    let list: PlaybillList
    let accent: Color

    private var entries: [PlaybillListEntry] { PlaybillStore.listEntries(for: list.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: -16) {
                ForEach(Array(entries.prefix(3).enumerated()), id: \.element.id) { index, item in
                    PlaybillPosterThumb(path: item.entry.backdropPath ?? item.entry.posterPath, kind: item.entry.kind, aspectOverride: 16/9)
                        .frame(width: 76, height: 48)
                        .overlay {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(KinemaTheme.cardBackground, lineWidth: 2)
                        }
                        .zIndex(Double(3 - index))
                }
                if entries.isEmpty {
                    Image(systemName: "plus")
                        .foregroundStyle(KinemaTheme.secondaryText)
                        .frame(width: 76, height: 48)
                        .background(KinemaTheme.raisedBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(KinemaTheme.secondaryText)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(list.name)
                    .font(KinemaType.cardTitle)
                    .foregroundStyle(KinemaTheme.paper)
                Text("\(entries.count) title\(entries.count == 1 ? "" : "s") · updated \(list.updatedAt.formatted(.relative(presentation: .named)))")
                    .font(KinemaType.metadata)
                    .foregroundStyle(KinemaTheme.secondaryText)
            }
        }
        .padding(14)
        .background(KinemaTheme.cardBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(KinemaTheme.hairline.opacity(0.62), lineWidth: 0.6)
        }
    }
}

struct PlaybillListRow: View {
    let list: PlaybillList
    let accent: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: list.systemKind == .watchlist ? "bookmark.fill" : list.systemKind == .tracking ? "tv.fill" : "list.bullet")
                .font(.system(size: 20))
                .foregroundStyle(accent)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(list.name)
                    .font(KinemaType.posterTitle)
                    .foregroundStyle(KinemaTheme.paper)
                Text("\(PlaybillStore.listEntries(for: list.id).count) titles")
                    .font(KinemaType.metadata)
                    .foregroundStyle(KinemaTheme.secondaryText)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .foregroundStyle(KinemaTheme.secondaryText)
        }
        .padding(14)
        .background(KinemaTheme.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(KinemaTheme.hairline.opacity(0.78), lineWidth: 0.6)
        }
    }
}

struct PlaybillListDetailView: View {
    let list: PlaybillList
    @Bindable var viewModel: PlayerViewModel
    var horizontalSizeClass: UserInterfaceSizeClass?
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [PlaybillListEntry] = []
    @State private var filter: PlaybillListFilter = .all
    @State private var sort: PlaybillListSort = .recentlyAdded
    @State private var showRename = false
    @State private var renamedListName = ""

    private var accent: Color { KinemaTheme.accent }

    var body: some View {
        ZStack {
            KinemaBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    listControls
                    if displayedEntries.isEmpty {
                    Text(KinemaCopy.playbillListsEmptyMessage)
                        .font(KinemaType.label)
                        .foregroundStyle(KinemaTheme.secondaryText)
                        .padding(.vertical, 40)
                        .frame(maxWidth: .infinity)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(displayedEntries) { entry in
                            NavigationLink(value: route(for: entry)) {
                                    PlaybillListTitleRow(entry: entry.entry, addedAt: entry.item.addedAt)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    PlaybillStore.removeFromList(listID: list.id, targetID: entry.entry.id)
                                    reload()
                                } label: {
                                    Label(KinemaCopy.playbillRemoveFromList, systemImage: "trash")
                                }
                            }
                                if entry.id != displayedEntries.last?.id {
                                    Divider().padding(.leading, 90).overlay(KinemaTheme.hairline.opacity(0.4))
                                }
                            }
                        }
                        .background(KinemaTheme.cardBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(KinemaTheme.hairline.opacity(0.62), lineWidth: 0.6)
                        }
                    }
                }
                .padding(24)
            }
        }
        .navigationTitle(list.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if !list.isSystem {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            renamedListName = list.name
                            showRename = true
                        } label: {
                            Label("Rename list", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            PlaybillStore.deleteList(id: list.id)
                            dismiss()
                        } label: {
                            Label("Delete list", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .onAppear { reload() }
        .sheet(isPresented: $showRename) {
            NavigationStack {
                Form {
                    TextField("List name", text: $renamedListName)
                }
                .navigationTitle("Rename list")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(KinemaCopy.cancel) { showRename = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(KinemaCopy.save) {
                            let trimmed = renamedListName.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            PlaybillStore.renameList(id: list.id, name: trimmed)
                            showRename = false
                        }
                        .disabled(renamedListName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            #if os(macOS)
            .frame(minWidth: 320)
            #endif
        }
    }

    private var displayedEntries: [PlaybillListEntry] {
        let filtered = entries.filter { item in
            switch filter {
            case .all: return true
            case .films: return item.entry.kind == .movie
            case .series: return item.entry.kind == .tvShow
            }
        }
        switch sort {
        case .recentlyAdded: return filtered.sorted { $0.item.addedAt > $1.item.addedAt }
        case .title: return filtered.sorted { $0.entry.title.localizedStandardCompare($1.entry.title) == .orderedAscending }
        case .year: return filtered.sorted { ($0.entry.year ?? 0) > ($1.entry.year ?? 0) }
        }
    }

    private var listControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(entries.count) title\(entries.count == 1 ? "" : "s")")
                    .font(KinemaType.metadataStrong)
                    .foregroundStyle(KinemaTheme.secondaryText)
                Spacer()
                Menu {
                    ForEach(PlaybillListSort.allCases) { option in
                        Button {
                            sort = option
                        } label: {
                            Label(option.title, systemImage: sort == option ? "checkmark" : option.icon)
                        }
                    }
                } label: {
                    Label(sort.title, systemImage: "arrow.up.arrow.down")
                        .font(KinemaType.controlLabel)
                }
                .buttonStyle(.bordered)
            }

            Picker("Filter", selection: $filter) {
                ForEach(PlaybillListFilter.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func route(for entry: PlaybillListEntry) -> PlaybillRoute {
        if entry.entry.kind == .tvShow {
            return .show(entry.entry)
        }
        return .title(entry.entry, nil)
    }

    private func reload() {
        entries = PlaybillStore.listEntries(for: list.id)
    }
}

private enum PlaybillListFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case films = "Films"
    case series = "Series"
    var id: String { rawValue }
}

private enum PlaybillListSort: String, CaseIterable, Identifiable {
    case recentlyAdded
    case title
    case year
    var id: String { rawValue }
    var title: String {
        switch self {
        case .recentlyAdded: return "Recently added"
        case .title: return "Title"
        case .year: return "Release year"
        }
    }
    var icon: String {
        switch self {
        case .recentlyAdded: return "clock"
        case .title: return "textformat"
        case .year: return "calendar"
        }
    }
}

private struct PlaybillListTitleRow: View {
    let entry: CatalogEntry
    let addedAt: Date

    var body: some View {
        HStack(spacing: 12) {
            PlaybillPosterThumb(path: entry.backdropPath ?? entry.posterPath, kind: entry.kind, aspectOverride: 16/9)
                .frame(width: 68, height: 43)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .font(KinemaType.labelStrong)
                    .foregroundStyle(KinemaTheme.paper)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(entry.kind == .movie ? "Film" : "Series")
                    if let year = entry.year { Text("· \(year)") }
                    Text("· Added \(addedAt.formatted(date: .abbreviated, time: .omitted))")
                }
                .font(KinemaType.metadata)
                .foregroundStyle(KinemaTheme.secondaryText)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(KinemaTheme.secondaryText.opacity(0.55))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }
}

// MARK: - My Playbill

private func playbillWatchedEpisodesByShow(
    db: PlaybillDatabase,
    trackedShows: [TrackedShow],
    fullActivities: [WatchActivity]
) -> [String: [WatchActivity]] {
    let shows = trackedShows.compactMap { tracked -> CatalogEntry? in
        guard let show = db.catalog[tracked.targetID], show.kind == .tvShow else { return nil }
        return show
    }
    guard !shows.isEmpty else { return [:] }

    var showIDsByTMDBID: [Int: Set<String>] = [:]
    var showIDsByTitleKey: [String: Set<String>] = [:]
    for show in shows {
        showIDsByTMDBID[show.tmdbID, default: []].insert(show.id)
        let key = MediaSeriesOrganizer.showKey(forTitle: show.title)
        showIDsByTitleKey[key, default: []].insert(show.id)
    }

    var titleMatchCache: [String: Set<String>] = [:]
    func titleMatchedShowIDs(for episode: CatalogEntry) -> Set<String> {
        let episodeTitleKey = MediaSeriesOrganizer.showKey(forTitle: episode.title)
        if let cached = titleMatchCache[episodeTitleKey] { return cached }
        let matches = showIDsByTitleKey[episodeTitleKey] ?? []
        titleMatchCache[episodeTitleKey] = matches
        return matches
    }

    var grouped: [String: [WatchActivity]] = [:]
    for activity in fullActivities {
        guard let episode = db.catalog[activity.targetID], episode.kind == .episode else { continue }
        var showIDs = Set<String>()
        if let parentShowID = episode.parentShowID,
           db.catalog[parentShowID]?.kind == .tvShow {
            showIDs.insert(parentShowID)
        }
        for showID in showIDsByTMDBID[episode.tmdbID, default: []] {
            showIDs.insert(showID)
        }
        if showIDs.isEmpty, episode.parentShowID == nil, episode.tmdbID <= 0 {
            for showID in titleMatchedShowIDs(for: episode) {
                showIDs.insert(showID)
            }
        }
        for showID in showIDs {
            grouped[showID, default: []].append(activity)
        }
    }
    return grouped
}

struct PlaybillMyPlaybillProfileSection: View {
    @Bindable var viewModel: PlayerViewModel
    @State private var shelves: [MyPlaybillShelf] = []
    @State private var mediaKind: MyPlaybillMediaKind = .series
    @State private var sort: MyPlaybillSort = .recent
    @State private var pendingIdentifications: [PendingWatchResolution] = []
    @State private var playbillToken: UUID?

    private let columns = [GridItem(.adaptive(minimum: 320, maximum: 560), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !pendingIdentifications.isEmpty {
                pendingSection
                Divider().overlay(KinemaTheme.hairline.opacity(0.42))
            }
            header
            if visibleShelves.isEmpty {
                emptyState
            } else {
                ForEach(Array(visibleShelves.enumerated()), id: \.element.id) { index, shelf in
                    shelfSection(shelf)
                    if index < visibleShelves.count - 1 {
                        Divider().overlay(KinemaTheme.hairline.opacity(0.42))
                    }
                }
            }
        }
        .onAppear {
            reload()
            playbillToken = EventBus.shared.subscribe { event in
                switch event {
                case .playbillUpdated, .watchProgressUpdated: reload()
                default: break
                }
            }
        }
        .onDisappear {
            if let playbillToken { EventBus.shared.unsubscribe(playbillToken) }
        }
        .task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await refreshDerivedStates()
        }
    }

    private var visibleShelves: [MyPlaybillShelf] {
        shelves
            .filter { $0.kind.mediaKind == mediaKind && !$0.items.isEmpty }
            .map { MyPlaybillShelf(kind: $0.kind, items: sorted($0.items)) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    KinemaSectionTitle("Your titles", systemImage: "rectangle.stack.fill")
                    Text("What is active, saved, caught up, and finished—at title level.")
                        .font(KinemaType.metadata)
                        .foregroundStyle(KinemaTheme.secondaryText)
                }
                Spacer()
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(MyPlaybillSort.allCases) { option in
                            Label(option.label, systemImage: option.icon).tag(option)
                        }
                    }
                } label: {
                    Label(sort.label, systemImage: "arrow.up.arrow.down")
                        .font(KinemaType.metadataStrong)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Picker("Media", selection: $mediaKind) {
                ForEach(MyPlaybillMediaKind.allCases) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)
        }
    }

    private var pendingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundStyle(KinemaTheme.brass)
                Text("Needs Identification")
                    .font(KinemaType.cardTitle)
                    .foregroundStyle(KinemaTheme.paper)
                Spacer()
                Text("\(pendingIdentifications.count)")
                    .font(KinemaType.metadataBold)
                    .foregroundStyle(KinemaTheme.secondaryText)
            }
            Text("These watches are safely stored. Choose a match when available; removing one discards only this unresolved Playbill record.")
                .font(KinemaType.metadata)
                .foregroundStyle(KinemaTheme.secondaryText)

            VStack(spacing: 0) {
                ForEach(pendingIdentifications) { pending in
                    HStack(spacing: 12) {
                        Image(systemName: pending.parsedEpisode == nil ? "film" : "tv")
                            .foregroundStyle(KinemaTheme.brass)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pending.mediaTitle)
                                .font(KinemaType.labelStrong)
                                .foregroundStyle(KinemaTheme.paper)
                                .lineLimit(1)
                            Text(pending.lastError ?? "Watch saved locally")
                                .font(KinemaType.micro)
                                .foregroundStyle(KinemaTheme.secondaryText)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button("Identify") {
                            Task { _ = await PendingWatchResolver.retry(pending) }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        Button(role: .destructive) {
                            PlaybillStore.removePendingWatch(id: pending.id)
                            reload()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    if pending.id != pendingIdentifications.last?.id {
                        Divider().padding(.leading, 52).overlay(KinemaTheme.hairline.opacity(0.4))
                    }
                }
            }
            .background(KinemaTheme.cardBackground.opacity(0.64), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(KinemaTheme.brass.opacity(0.28), lineWidth: 0.7)
            }
        }
    }

    private func shelfSection(_ shelf: MyPlaybillShelf) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(shelf.kind.tint)
                    .frame(width: 4, height: 19)
                Image(systemName: shelf.kind.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(shelf.kind.tint)
                Text(shelf.kind.title)
                    .font(KinemaType.cardTitle)
                    .foregroundStyle(KinemaTheme.paper)
                Spacer()
                Text("\(shelf.items.count)")
                    .font(KinemaType.metadataBold)
                    .foregroundStyle(KinemaTheme.secondaryText)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(KinemaTheme.raisedBackground, in: Capsule())
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(shelf.items) { item in
                    titleCard(item, tint: shelf.kind.tint)
                }
            }
        }
    }

    private func titleCard(_ item: MyPlaybillItem, tint: Color) -> some View {
        NavigationLink(value: route(for: item.entry, activityID: item.activityID)) {
            HStack(spacing: 12) {
                PlaybillPosterThumb(path: item.entry.posterPath, kind: item.entry.kind, aspectOverride: 16/9)
                    .frame(width: 76, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(item.entry.title)
                            .font(KinemaType.labelStrong)
                            .foregroundStyle(KinemaTheme.paper)
                            .lineLimit(1)
                        if item.repeatCount > 1 {
                            PlaybillRepeatBadge(count: item.repeatCount, scale: .chip)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(KinemaTheme.secondaryText.opacity(0.5))
                    }
                    ProgressView(value: item.progress)
                        .progressViewStyle(.linear)
                        .tint(tint)
                        .scaleEffect(x: 1, y: 0.72, anchor: .center)
                    HStack(spacing: 6) {
                        Text(item.progressLabel)
                            .font(KinemaType.micro)
                            .foregroundStyle(KinemaTheme.secondaryText)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(item.lastActivityAt, style: .relative)
                            .font(KinemaType.micro)
                            .foregroundStyle(KinemaTheme.secondaryText.opacity(0.78))
                            .lineLimit(1)
                    }
                }
            }
            .padding(11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(KinemaTheme.cardBackground.opacity(0.64), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(KinemaTheme.hairline.opacity(0.52), lineWidth: 0.6)
        }
    }

    private func sorted(_ items: [MyPlaybillItem]) -> [MyPlaybillItem] {
        switch sort {
        case .recent:
            items.sorted { lhs, rhs in
                if lhs.lastActivityAt != rhs.lastActivityAt { return lhs.lastActivityAt > rhs.lastActivityAt }
                return lhs.entry.title.localizedCaseInsensitiveCompare(rhs.entry.title) == .orderedAscending
            }
        case .progress:
            items.sorted { lhs, rhs in
                if lhs.progress != rhs.progress { return lhs.progress > rhs.progress }
                return lhs.lastActivityAt > rhs.lastActivityAt
            }
        case .title:
            items.sorted { $0.entry.title.localizedCaseInsensitiveCompare($1.entry.title) == .orderedAscending }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            mediaKind == .series ? "No series yet" : "No films yet",
            systemImage: mediaKind == .series ? "tv" : "film",
            description: Text(mediaKind == .series
                ? "Track or save a series to see its automatic progress here."
                : "Save, start, or watch a film to build your film Playbill.")
        )
        .frame(maxWidth: .infinity, minHeight: 260)
    }

    private func route(for entry: CatalogEntry, activityID: UUID?) -> PlaybillRoute {
        entry.kind == .tvShow ? .show(entry) : .title(entry, activityID)
    }

    private func reload() {
        let db = PlaybillStore.rawDatabase()
        pendingIdentifications = db.pendingWatchResolutions.sorted { $0.createdAt > $1.createdAt }
        let full = db.activities.filter { $0.completion == .full }
        let watchedTargetIDs = Set(full.map(\.targetID))
        let trackedShows = db.trackedShows
        let episodeWatchesByShow = playbillWatchedEpisodesByShow(
            db: db,
            trackedShows: trackedShows,
            fullActivities: full
        )
        var activeRewatchByShow: [String: (episode: CatalogEntry, progress: TitlePlaybackProgress)] = [:]
        for (targetID, playback) in db.playbackProgress where playback.hasPartialResume {
            guard watchedTargetIDs.contains(targetID),
                  let episode = db.catalog[targetID],
                  episode.kind == .episode else { continue }
            let showTargetID = episode.parentShowID ?? CatalogEntry.showID(episode.tmdbID)
            guard db.catalog[showTargetID]?.kind == .tvShow else { continue }
            if let existing = activeRewatchByShow[showTargetID],
               existing.progress.updatedAt >= playback.updatedAt {
                continue
            }
            activeRewatchByShow[showTargetID] = (episode, playback)
        }
        var grouped: [MyPlaybillShelfKind: [MyPlaybillItem]] = [:]

        for tracked in trackedShows {
            guard let show = db.catalog[tracked.targetID], show.kind == .tvShow else { continue }
            let episodeWatches = episodeWatchesByShow[show.id, default: []]
            let distinctWatched = PlaybillShowProgress.watchedEpisodeIDs(for: show.id).count
            let latest = episodeWatches.max { $0.watchedAt < $1.watchedAt }
            let knownTotal = max(PlaybillStore.displayEpisodeTotal(for: show), distinctWatched)
            let kind = MyPlaybillShelfKind(status: tracked.status)
            let progress: Double
            var label: String

            switch tracked.status {
            case .watching:
                progress = knownTotal > 0 ? Double(distinctWatched) / Double(knownTotal) : 0
                label = knownTotal > 0 ? "\(distinctWatched) of \(knownTotal) episodes" : "\(distinctWatched) episodes watched"
            case .planToWatch:
                progress = 0
                label = "Not started"
            case .waiting:
                progress = 1
                label = "Caught up · \(distinctWatched) episodes"
            case .completed:
                progress = 1
                label = "All \(distinctWatched) episodes watched"
            case .dropped:
                progress = knownTotal > 0 ? Double(distinctWatched) / Double(knownTotal) : 0
                label = "Stopped after \(distinctWatched) episodes"
            }

            if let rewatch = activeRewatchByShow[show.id] {
                let season = rewatch.episode.seasonNumber ?? 0
                let episode = rewatch.episode.episodeNumber ?? 0
                let code = String(format: "S%02dE%02d", season, episode)
                let percent = Int((rewatch.progress.fraction * 100).rounded())
                label = "Rewatching \(code) · \(percent)%"
            }

            grouped[kind, default: []].append(MyPlaybillItem(
                entry: show,
                progress: min(max(progress, 0), 1),
                progressLabel: label,
                lastActivityAt: activeRewatchByShow[show.id]?.progress.updatedAt
                    ?? latest?.watchedAt
                    ?? tracked.trackedAt,
                activityID: latest?.id,
                repeatCount: PlaybillStore.seriesRepeatWatchCount(for: show.id)
            ))
        }

        if let watchlistID = db.lists.first(where: { $0.systemKind == .watchlist })?.id {
            for listItem in db.listItems where listItem.listID == watchlistID {
                guard let entry = db.catalog[listItem.targetID], entry.kind == .movie else { continue }
                grouped[.filmWatchLater, default: []].append(MyPlaybillItem(
                    entry: entry,
                    progress: 0,
                    progressLabel: "Not started",
                    lastActivityAt: listItem.addedAt,
                    activityID: nil,
                    repeatCount: 0
                ))
            }
        }

        let inProgressMovies = db.playbackProgress.compactMap { targetID, playback -> MyPlaybillItem? in
            guard playback.hasPartialResume,
                  !watchedTargetIDs.contains(targetID),
                  let entry = db.catalog[targetID], entry.kind == .movie else { return nil }
            return MyPlaybillItem(
                entry: entry,
                progress: playback.fraction,
                progressLabel: "\(Int((playback.fraction * 100).rounded()))% watched",
                lastActivityAt: playback.updatedAt,
                activityID: nil,
                repeatCount: 0
            )
        }
        grouped[.filmInProgress] = inProgressMovies
        let inProgressIDs = Set(inProgressMovies.map(\.entry.id))

        let watchedMovies = Dictionary(grouping: full.compactMap { activity -> PlaybillDiaryItem? in
            guard let entry = db.catalog[activity.targetID], entry.kind == .movie else { return nil }
            return PlaybillDiaryItem(activity: activity, entry: entry)
        }, by: { $0.entry.id })
        for (targetID, watches) in watchedMovies {
            guard let latest = watches.max(by: { $0.activity.watchedAt < $1.activity.watchedAt }) else { continue }
            let rewatchProgress = db.playbackProgress[targetID].flatMap { $0.hasPartialResume ? $0 : nil }
            let progressLabel = rewatchProgress.map {
                "Rewatching · \(Int(($0.fraction * 100).rounded()))%"
            } ?? "Watched"
            grouped[.filmWatched, default: []].append(MyPlaybillItem(
                entry: latest.entry,
                progress: 1,
                progressLabel: progressLabel,
                lastActivityAt: rewatchProgress?.updatedAt ?? latest.activity.watchedAt,
                activityID: latest.activity.id,
                repeatCount: watches.count
            ))
        }

        let watchedMovieIDs = Set(watchedMovies.keys)
        grouped[.filmWatchLater] = grouped[.filmWatchLater, default: []].filter {
            !inProgressIDs.contains($0.entry.id) && !watchedMovieIDs.contains($0.entry.id)
        }

        shelves = MyPlaybillShelfKind.allCases.map { MyPlaybillShelf(kind: $0, items: grouped[$0, default: []]) }
    }

    private func refreshDerivedStates() async {
        await Task.yield()
        if PlaybillStore.demoteIncompleteCompletedShows() > 0 {
            reload()
        }
    }
}

private enum MyPlaybillMediaKind: String, CaseIterable, Identifiable {
    case series
    case films
    var id: String { rawValue }
    var label: String { self == .series ? "Series" : "Films" }
}

private enum MyPlaybillSort: String, CaseIterable, Identifiable {
    case recent
    case progress
    case title
    var id: String { rawValue }
    var label: String {
        switch self {
        case .recent: "Recent"
        case .progress: "Progress"
        case .title: "Title"
        }
    }
    var icon: String {
        switch self {
        case .recent: "clock"
        case .progress: "chart.bar.fill"
        case .title: "textformat"
        }
    }
}

private enum MyPlaybillShelfKind: String, CaseIterable, Hashable {
    case seriesWatching, seriesWaiting, seriesWatchLater, seriesCompleted, seriesDropped
    case filmInProgress, filmWatchLater, filmWatched

    init(status: TrackedShowStatus) {
        switch status {
        case .watching: self = .seriesWatching
        case .waiting: self = .seriesWaiting
        case .planToWatch: self = .seriesWatchLater
        case .completed: self = .seriesCompleted
        case .dropped: self = .seriesDropped
        }
    }
    var mediaKind: MyPlaybillMediaKind {
        switch self {
        case .seriesWatching, .seriesWaiting, .seriesWatchLater, .seriesCompleted, .seriesDropped: .series
        case .filmInProgress, .filmWatchLater, .filmWatched: .films
        }
    }
    var title: String {
        switch self {
        case .seriesWatching: "Watching"
        case .seriesWaiting: "Waiting for More"
        case .seriesWatchLater, .filmWatchLater: "Watch Later"
        case .seriesCompleted: "Completed"
        case .seriesDropped: "Dropped"
        case .filmInProgress: "In Progress"
        case .filmWatched: "Watched"
        }
    }
    var icon: String {
        switch self {
        case .seriesWatching: "play.circle.fill"
        case .seriesWaiting: "clock.badge.checkmark.fill"
        case .seriesWatchLater, .filmWatchLater: "bookmark.fill"
        case .seriesCompleted, .filmWatched: "checkmark.circle.fill"
        case .seriesDropped: "minus.circle.fill"
        case .filmInProgress: "play.square.stack.fill"
        }
    }
    var tint: Color {
        switch self {
        case .seriesWatching, .filmInProgress: KinemaTheme.accent
        case .seriesWaiting: .blue
        case .seriesWatchLater, .filmWatchLater: KinemaTheme.brass
        case .seriesCompleted, .filmWatched: .green
        case .seriesDropped: KinemaTheme.secondaryText
        }
    }
}

private struct MyPlaybillItem: Identifiable {
    let entry: CatalogEntry
    let progress: Double
    let progressLabel: String
    let lastActivityAt: Date
    let activityID: UUID?
    let repeatCount: Int
    var id: String { entry.id }
}

private struct MyPlaybillShelf: Identifiable {
    let kind: MyPlaybillShelfKind
    let items: [MyPlaybillItem]
    var id: String { kind.rawValue }
}

/// Title-level ownership and lifecycle. This is intentionally not an episode grid:
/// episodes roll up into their parent show and activity remains a secondary record.
struct PlaybillMyPlaybillSection: View {
    @Bindable var viewModel: PlayerViewModel
    @State private var shelves: [PlaybillStateShelf] = []
    @State private var recent: [PlaybillActivityGroup] = []
    @State private var playbillToken: UUID?

    private let columns = [GridItem(.adaptive(minimum: 300, maximum: 520), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if shelves.allSatisfy({ $0.items.isEmpty }) && recent.isEmpty {
                emptyState
            } else {
                stateOverview
                if !recent.isEmpty { recentActivity }
            }
        }
        .onAppear {
            reload()
            playbillToken = EventBus.shared.subscribe { event in
                switch event {
                case .playbillUpdated, .watchProgressUpdated: reload()
                default: break
                }
            }
        }
        .onDisappear {
            if let playbillToken { EventBus.shared.unsubscribe(playbillToken) }
        }
        .task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await refreshDerivedStates()
        }
    }

    private var stateOverview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                KinemaSectionTitle("Where everything stands", systemImage: "square.grid.2x2")
                Spacer()
                Text("\(shelves.reduce(0) { $0 + $1.items.count }) titles")
                    .font(KinemaType.metadataStrong)
                    .foregroundStyle(KinemaTheme.secondaryText)
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(shelves.filter { !$0.items.isEmpty }) { shelf in
                    stateCard(shelf)
                }
            }
        }
    }

    private func stateCard(_ shelf: PlaybillStateShelf) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: shelf.icon)
                    .foregroundStyle(shelf.tint)
                Text(shelf.title)
                    .font(KinemaType.labelStrong)
                    .foregroundStyle(KinemaTheme.paper)
                Spacer()
                Text("\(shelf.items.count)")
                    .font(KinemaType.metadataBold)
                    .foregroundStyle(KinemaTheme.secondaryText)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(KinemaTheme.raisedBackground, in: Capsule())
            }
            .padding(12)

            Divider().overlay(KinemaTheme.hairline.opacity(0.5))

            ForEach(Array(shelf.items.prefix(5))) { item in
                compactTitleRow(item)
                if item.id != shelf.items.prefix(5).last?.id {
                    Divider().padding(.leading, 80).overlay(KinemaTheme.hairline.opacity(0.35))
                }
            }

            if shelf.items.count > 5 {
                Text("+ \(shelf.items.count - 5) more")
                    .font(KinemaType.metadataStrong)
                    .foregroundStyle(KinemaTheme.secondaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
            }
        }
        .background(KinemaTheme.cardBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(KinemaTheme.hairline.opacity(0.62), lineWidth: 0.6)
        }
    }

    private func compactTitleRow(_ item: PlaybillStateItem) -> some View {
        HStack(spacing: 10) {
            NavigationLink(value: route(for: item.entry, activityID: item.activityID)) {
                HStack(spacing: 10) {
                    PlaybillPosterThumb(path: item.entry.posterPath, kind: item.entry.kind, aspectOverride: 16/9)
                        .frame(width: 58, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(item.entry.title)
                                .font(KinemaType.labelStrong)
                                .foregroundStyle(KinemaTheme.paper)
                                .lineLimit(1)
                            if item.repeatCount > 1 {
                                PlaybillRepeatBadge(count: item.repeatCount, scale: .chip)
                            }
                        }
                        Text(item.detail)
                            .font(KinemaType.micro)
                            .foregroundStyle(KinemaTheme.secondaryText)
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(KinemaTheme.secondaryText.opacity(0.5))
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
    }

    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: 12) {
            KinemaSectionTitle("Recently watched", systemImage: "clock.arrow.circlepath")
            VStack(spacing: 0) {
                ForEach(recent.prefix(12)) { group in
                    NavigationLink(value: route(for: group.entry, activityID: group.activityID)) {
                        HStack(spacing: 12) {
                            PlaybillPosterThumb(path: group.entry.posterPath, kind: group.entry.kind, aspectOverride: 16/9)
                                .frame(width: 64, height: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group.entry.title)
                                    .font(KinemaType.labelStrong)
                                    .foregroundStyle(KinemaTheme.paper)
                                Text(group.detail)
                                    .font(KinemaType.metadata)
                                    .foregroundStyle(KinemaTheme.secondaryText)
                            }
                            Spacer()
                            if group.repeatCount > 1 {
                                PlaybillRepeatBadge(count: group.repeatCount, scale: .chip)
                            }
                            Text(group.lastWatched, style: .relative)
                                .font(KinemaType.micro)
                                .foregroundStyle(KinemaTheme.secondaryText)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(KinemaTheme.secondaryText.opacity(0.55))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if group.id != recent.prefix(12).last?.id {
                        Divider().padding(.leading, 88).overlay(KinemaTheme.hairline.opacity(0.4))
                    }
                }
            }
            .background(KinemaTheme.cardBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(KinemaTheme.hairline.opacity(0.62), lineWidth: 0.6)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "Your Playbill is empty",
            systemImage: "rectangle.stack",
            description: Text("Track a series or save a film to see where everything stands.")
        )
        .frame(maxWidth: .infinity, minHeight: 260)
    }

    private func route(for entry: CatalogEntry, activityID: UUID?) -> PlaybillRoute {
        entry.kind == .tvShow ? .show(entry) : .title(entry, activityID)
    }

    private func reload() {
        let db = PlaybillStore.rawDatabase()
        let full = db.activities.filter { $0.completion == .full }
        let trackedShows = db.trackedShows
        let episodeWatchesByShow = playbillWatchedEpisodesByShow(
            db: db,
            trackedShows: trackedShows,
            fullActivities: full
        )
        var byStatus: [TrackedShowStatus: [PlaybillStateItem]] = [:]

        for tracked in trackedShows {
            guard let show = db.catalog[tracked.targetID] else { continue }
            let episodeWatches = episodeWatchesByShow[show.id, default: []]
            let detail: String
            switch tracked.status {
            case .watching:
                let watchedCount = PlaybillShowProgress.watchedEpisodeIDs(for: show.id).count
                detail = watchedCount == 0 ? "Not started" : "\(watchedCount) episodes watched"
            case .planToWatch: detail = "Saved to watch later"
            case .waiting: detail = "Caught up · waiting for a new season"
            case .completed: detail = "Finished series"
            case .dropped: detail = "Stopped watching"
            }
            byStatus[tracked.status, default: []].append(
                PlaybillStateItem(
                    entry: show,
                    detail: detail,
                    activityID: episodeWatches.max(by: { $0.watchedAt < $1.watchedAt })?.id,
                    repeatCount: PlaybillStore.seriesRepeatWatchCount(for: show.id)
                )
            )
        }

        if let watchlistID = db.lists.first(where: { $0.systemKind == .watchlist })?.id {
            let trackedIDs = Set(db.trackedShows.map(\.targetID))
            for listItem in db.listItems where listItem.listID == watchlistID && !trackedIDs.contains(listItem.targetID) {
                guard let entry = db.catalog[listItem.targetID] else { continue }
                byStatus[.planToWatch, default: []].append(
                    PlaybillStateItem(
                        entry: entry,
                        detail: "Added \(listItem.addedAt.formatted(date: .abbreviated, time: .omitted))",
                        activityID: nil,
                        repeatCount: 0
                    )
                )
            }
        }

        let watchedMovies = Dictionary(grouping: full.compactMap { activity -> PlaybillDiaryItem? in
            guard let entry = db.catalog[activity.targetID], entry.kind == .movie else { return nil }
            return PlaybillDiaryItem(activity: activity, entry: entry)
        }, by: { $0.entry.id })
        for (_, watches) in watchedMovies {
            guard let latest = watches.max(by: { $0.activity.watchedAt < $1.activity.watchedAt }) else { continue }
            let detail = "Watched"
            byStatus[.completed, default: []].append(
                PlaybillStateItem(
                    entry: latest.entry,
                    detail: detail,
                    activityID: latest.activity.id,
                    repeatCount: watches.count
                )
            )
        }

        let order: [(TrackedShowStatus, String, String)] = [
            (.watching, "Watching", "play.circle.fill"),
            (.waiting, "Waiting for more", "clock.badge.checkmark.fill"),
            (.planToWatch, "Watch later", "bookmark.fill"),
            (.completed, "Completed", "checkmark.circle.fill"),
            (.dropped, "Dropped", "minus.circle.fill")
        ]
        shelves = order.map { status, title, icon in
            PlaybillStateShelf(
                status: status,
                title: title,
                icon: icon,
                tint: status.tint,
                items: byStatus[status, default: []].sorted { $0.entry.title < $1.entry.title }
            )
        }

        let grouped = Dictionary(grouping: full) { activity -> String in
            guard let entry = db.catalog[activity.targetID] else { return activity.targetID }
            return entry.parentShowID ?? entry.id
        }
        recent = grouped.compactMap { key, activities in
            guard let latest = activities.max(by: { $0.watchedAt < $1.watchedAt }),
                  let watchedEntry = db.catalog[latest.targetID] else { return nil }
            let entry = watchedEntry.parentShowID.flatMap { db.catalog[$0] } ?? watchedEntry
            let distinctCount = Set(activities.map(\.targetID)).count
            let detail = watchedEntry.kind == .episode
                ? "\(distinctCount) episode\(distinctCount == 1 ? "" : "s") watched"
                : "Film watched"
            let repeatCount = entry.kind == .tvShow
                ? PlaybillStore.seriesRepeatWatchCount(for: entry.id)
                : activities.count
            return PlaybillActivityGroup(
                entry: entry,
                detail: detail,
                lastWatched: latest.watchedAt,
                activityID: latest.id,
                repeatCount: repeatCount
            )
        }
        .sorted { $0.lastWatched > $1.lastWatched }
    }

    private func refreshDerivedStates() async {
        await Task.yield()
        if PlaybillStore.demoteIncompleteCompletedShows() > 0 {
            reload()
        }
    }
}

private struct PlaybillStateItem: Identifiable {
    let entry: CatalogEntry
    let detail: String
    let activityID: UUID?
    let repeatCount: Int
    var id: String { entry.id }
}

private struct PlaybillStateShelf: Identifiable {
    let status: TrackedShowStatus
    let title: String
    let icon: String
    let tint: Color
    let items: [PlaybillStateItem]
    var id: String { status.rawValue }
}

private struct PlaybillActivityGroup: Identifiable {
    let entry: CatalogEntry
    let detail: String
    let lastWatched: Date
    let activityID: UUID
    let repeatCount: Int
    var id: String { entry.id }
}

struct PlaybillDiarySection: View {
    @Bindable var viewModel: PlayerViewModel
    var horizontalSizeClass: UserInterfaceSizeClass?
    @State private var items: [PlaybillDiaryItem] = []
    @State private var continueItems: [PlaybillContinueItem] = []
    @State private var refreshID = UUID()
    @State private var playbillToken: UUID?

    private var accent: Color { KinemaTheme.accent }

    var body: some View {
        Group {
            if continueItems.isEmpty && items.isEmpty {
                emptyDiary
            } else {
                VStack(alignment: .leading, spacing: 24) {
                    if !continueItems.isEmpty {
                        continueSection
                    }
                    if !items.isEmpty {
                        diarySection
                    }
                }
            }
        }
        .id(refreshID)
        .onAppear {
            reload()
            playbillToken = EventBus.shared.subscribe { event in
                switch event {
                case .playbillUpdated, .watchProgressUpdated:
                    reload()
                default:
                    break
                }
            }
        }
        .onDisappear {
            if let playbillToken { EventBus.shared.unsubscribe(playbillToken) }
        }
    }

    private var continueSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            KinemaSectionTitle(KinemaCopy.playbillContinue, systemImage: "play.circle")

            LazyVGrid(
                columns: MediaLibraryLayout.posterColumns(horizontalSizeClass: horizontalSizeClass),
                spacing: MediaLibraryLayout.gridSpacing(horizontalSizeClass: horizontalSizeClass)
            ) {
                ForEach(continueItems) { item in
                    NavigationLink(value: PlaybillRoute.title(item.entry, nil)) {
                        PlaybillPosterCard(
                            entry: item.entry,
                            accent: accent,
                            badge: KinemaCopy.playbillInProgress,
                            progress: item.progress
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            playContinueItem(item)
                        } label: {
                            Label(KinemaCopy.playbillResumeInKinema, systemImage: "play.fill")
                        }
                    }
                }
            }
        }
    }

    private var diarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !continueItems.isEmpty {
                KinemaSectionTitle(KinemaCopy.playbillDiary, systemImage: "book.closed")
            }

            LazyVGrid(
                columns: MediaLibraryLayout.posterColumns(horizontalSizeClass: horizontalSizeClass),
                spacing: MediaLibraryLayout.gridSpacing(horizontalSizeClass: horizontalSizeClass)
            ) {
                ForEach(items) { item in
                    NavigationLink(value: PlaybillRoute.title(item.entry, item.activity.id)) {
                        PlaybillPosterCard(
                            entry: item.entry,
                            accent: accent,
                            badge: item.activity.source.displayBadge,
                            progress: PlaybillStore.playbackProgress(for: item.entry.id)
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if PlaybillLibraryResolver.hasLinkedMedia(for: item.entry.id) {
                            Button {
                                playDiaryItem(item)
                            } label: {
                                Label(
                                    playLabel(for: item.entry.id),
                                    systemImage: "play.fill"
                                )
                            }
                        }
                        Button(role: .destructive) {
                            PlaybillStore.removeActivity(id: item.activity.id)
                            reload()
                        } label: {
                            Label("Remove entry", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private var emptyDiary: some View {
        VStack(spacing: 14) {
            Text(KinemaCopy.playbillEmptyTitle)
                .font(KinemaType.cardTitle)
                .foregroundStyle(KinemaTheme.paper)
            Text(KinemaCopy.playbillEmptyMessage)
                .font(KinemaType.label)
                .foregroundStyle(KinemaTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
    }

    private func reload() {
        continueItems = PlaybillStore.continueItems(limit: 40)
        items = PlaybillStore.diaryItems(limit: 120)
    }

    private func diaryItem(for continueItem: PlaybillContinueItem) -> PlaybillDiaryItem {
        PlaybillDiaryItem(
            activity: WatchActivity(
                targetID: continueItem.entry.id,
                source: .player,
                completion: .partial,
                watchedSeconds: continueItem.progress.position
            ),
            entry: continueItem.entry
        )
    }

    private func playContinueItem(_ item: PlaybillContinueItem) {
        playEntry(item.entry)
    }

    private func playDiaryItem(_ item: PlaybillDiaryItem) {
        playEntry(item.entry)
    }

    private func playEntry(_ entry: CatalogEntry) {
        playShowEntry(entry, viewModel: viewModel)
    }

    private func playLabel(for targetID: String) -> String {
        PlaybillStore.playbackProgress(for: targetID)?.hasPartialResume == true
            ? KinemaCopy.playbillResumeInKinema
            : KinemaCopy.playbillPlayInKinema
    }
}

struct PlaybillSearchSection: View {
    @Bindable var viewModel: PlayerViewModel
    @State private var query = ""
    @State private var results: [PlaybillSearchResult] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var selectedResult: PlaybillSearchResult?
    @State private var watchedAt = Date()
    @State private var connectivity = PlaybillConnectivity.shared
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            KinemaCard(title: KinemaCopy.playbillSearch, icon: "magnifyingglass") {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(KinemaTheme.secondaryText)
                    TextField(KinemaCopy.playbillSearchPlaceholder, text: $query)
                        .textFieldStyle(.plain)
                        .font(KinemaType.body)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #endif
                        .focused($focused)
                        .onSubmit { runSearch() }
                        .disabled(!connectivity.isOnline)

                    if isSearching {
                        ProgressView().controlSize(.small)
                    } else if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(KinemaTheme.secondaryText)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 40)
                .background(KinemaTheme.raisedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(KinemaType.metadata)
                    .foregroundStyle(KinemaTheme.accent)
            }

            if !connectivity.isOnline {
                Label("Connect to search for new titles. Everything already in your Playbill remains available.", systemImage: "wifi.slash")
                    .font(KinemaType.metadata)
                    .foregroundStyle(KinemaTheme.secondaryText)
            }

            if !results.isEmpty {
                KinemaSectionTitle("Results", systemImage: "sparkles")
                LazyVStack(spacing: 10) {
                    ForEach(results) { result in
                        let state = PlaybillStore.titleState(for: result)
                        if state.isExisting {
                            NavigationLink(value: route(for: result)) {
                                PlaybillSearchRow(result: result, state: state)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button {
                                selectedResult = result
                                watchedAt = Date()
                            } label: {
                                PlaybillSearchRow(result: result, state: state)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .sheet(item: $selectedResult) { result in
            NavigationStack {
                PlaybillAddSheet(result: result, watchedAt: $watchedAt, viewModel: viewModel)
            }
            #if os(iOS)
            .presentationDetents(result.kind == .tvShow ? [.height(360)] : [.medium])
            .presentationDragIndicator(.visible)
            #endif
            #if os(macOS)
            .frame(minWidth: 400)
            #endif
        }
    }

    private func runSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard connectivity.isOnline else {
            errorMessage = "Search needs an internet connection."
            return
        }
        isSearching = true
        errorMessage = nil
        Task {
            defer { isSearching = false }
            do {
                results = try await TMDBClient.search(query: trimmed)
            } catch {
                errorMessage = error.localizedDescription
                results = []
            }
        }
    }

    private func route(for result: PlaybillSearchResult) -> PlaybillRoute {
        let entry = PlaybillStore.entry(for: result.id) ?? CatalogEntry(
            id: result.id,
            kind: result.kind,
            tmdbID: result.tmdbID,
            title: result.title,
            subtitle: result.subtitle,
            year: result.year,
            overview: result.overview,
            posterPath: result.posterPath
        )
        return entry.kind == .tvShow ? .show(entry) : .title(entry, nil)
    }
}

struct PlaybillSearchRow: View {
    let result: PlaybillSearchResult
    var state: PlaybillTitleState = .new

    var body: some View {
        HStack(spacing: 14) {
            PlaybillPosterThumb(path: result.posterPath, kind: result.kind)
                .frame(width: 52, height: 78)

            VStack(alignment: .leading, spacing: 4) {
                Text(result.title)
                    .font(KinemaType.posterTitle)
                    .foregroundStyle(KinemaTheme.paper)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(result.kind == .movie ? "Film" : "Series")
                    if let year = result.year {
                        Text("·")
                        Text(String(year))
                    }
                }
                .font(KinemaType.metadata)
                .foregroundStyle(KinemaTheme.secondaryText)
            }
            Spacer(minLength: 0)
            stateBadge
        }
        .padding(14)
        .background(KinemaTheme.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(KinemaTheme.hairline.opacity(0.78), lineWidth: 0.6)
        }
    }

    private var stateBadge: some View {
        Label(stateLabel, systemImage: stateIcon)
            .font(KinemaType.microBold)
            .foregroundStyle(stateTint)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .frame(minWidth: state.isExisting ? 30 : 58, minHeight: 30)
            .background(stateTint.opacity(0.12), in: Capsule())
            .accessibilityLabel(stateLabel)
    }

    private var stateLabel: String {
        switch state {
        case .new:
            return result.kind == .tvShow ? "Track" : "Add"
        case let .tracked(status):
            return status.label
        case let .watched(count):
            return count == 1 ? "Watched" : "\(count) watched"
        case .watchLater:
            return "Watch later"
        }
    }

    private var stateIcon: String {
        switch state {
        case .new: return "plus.circle.fill"
        case let .tracked(status): return status.icon
        case .watched: return "checkmark.circle.fill"
        case .watchLater: return "bookmark.fill"
        }
    }

    private var stateTint: Color {
        switch state {
        case .new: return KinemaTheme.accent
        case let .tracked(status): return status.tint
        case .watched: return .green
        case .watchLater: return KinemaTheme.brass
        }
    }
}

struct PlaybillAddSheet: View {
    let result: PlaybillSearchResult
    @Binding var watchedAt: Date
    @Bindable var viewModel: PlayerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var connectivity = PlaybillConnectivity.shared

    private var isSeries: Bool { result.kind == .tvShow }
    private var titleState: PlaybillTitleState { PlaybillStore.titleState(for: result) }
    private var alreadyInPlaybill: Bool { titleState.isExisting }

    var body: some View {
        ZStack {
            KinemaBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 16) {
                        PlaybillPosterThumb(path: result.posterPath, kind: result.kind)
                            .frame(width: 88, height: 132)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(result.title)
                                .font(KinemaType.title)
                                .foregroundStyle(KinemaTheme.paper)
                            if let overview = result.overview, !overview.isEmpty {
                                Text(overview)
                                    .font(KinemaType.metadata)
                                    .foregroundStyle(KinemaTheme.secondaryText)
                                    .lineLimit(4)
                            }
                        }
                    }

                    if alreadyInPlaybill {
                        existingStateBlock
                    } else if !isSeries {
                        DatePicker(KinemaCopy.playbillWatchedDate, selection: $watchedAt, displayedComponents: [.date, .hourAndMinute])
                    } else {
                        Text("Track this series to see the next episode, catch up on what you missed, and follow your progress.")
                            .font(KinemaType.label)
                            .foregroundStyle(KinemaTheme.secondaryText)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(KinemaType.metadata)
                            .foregroundStyle(KinemaTheme.accent)
                    }

                    Button(action: primaryAction) {
                        KinemaComposerButtonLabel(
                            primaryButtonTitle,
                            systemImage: alreadyInPlaybill ? "arrow.right.circle" : (isSeries ? "tv" : "checkmark.circle"),
                            showsProgress: isSaving
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(KinemaTheme.accent)
                    .kinemaComposerButtonStyle()
                    .disabled(isSaving)

                    if !isSeries && !alreadyInPlaybill {
                        Button(action: addToWatchlist) {
                            KinemaComposerButtonLabel(KinemaCopy.playbillAddToWatchlist, systemImage: "bookmark")
                        }
                        .buttonStyle(.bordered)
                        .kinemaComposerButtonStyle()
                        .disabled(isSaving)
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle(KinemaCopy.playbillAddTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(KinemaCopy.cancel) { dismiss() }
            }
        }
    }

    private var existingStateBlock: some View {
        HStack(spacing: 10) {
            Image(systemName: existingStateIcon)
                .foregroundStyle(existingStateTint)
            Text(existingStateMessage)
                .font(KinemaType.label)
                .foregroundStyle(KinemaTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(KinemaTheme.raisedBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var primaryButtonTitle: String {
        if alreadyInPlaybill {
            return isSeries ? "Open series" : "Open title"
        }
        return isSeries ? KinemaCopy.playbillTrackSeries : KinemaCopy.playbillMarkWatched
    }

    private var existingStateMessage: String {
        switch titleState {
        case let .tracked(status):
            return "Already in Playbill · \(status.label)"
        case let .watched(count):
            let noun = isSeries ? "episodes watched" : "watches"
            return "Already in Playbill · \(count) \(noun)"
        case .watchLater:
            return "Already in Playbill · Watch later"
        case .new:
            return ""
        }
    }

    private var existingStateIcon: String {
        switch titleState {
        case let .tracked(status): return status.icon
        case .watched: return "checkmark.circle.fill"
        case .watchLater: return "bookmark.fill"
        case .new: return "plus.circle.fill"
        }
    }

    private var existingStateTint: Color {
        switch titleState {
        case let .tracked(status): return status.tint
        case .watched: return .green
        case .watchLater: return KinemaTheme.brass
        case .new: return KinemaTheme.accent
        }
    }

    private func primaryAction() {
        if alreadyInPlaybill {
            openExisting()
            return
        }
        if isSeries {
            trackSeries()
        } else {
            logWatch()
        }
    }

    private func openExisting() {
        dismiss()
        viewModel.showOSD("Already in Playbill")
    }

    private func trackSeries() {
        isSaving = true
        errorMessage = nil
        let entry = savedEntry()
        _ = PlaybillStore.upsertCatalog(entry)
        _ = PlaybillStore.trackShow(targetID: entry.id)
        viewModel.showOSD(KinemaCopy.playbillTracked)
        dismiss()
        enrichWhenPossible(entry)
    }

    private func logWatch() {
        isSaving = true
        errorMessage = nil
        let entry = savedEntry()
        _ = PlaybillStore.upsertCatalog(entry)
        _ = PlaybillStore.logWatch(targetID: entry.id, watchedAt: watchedAt, source: .manual)
        viewModel.showOSD(KinemaCopy.playbillLogged)
        dismiss()
        enrichWhenPossible(entry)
    }

    private func addToWatchlist() {
        isSaving = true
        errorMessage = nil
        let entry = savedEntry()
        _ = PlaybillStore.upsertCatalog(entry)
        _ = PlaybillStore.addToWatchlist(targetID: entry.id)
        viewModel.showOSD(KinemaCopy.playbillAddedToWatchlist)
        dismiss()
        enrichWhenPossible(entry)
    }

    private func savedEntry() -> CatalogEntry {
        PlaybillStore.entry(for: result.id) ?? CatalogEntry(
            id: result.id,
            kind: result.kind,
            tmdbID: result.tmdbID,
            title: result.title,
            subtitle: result.subtitle,
            year: result.year,
            overview: result.overview,
            posterPath: result.posterPath
        )
    }

    private func enrichWhenPossible(_ localEntry: CatalogEntry) {
        guard connectivity.isOnline else { return }
        Task(priority: .utility) {
            guard let enriched = try? await TMDBClient.catalogEntry(from: result) else { return }
            _ = PlaybillStore.upsertCatalog(enriched)
            if localEntry.kind == .tvShow {
                await PlaybillShowProgress.warmCache(for: localEntry.id)
                _ = await PlaybillShowProgress.reconcileTrackingState(for: localEntry.id, allowNetwork: true)
            }
        }
    }
}

struct PlaybillStatsSection: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var insight = PlaybillInsightSnapshot.empty
    @State private var selectedRange: PlaybillStatsRange = .thirtyDays
    @State private var showDataTools = false
    @State private var playbillToken: UUID?

    private var selectedStats: PlaybillRangeStats {
        insight.ranges[selectedRange] ?? .empty
    }

    private var trendPoints: [PlaybillTrendPoint] {
        selectedStats.trendPoints(for: selectedRange)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 34) {
            storyOpening

            if selectedStats.watches == 0 {
                emptyStory
            } else {
                viewingRhythm
                evidence
                if selectedStats.filmHours + selectedStats.seriesHours > 0 {
                    formatStory
                }

                if !selectedStats.topTitles.isEmpty {
                    signatures
                }

                if let latestTitle = selectedStats.latestTitle,
                   let latestWatchedAt = selectedStats.latestWatchedAt {
                    latestNote(title: latestTitle, watchedAt: latestWatchedAt)
                }
            }

            Divider().overlay(KinemaTheme.hairline)

            DisclosureGroup(isExpanded: $showDataTools) {
                PlaybillDataSection()
                    .padding(.top, 12)
            } label: {
                Label("Data & imports", systemImage: "externaldrive.fill.badge.plus")
                    .font(KinemaType.labelStrong)
                    .foregroundStyle(KinemaTheme.secondaryText)
            }
            .tint(KinemaTheme.brass)
        }
        .onAppear {
            reload()
            playbillToken = EventBus.shared.subscribe { event in
                if case .playbillUpdated = event { reload() }
            }
        }
        .onDisappear {
            if let playbillToken { EventBus.shared.unsubscribe(playbillToken) }
        }
    }

    private var storyOpening: some View {
        VStack(alignment: .leading, spacing: 18) {
            if horizontalSizeClass == .compact {
                VStack(alignment: .leading, spacing: 14) {
                    rangePicker
                    storyCopy
                }
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .center, spacing: 24) {
                        rangeEyebrow
                        Spacer(minLength: 24)
                        rangePicker
                    }
                    storyMessage
                }
            }
        }
    }

    private var storyCopy: some View {
        VStack(alignment: .leading, spacing: 8) {
            rangeEyebrow
            storyMessage
        }
    }

    private var rangeEyebrow: some View {
        Text(selectedRange.contextLabel.uppercased())
            .font(KinemaType.microBold)
            .tracking(1.4)
            .foregroundStyle(KinemaTheme.brass)
    }

    private var storyMessage: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(storyHeadline)
                .font(KinemaType.display)
                .foregroundStyle(KinemaTheme.paper)
                .fixedSize(horizontal: false, vertical: true)

            if selectedStats.watches > 0 {
                Text(storyContext)
                    .font(KinemaType.label)
                    .foregroundStyle(KinemaTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: 760, alignment: .leading)
    }

    private var rangePicker: some View {
        Picker("Reel range", selection: $selectedRange) {
            ForEach(PlaybillStatsRange.allCases) { range in
                Text(range.title).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: horizontalSizeClass == .compact ? .infinity : 300)
    }

    private var storyHeadline: String {
        guard selectedStats.watches > 0 else { return "Your reel is waiting for its first scene." }

        if selectedRange == .thirtyDays, insight.previous30DaysHours > 0 {
            let delta = selectedStats.hours - insight.previous30DaysHours
            let threshold = max(0.5, insight.previous30DaysHours * 0.12)
            if abs(delta) >= threshold {
                return "You watched \(PlaybillDurationFormatter.compact(hours: abs(delta))) \(delta > 0 ? "more" : "less") than in the previous 30 days."
            }
        }

        let total = selectedStats.filmHours + selectedStats.seriesHours
        if total <= 0 {
            return "You completed \(selectedStats.watches) \(selectedStats.watches == 1 ? "watch" : "watches") in this chapter."
        }
        let seriesShare = total > 0 ? selectedStats.seriesHours / total : 0
        if seriesShare >= 0.65 { return "Series shaped most of this chapter of your reel." }
        if seriesShare <= 0.35 { return "Films took the leading role in this chapter." }
        return "Films and series shared the screen almost evenly."
    }

    private var storyContext: String {
        let dayCopy = selectedStats.activeDays == 1 ? "day" : "days"
        let watchCopy = selectedStats.watches == 1 ? "watch" : "watches"
        return "\(PlaybillDurationFormatter.compact(hours: selectedStats.hours)) across \(selectedStats.watches) \(watchCopy), spread over \(selectedStats.activeDays) active \(dayCopy)."
    }

    private var emptyStory: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "film")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(KinemaTheme.brass)
            Text("Completed watches in this period will become a simple visual story here—without turning your viewing into a scorecard.")
                .font(KinemaType.label)
                .foregroundStyle(KinemaTheme.secondaryText)
        }
        .padding(.vertical, 8)
    }

    private var viewingRhythm: some View {
        VStack(alignment: .leading, spacing: 15) {
            narrativeLabel("The rhythm", detail: rhythmTakeaway)
            trendChart
        }
    }

    private var rhythmTakeaway: String {
        guard let peak = trendPoints.max(by: { $0.hours < $1.hours }), peak.hours > 0 else {
            return "Your watching was spread lightly across the period."
        }
        return "Your strongest stretch was \(peak.label), with \(PlaybillDurationFormatter.compact(hours: peak.hours)) watched."
    }

    private var trendChart: some View {
        let peakHours = trendPoints.map(\.hours).max() ?? 0
        return GeometryReader { geometry in
            let spacing: CGFloat = trendPoints.count > 8 ? 5 : 10
            let availableWidth = max(1, geometry.size.width - spacing * CGFloat(max(0, trendPoints.count - 1)))
            let barWidth = max(5, availableWidth / CGFloat(max(1, trendPoints.count)))

            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(trendPoints) { point in
                    let isPeak = point.hours == peakHours && peakHours > 0
                    VStack(spacing: 7) {
                        if isPeak {
                            Text(PlaybillDurationFormatter.compact(hours: point.hours))
                                .font(KinemaType.microBold)
                                .foregroundStyle(KinemaTheme.paper)
                                .lineLimit(1)
                        } else {
                            Spacer(minLength: 12)
                        }

                        RoundedRectangle(cornerRadius: min(5, barWidth / 2), style: .continuous)
                            .fill(isPeak ? KinemaTheme.accent : KinemaTheme.secondaryText.opacity(0.24))
                            .frame(
                                width: barWidth,
                                height: max(3, 118 * CGFloat(point.hours / max(0.01, peakHours)))
                            )

                        Text(point.label)
                            .font(KinemaType.micro)
                            .foregroundStyle(isPeak ? KinemaTheme.paper : KinemaTheme.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(width: barWidth)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .frame(height: 168)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rhythmTakeaway)
    }

    private var evidence: some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider().overlay(KinemaTheme.hairline.opacity(0.8))
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 130), spacing: 24, alignment: .leading)],
                alignment: .leading,
                spacing: 18
            ) {
                evidenceMetric("\(selectedStats.watches)", selectedStats.watches == 1 ? "completed watch" : "completed watches")
                evidenceMetric("\(selectedStats.activeDays)", selectedStats.activeDays == 1 ? "active day" : "active days")
                evidenceMetric("\(selectedStats.replays)", selectedStats.replays == 1 ? "rewatch" : "rewatches")
            }
        }
    }

    private var formatStory: some View {
        let total = max(0.01, selectedStats.filmHours + selectedStats.seriesHours)
        let seriesShare = selectedStats.seriesHours / total
        let filmShare = selectedStats.filmHours / total
        let seriesLeads = seriesShare >= filmShare

        return VStack(alignment: .leading, spacing: 15) {
            narrativeLabel("What drove it", detail: formatTakeaway(seriesShare: seriesShare))

            GeometryReader { geometry in
                HStack(spacing: 3) {
                    if seriesShare > 0 {
                        Capsule()
                            .fill(seriesLeads ? KinemaTheme.accent : KinemaTheme.secondaryText.opacity(0.28))
                            .frame(width: max(3, geometry.size.width * CGFloat(seriesShare) - 1.5))
                    }
                    if filmShare > 0 {
                        Capsule()
                            .fill(seriesLeads ? KinemaTheme.secondaryText.opacity(0.28) : KinemaTheme.accent)
                            .frame(width: max(3, geometry.size.width * CGFloat(filmShare) - 1.5))
                    }
                }
            }
            .frame(height: 11)

            HStack(spacing: 22) {
                formatLegend("Series", hours: selectedStats.seriesHours, share: seriesShare, emphasized: seriesLeads)
                formatLegend("Films", hours: selectedStats.filmHours, share: filmShare, emphasized: !seriesLeads)
            }
        }
    }

    private func formatTakeaway(seriesShare: Double) -> String {
        let percentage = Int((max(seriesShare, 1 - seriesShare) * 100).rounded())
        if seriesShare >= 0.55 { return "Series accounted for \(percentage)% of your watching time."
        }
        if seriesShare <= 0.45 { return "Films accounted for \(percentage)% of your watching time."
        }
        return "Neither format dominated your watching time."
    }

    private var signatures: some View {
        let values = Array(selectedStats.topTitles.prefix(5))
        let maximum = max(0.01, values.map(\.hours).max() ?? 0)
        return VStack(alignment: .leading, spacing: 15) {
            narrativeLabel("The names in the credits", detail: signatureTakeaway(values: values))

            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(values.enumerated()), id: \.element.id) { index, value in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(value.label)
                                .font(KinemaType.metadataStrong)
                                .foregroundStyle(KinemaTheme.paper)
                                .lineLimit(1)
                            Spacer()
                            Text(PlaybillDurationFormatter.compact(hours: value.hours))
                                .font(KinemaType.micro)
                                .foregroundStyle(KinemaTheme.secondaryText)
                                .monospacedDigit()
                        }
                        GeometryReader { geometry in
                            Capsule()
                                .fill(index == 0 ? KinemaTheme.accent : KinemaTheme.secondaryText.opacity(0.24))
                                .frame(width: max(4, geometry.size.width * CGFloat(value.hours / maximum)))
                        }
                        .frame(height: 5)
                    }
                }
            }

            if !selectedStats.topGenres.isEmpty {
                Text("Your reel leaned toward \(selectedStats.topGenres.prefix(3).map(\.label).joined(separator: ", ")).")
                    .font(KinemaType.metadata)
                    .foregroundStyle(KinemaTheme.secondaryText)
            }
        }
    }

    private func signatureTakeaway(values: [PlaybillRankedHours]) -> String {
        guard let leader = values.first else { return "No title led this period."
        }
        return "\(leader.label) held your attention longest."
    }

    private func latestNote(title: String, watchedAt: Date) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Latest")
                .font(KinemaType.microBold)
                .foregroundStyle(KinemaTheme.brass)
            Text(title)
                .font(KinemaType.metadataStrong)
                .foregroundStyle(KinemaTheme.paper)
                .lineLimit(1)
            Text("· \(watchedAt.formatted(date: .abbreviated, time: .omitted))")
                .font(KinemaType.metadata)
                .foregroundStyle(KinemaTheme.secondaryText)
        }
    }

    private func narrativeLabel(_ eyebrow: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(eyebrow.uppercased())
                .font(KinemaType.microBold)
                .tracking(1.2)
                .foregroundStyle(KinemaTheme.brass)
            Text(detail)
                .font(KinemaType.title)
                .foregroundStyle(KinemaTheme.paper)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func evidenceMetric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(KinemaType.title)
                .foregroundStyle(KinemaTheme.paper)
                .monospacedDigit()
            Text(label)
                .font(KinemaType.metadata)
                .foregroundStyle(KinemaTheme.secondaryText)
        }
    }

    private func formatLegend(_ label: String, hours: Double, share: Double, emphasized: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(label) · \(Int((share * 100).rounded()))%")
                .font(KinemaType.metadataStrong)
                .foregroundStyle(emphasized ? KinemaTheme.paper : KinemaTheme.secondaryText)
            Text(PlaybillDurationFormatter.compact(hours: hours))
                .font(KinemaType.micro)
                .foregroundStyle(KinemaTheme.secondaryText)
        }
    }

    private func reload() {
        insight = PlaybillInsightSnapshot.build()
    }
}

private enum PlaybillStatsRange: String, CaseIterable, Identifiable {
    case thirtyDays
    case year
    case allTime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .thirtyDays: return "30 days"
        case .year: return "Year"
        case .allTime: return "All time"
        }
    }

    var contextLabel: String {
        switch self {
        case .thirtyDays: return "Last 30 days"
        case .year: return "This year"
        case .allTime: return "All time"
        }
    }

    var icon: String {
        switch self {
        case .thirtyDays: return "calendar.badge.clock"
        case .year: return "calendar.circle"
        case .allTime: return "infinity"
        }
    }

    func startDate(now: Date, calendar: Calendar) -> Date? {
        switch self {
        case .thirtyDays:
            return calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now))
        case .year:
            return calendar.date(from: calendar.dateComponents([.year], from: now))
        case .allTime:
            return nil
        }
    }
}

private struct PlaybillRankedHours: Identifiable {
    let label: String
    let hours: Double
    var id: String { label }
}

private struct PlaybillTrendPoint: Identifiable {
    let date: Date
    let label: String
    let hours: Double
    var id: Date { date }
}

private struct PlaybillRangeStats {
    var watches: Int
    var replays: Int
    var hours: Double
    var activeDays: Int
    var latestTitle: String?
    var latestWatchedAt: Date?
    var filmHours: Double
    var seriesHours: Double
    var dayHours: [Date: Double]
    var topTitles: [PlaybillRankedHours]
    var topGenres: [PlaybillRankedHours]

    static let empty = PlaybillRangeStats(
        watches: 0, replays: 0, hours: 0, activeDays: 0,
        latestTitle: nil, latestWatchedAt: nil,
        filmHours: 0, seriesHours: 0, dayHours: [:], topTitles: [], topGenres: []
    )

    func trendPoints(for range: PlaybillStatsRange, now: Date = Date(), calendar: Calendar = .current) -> [PlaybillTrendPoint] {
        switch range {
        case .thirtyDays:
            let today = calendar.startOfDay(for: now)
            let periodStart = calendar.date(byAdding: .day, value: -29, to: today) ?? today
            return (0..<6).compactMap { bucket in
                guard let start = calendar.date(byAdding: .day, value: bucket * 5, to: periodStart) else { return nil }
                let bucketDays = (0..<5).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
                let value = bucketDays.reduce(0) { $0 + (dayHours[calendar.startOfDay(for: $1)] ?? 0) }
                return PlaybillTrendPoint(
                    date: start,
                    label: start.formatted(.dateTime.month(.abbreviated).day()),
                    hours: value
                )
            }

        case .year:
            let components = calendar.dateComponents([.year], from: now)
            let yearStart = calendar.date(from: components) ?? now
            let monthCount = max(1, (calendar.dateComponents([.month], from: yearStart, to: now).month ?? 0) + 1)
            return (0..<monthCount).compactMap { offset in
                guard let start = calendar.date(byAdding: .month, value: offset, to: yearStart),
                      let end = calendar.date(byAdding: .month, value: 1, to: start) else { return nil }
                return PlaybillTrendPoint(
                    date: start,
                    label: start.formatted(.dateTime.month(.abbreviated)),
                    hours: hours(from: start, to: end)
                )
            }

        case .allTime:
            guard let firstDay = dayHours.keys.min(), let lastDay = dayHours.keys.max() else { return [] }
            let firstMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: firstDay)) ?? firstDay
            let lastMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: lastDay)) ?? lastDay
            let monthSpan = (calendar.dateComponents([.month], from: firstMonth, to: lastMonth).month ?? 0) + 1

            if monthSpan <= 12 {
                return (0..<monthSpan).compactMap { offset in
                    guard let start = calendar.date(byAdding: .month, value: offset, to: firstMonth),
                          let end = calendar.date(byAdding: .month, value: 1, to: start) else { return nil }
                    return PlaybillTrendPoint(
                        date: start,
                        label: start.formatted(.dateTime.month(.abbreviated)),
                        hours: hours(from: start, to: end)
                    )
                }
            }

            let firstYear = calendar.component(.year, from: firstDay)
            let lastYear = calendar.component(.year, from: lastDay)
            return (firstYear...lastYear).compactMap { year in
                guard let start = calendar.date(from: DateComponents(year: year)),
                      let end = calendar.date(byAdding: .year, value: 1, to: start) else { return nil }
                return PlaybillTrendPoint(date: start, label: String(year), hours: hours(from: start, to: end))
            }
        }
    }

    private func hours(from start: Date, to end: Date) -> Double {
        dayHours.reduce(0) { partial, item in
            partial + ((item.key >= start && item.key < end) ? item.value : 0)
        }
    }
}

private enum PlaybillDurationFormatter {
    private static let hoursPerDay = 24.0
    private static let hoursPerMonth = 24.0 * 30.4375
    private static let hoursPerYear = 24.0 * 365.25

    static func compact(hours: Double) -> String {
        guard hours.isFinite, hours > 0 else { return "0m" }

        if hours < 1 {
            return "\(max(1, Int((hours * 60).rounded())))m"
        }
        if hours < hoursPerDay {
            return "\(hours.formatted(.number.precision(.fractionLength(hours >= 10 ? 0 : 1))))h"
        }

        return compound(hours: hours)
    }

    private static func compound(hours: Double) -> String {
        var remaining = Int((hours * 60).rounded())
        let units: [(label: String, minutes: Int)] = [
            ("y", Int(hoursPerYear * 60)),
            ("mo", Int(hoursPerMonth * 60)),
            ("d", Int(hoursPerDay * 60)),
            ("h", 60)
        ]
        var parts: [String] = []

        for unit in units {
            let value = remaining / unit.minutes
            guard value > 0 else { continue }
            parts.append("\(value)\(unit.label)")
            remaining -= value * unit.minutes
            if parts.count == 2 { break }
        }

        return parts.isEmpty ? "\(max(1, remaining))m" : parts.joined(separator: " ")
    }
}

private struct PlaybillInsightSnapshot {
    var previous30DaysHours: Double
    var ranges: [PlaybillStatsRange: PlaybillRangeStats]

    static let empty = PlaybillInsightSnapshot(previous30DaysHours: 0, ranges: [:])

    @MainActor
    static func build(now: Date = Date()) -> PlaybillInsightSnapshot {
        let db = PlaybillStore.rawDatabase()
        let activities = db.activities.filter { $0.completion == .full }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let last30Start = calendar.date(byAdding: .day, value: -29, to: today) ?? today
        let previous30Start = calendar.date(byAdding: .day, value: -30, to: last30Start) ?? last30Start
        var previous30DaysHours = 0.0
        var rangeBuckets = Dictionary(
            uniqueKeysWithValues: PlaybillStatsRange.allCases.map { ($0, PlaybillRangeAccumulator()) }
        )

        for activity in activities {
            guard let entry = db.catalog[activity.targetID] else { continue }
            let owner = entry.parentShowID.flatMap { db.catalog[$0] } ?? entry
            let minutes: Double
            if let seconds = activity.watchedSeconds, seconds > 0 {
                minutes = seconds / 60
            } else {
                minutes = Double(entry.runtimeMinutes ?? owner.runtimeMinutes ?? 0)
            }
            let hours = minutes / 60

            if activity.watchedAt >= previous30Start && activity.watchedAt < last30Start {
                previous30DaysHours += hours
            }

            for range in PlaybillStatsRange.allCases {
                if let start = range.startDate(now: now, calendar: calendar), activity.watchedAt < start {
                    continue
                }
                rangeBuckets[range, default: PlaybillRangeAccumulator()].add(
                    activity: activity,
                    owner: owner,
                    hours: hours,
                    calendar: calendar
                )
            }
        }

        return PlaybillInsightSnapshot(
            previous30DaysHours: previous30DaysHours,
            ranges: rangeBuckets.mapValues { $0.stats() }
        )
    }
}

private struct PlaybillRangeAccumulator {
    var watches = 0
    var hours = 0.0
    var filmHours = 0.0
    var seriesHours = 0.0
    var days: Set<Date> = []
    var dayHours: [Date: Double] = [:]
    var targetCounts: [String: Int] = [:]
    var titleHours: [String: Double] = [:]
    var genreHours: [String: Double] = [:]
    var latestTitle: String?
    var latestWatchedAt: Date?

    mutating func add(
        activity: WatchActivity,
        owner: CatalogEntry,
        hours: Double,
        calendar: Calendar
    ) {
        watches += 1
        self.hours += hours
        let day = calendar.startOfDay(for: activity.watchedAt)
        days.insert(day)
        dayHours[day, default: 0] += hours
        targetCounts[activity.targetID, default: 0] += 1
        titleHours[owner.title, default: 0] += hours
        for genre in owner.genres {
            genreHours[genre, default: 0] += hours
        }
        if owner.kind == .movie {
            filmHours += hours
        } else {
            seriesHours += hours
        }
        if latestWatchedAt == nil || activity.watchedAt > latestWatchedAt! {
            latestTitle = owner.title
            latestWatchedAt = activity.watchedAt
        }
    }

    func stats() -> PlaybillRangeStats {
        PlaybillRangeStats(
            watches: watches,
            replays: targetCounts.values.filter { $0 > 1 }.reduce(0) { $0 + ($1 - 1) },
            hours: hours,
            activeDays: days.count,
            latestTitle: latestTitle,
            latestWatchedAt: latestWatchedAt,
            filmHours: filmHours,
            seriesHours: seriesHours,
            dayHours: dayHours,
            topTitles: titleHours
                .filter { $0.value > 0 }
                .sorted { lhs, rhs in lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value }
                .map { PlaybillRankedHours(label: $0.key, hours: $0.value) },
            topGenres: genreHours
                .filter { $0.value > 0 }
                .sorted { lhs, rhs in lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value }
                .map { PlaybillRankedHours(label: $0.key, hours: $0.value) }
        )
    }
}

struct PlaybillDataSection: View {
    @State private var statusMessage: String?
    @State private var importProgress: TraktImporter.ImportProgress?
    @State private var isImporting = false
    @State private var showImporter = false
    @State private var showTraktImporter = false

    var body: some View {
        KinemaCard(title: KinemaCopy.playbillDataTitle, icon: "arrow.triangle.2.circlepath") {
            VStack(alignment: .leading, spacing: 12) {
                Text(KinemaCopy.playbillDataSubtitle)
                    .font(KinemaType.metadata)
                    .foregroundStyle(KinemaTheme.secondaryText)

                HStack(spacing: 10) {
                    Button(KinemaCopy.playbillExport, action: exportBackup)
                        .buttonStyle(.bordered)
                        .disabled(isImporting)
                    Button(KinemaCopy.playbillImport, action: { showImporter = true })
                        .buttonStyle(.bordered)
                        .disabled(isImporting)
                    Button(KinemaCopy.playbillImportTrakt, action: { showTraktImporter = true })
                        .buttonStyle(.bordered)
                        .disabled(isImporting)
                }

                if let importProgress {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: importProgress.fraction)
                            .progressViewStyle(.linear)
                            .tint(KinemaTheme.brass)
                        Text(importProgress.message)
                            .font(KinemaType.metadata)
                            .foregroundStyle(KinemaTheme.secondaryText)
                    }
                }

                if let statusMessage {
                    Text(statusMessage)
                        .font(KinemaType.metadata)
                        .foregroundStyle(KinemaTheme.brass)
                }
            }
        }
        #if os(iOS) || os(macOS)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            handleImport(result, trakt: false)
        }
        .fileImporter(isPresented: $showTraktImporter, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            handleImport(result, trakt: true)
        }
        #endif
    }

    private func exportBackup() {
        do {
            let data = try PlaybillStore.exportBackup()
            #if os(macOS)
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "kinema-playbill-backup.json"
            if panel.runModal() == .OK, let url = panel.url {
                try data.write(to: url)
                statusMessage = KinemaCopy.playbillExportDone
            }
            #elseif os(iOS)
            shareData(data, filename: "kinema-playbill-backup.json")
            statusMessage = KinemaCopy.playbillExportDone
            #endif
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    #if os(iOS)
    private func shareData(_ data: Data, filename: String) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? data.write(to: url)
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        root.present(controller, animated: true)
    }
    #endif

    #if os(iOS) || os(macOS)
    private func handleImport(_ result: Result<[URL], Error>, trakt: Bool) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        Task {
            do {
                isImporting = true
                importProgress = trakt ? TraktImporter.ImportProgress(
                    processed: 0,
                    total: 1,
                    imported: 0,
                    message: "Preparing Trakt import..."
                ) : nil
                statusMessage = nil
                defer {
                    isImporting = false
                    importProgress = nil
                }
                guard url.startAccessingSecurityScopedResource() else { return }
                defer { url.stopAccessingSecurityScopedResource() }
                let data = try Data(contentsOf: url)
                if trakt {
                    let summary = try await TraktImporter.importHistorySummary(from: data) { progress in
                        importProgress = progress
                    }
                    statusMessage = traktImportStatusMessage(summary)
                } else {
                    let count = try PlaybillStore.importBackup(from: data, merge: true)
                    statusMessage = "Merged \(count) diary entries."
                }
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    private func traktImportStatusMessage(_ summary: TraktImportSummary) -> String {
        var parts = ["Imported \(summary.added) new Trakt \(summary.added == 1 ? "entry" : "entries")"]
        if summary.alreadyPresent > 0 {
            parts.append("\(summary.alreadyPresent) already present")
        }
        if summary.repaired > 0 {
            parts.append("repaired \(summary.repaired) Playbill \(summary.repaired == 1 ? "record" : "records")")
        }
        return parts.joined(separator: ", ") + "."
    }
    #endif
}

extension WatchSource {
    var displayBadge: String? {
        switch self {
        case .player: return "Kinema"
        case .manual: return nil
        case .importTrakt: return "Trakt"
        case .importBackup: return "Import"
        }
    }
}

extension PlaybillDiaryItem: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: PlaybillDiaryItem, rhs: PlaybillDiaryItem) -> Bool {
        lhs.id == rhs.id
    }
}
