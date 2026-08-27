import SwiftUI
import KinemaCore
import KinemaPlayback

public struct ChaptersSheet: View {
    @Bindable var viewModel: PlayerViewModel
    @Environment(\.dismiss) private var dismiss

    public init(viewModel: PlayerViewModel) {
        self.viewModel = viewModel
    }

    private var session: PlayerSession { viewModel.session }
    private var accent: Color { KinemaTheme.accent }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    chaptersCard
                }
                .padding(20)
            }
            .background(KinemaTheme.settingsBackground)
            .navigationTitle(KinemaCopy.chapters)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(KinemaCopy.done) { dismiss() }
                }
            }
            .tint(accent)
        }
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 460, minHeight: 480)
        #endif
    }

    private var hero: some View {
        let current = session.currentChapter
        return KinemaSheetHero(
            icon: "list.bullet.rectangle",
            title: current?.displayTitle ?? KinemaCopy.chapters,
            subtitle: heroSubtitle(current: current)
        )
    }

    private func heroSubtitle(current: Chapter?) -> String {
        let count = session.chapters.count
        if count == 0 {
            return KinemaCopy.chaptersNoneAvailable
        }
        if let current, let index = session.currentChapterIndex {
            return "\(index + 1) of \(count) · \(formatTime(current.time))"
        }
        return "\(count) chapter\(count == 1 ? "" : "s") in this title"
    }

    private var chaptersCard: some View {
        KinemaCard(title: KinemaCopy.chapters, icon: "bookmark") {
            if session.chapters.isEmpty {
                Text(KinemaCopy.chaptersNoneAvailable)
                    .font(KinemaType.note)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(session.chapters.enumerated()), id: \.element.id) { index, chapter in
                    chapterRow(chapter: chapter, index: index)
                }
            }
        }
    }

    private func chapterRow(chapter: Chapter, index: Int) -> some View {
        let isCurrent = session.currentChapterIndex == index
        return Button {
            session.seekToChapter(chapter)
            viewModel.showOSD(chapter.displayTitle)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Text(String(format: "%02d", index + 1))
                    .font(KinemaType.timecode.weight(.bold))
                    .foregroundStyle(isCurrent ? accent : .secondary)
                    .frame(width: 28, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(chapter.displayTitle)
                        .font(KinemaType.labelRegular.weight(isCurrent ? .semibold : .medium))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Text(formatTime(chapter.time))
                        .font(KinemaType.timecode)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if isCurrent {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(KinemaType.bodyStrong)
                        .foregroundStyle(accent)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isCurrent ? accent.opacity(0.12) : Color.primary.opacity(0.04))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isCurrent ? accent.opacity(0.28) : Color.primary.opacity(0.05),
                        lineWidth: 0.5
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(chapter.displayTitle), \(formatTime(chapter.time))")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}
