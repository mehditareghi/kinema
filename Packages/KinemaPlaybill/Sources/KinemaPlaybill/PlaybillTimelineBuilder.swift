import Foundation

@MainActor
public enum PlaybillTimelineBuilder {
    public static func build(limitHistory: Int = 80) async -> [PlaybillTimelineSection] {
        var sections: [PlaybillTimelineSection] = []

        var catchUpRows: [PlaybillTimelineRow] = []
        var upNextRows: [PlaybillTimelineRow] = []

        for tracked in PlaybillStore.trackedShows() {
            guard tracked.status == .watching || tracked.status == .planToWatch else { continue }
            guard let summary = await PlaybillShowProgress.progressSummary(for: tracked.targetID) else { continue }

            if summary.missedAiredCount > 0, let next = summary.nextEpisode {
                catchUpRows.append(
                    PlaybillTimelineRow(
                        id: "catchup-\(tracked.targetID)",
                        entry: next,
                        showEntry: summary.show,
                        subtitle: next.subtitle ?? summary.show.title,
                        badge: "\(summary.missedAiredCount) new",
                        missedCount: summary.missedAiredCount
                    )
                )
            }

            if let next = summary.nextEpisode {
                let code = next.seasonNumber.flatMap { s in
                    next.episodeNumber.map { e in String(format: "S%02dE%02d", s, e) }
                } ?? "Next up"
                upNextRows.append(
                    PlaybillTimelineRow(
                        id: "upnext-\(tracked.targetID)",
                        entry: next,
                        showEntry: summary.show,
                        subtitle: next.subtitle ?? summary.show.title,
                        badge: code
                    )
                )
            } else if summary.watchedEpisodeCount == 0 {
                upNextRows.append(
                    PlaybillTimelineRow(
                        id: "upnext-\(tracked.targetID)",
                        entry: summary.show,
                        subtitle: "Start watching",
                        badge: "Track"
                    )
                )
            }
        }

        if !catchUpRows.isEmpty {
            sections.append(PlaybillTimelineSection(
                id: "catch-up",
                title: "Catch up",
                subtitle: "Episodes you missed while away",
                kind: .catchUp,
                items: catchUpRows
            ))
        }

        if !upNextRows.isEmpty {
            sections.append(PlaybillTimelineSection(
                id: "up-next",
                title: "Up next",
                subtitle: "What to watch next in your tracked series",
                kind: .upNext,
                items: upNextRows
            ))
        }

        sections.append(contentsOf: buildContinueAndHistory(limitHistory: limitHistory))
        return sections
    }

    /// Continue + history only — no TMDB / progressSummary work.
    public static func buildContinueAndHistory(limitHistory: Int = 80) -> [PlaybillTimelineSection] {
        var sections: [PlaybillTimelineSection] = []

        let continueRows = PlaybillStore.continueItems(limit: 24).map { item in
            PlaybillTimelineRow(
                entry: item.entry,
                subtitle: "Resume \(formatTime(item.progress.position))",
                badge: "In progress",
                date: item.progress.updatedAt,
                progress: item.progress
            )
        }
        if !continueRows.isEmpty {
            sections.append(PlaybillTimelineSection(
                id: "continue",
                title: "Continue",
                subtitle: nil,
                kind: .continueWatching,
                items: continueRows
            ))
        }

        sections.append(contentsOf: historyGrouped(limit: limitHistory))
        return sections
    }

    private static func historyGrouped(limit: Int) -> [PlaybillTimelineSection] {
        let items = PlaybillStore.diaryItems(limit: limit)
        guard !items.isEmpty else { return [] }

        let calendar = Calendar.current
        var grouped: [(Date, [PlaybillTimelineRow])] = []
        var currentDay: Date?
        var currentRows: [PlaybillTimelineRow] = []

        for item in items {
            let day = calendar.startOfDay(for: item.activity.watchedAt)
            if currentDay != day {
                if let currentDay, !currentRows.isEmpty {
                    grouped.append((currentDay, currentRows))
                }
                currentDay = day
                currentRows = []
            }
            currentRows.append(
                PlaybillTimelineRow(
                    id: item.id.uuidString,
                    entry: item.entry,
                    showEntry: parentShow(for: item.entry),
                    subtitle: historySubtitle(for: item),
                    badge: item.activity.source.displayBadge,
                    date: item.activity.watchedAt,
                    activityID: item.activity.id
                )
            )
        }
        if let currentDay, !currentRows.isEmpty {
            grouped.append((currentDay, currentRows))
        }

        return grouped.map { day, rows in
            PlaybillTimelineSection(
                id: "history-\(day.timeIntervalSince1970)",
                title: historyDayTitle(day),
                subtitle: nil,
                kind: .history,
                items: rows
            )
        }
    }

    private static func parentShow(for entry: CatalogEntry) -> CatalogEntry? {
        guard entry.kind == .episode, let parentID = entry.parentShowID else { return nil }
        return PlaybillStore.entry(for: parentID)
    }

    private static func historySubtitle(for item: PlaybillDiaryItem) -> String {
        switch item.entry.kind {
        case .episode:
            if let season = item.entry.seasonNumber, let episode = item.entry.episodeNumber {
                let code = String(format: "S%02dE%02d", season, episode)
                if let subtitle = item.entry.subtitle, !subtitle.isEmpty {
                    return "\(code) · \(subtitle)"
                }
                return code
            }
            return item.entry.title
        case .movie:
            return "Film"
        case .tvShow:
            return "Series"
        }
    }

    private static func historyDayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: day)
    }

    private static func formatTime(_ interval: TimeInterval) -> String {
        guard interval.isFinite, interval >= 0 else { return "0:00" }
        let total = Int(interval)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private extension WatchSource {
    var displayBadge: String? {
        switch self {
        case .player: return "Kinema"
        case .manual: return "Manual"
        case .importTrakt: return "Trakt"
        case .importBackup: return "Import"
        }
    }
}
