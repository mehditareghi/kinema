import SwiftUI
import KinemaPlaybill
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// Shown during playback when Playbill has medium-confidence title matches.
struct PlaybillMatchOverlay: View {
    let prompt: PlaybillMatchPrompt
    let accent: Color
    let onConfirm: (PlaybillMatchCandidate) -> Void
    let onSkip: () -> Void

    @State private var appeared = false
    @State private var isConfirming = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.62)
                .ignoresSafeArea()

            VStack {
                Spacer(minLength: 0)
                card
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
                    .frame(maxWidth: 520)
                    .frame(maxWidth: .infinity)
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 24)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) {
                appeared = true
            }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("LOG TO PLAYBILL")
                    .font(KinemaType.eyebrow)
                    .tracking(2)
                    .foregroundStyle(KinemaTheme.brass)
                Text(KinemaCopy.playbillMatchTitle)
                    .font(KinemaType.cardTitle)
                    .foregroundStyle(KinemaTheme.paper)
                Text(KinemaCopy.playbillMatchSubtitle)
                    .font(KinemaType.metadata)
                    .foregroundStyle(KinemaTheme.secondaryText)
            }

            VStack(spacing: 8) {
                ForEach(prompt.candidates.prefix(4)) { candidate in
                    Button {
                        guard !isConfirming else { return }
                        isConfirming = true
                        onConfirm(candidate)
                    } label: {
                        PlaybillSearchRow(result: candidate.result)
                    }
                    .buttonStyle(.plain)
                    .disabled(isConfirming)
                }
            }

            Button(action: onSkip) {
                KinemaComposerButtonLabel(KinemaCopy.playbillMatchSkip)
            }
            .buttonStyle(.bordered)
            .tint(KinemaTheme.secondaryText)
            .kinemaComposerButtonStyle()
            .disabled(isConfirming)
        }
        .padding(20)
        .background(KinemaTheme.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(KinemaTheme.hairline.opacity(0.85), lineWidth: 0.6)
        }
        .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
    }
}

/// Shared TMDB API key field + save — Open Stream-style composer used in Playbill tab and Preferences.
struct PlaybillTMDBKeyEntry: View {
    @Binding var apiKey: String
    var saveTitle: String = KinemaCopy.playbillSaveKey
    var secondaryAction: SecondaryAction?
    var onSaved: (() -> Void)?

    struct SecondaryAction {
        let title: String
        let systemImage: String
        let action: () -> Void
    }

    @State private var draftKey = ""
    @FocusState private var focused: Bool

    private var accent: Color { KinemaTheme.accent }
    private var trimmedDraft: String {
        draftKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var trimmedStored: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var isDirty: Bool { trimmedDraft != trimmedStored }
    private var canSave: Bool { !trimmedDraft.isEmpty && isDirty }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            KinemaComposerField(
                icon: "key.fill",
                placeholder: KinemaCopy.playbillAPIKeyPlaceholder,
                text: $draftKey,
                isSecure: true,
                accent: accent,
                isFocused: $focused,
                onSubmit: save,
                onPaste: pasteKey
            )

            apiKeyStatus

            KinemaComposerActionLayout {
                keyActions
            }
        }
        .onAppear {
            draftKey = apiKey
            if draftKey.isEmpty {
                focused = true
            }
        }
        .onChange(of: apiKey) { _, newValue in
            if !isDirty {
                draftKey = newValue
            }
        }
    }

    @ViewBuilder
    private var keyActions: some View {
        Button(action: save) {
            KinemaComposerButtonLabel(saveTitle, systemImage: "checkmark.circle.fill")
        }
        .buttonStyle(.borderedProminent)
        .tint(accent)
        .kinemaComposerButtonStyle()
        .disabled(!canSave)

        if let secondaryAction {
            Button(action: secondaryAction.action) {
                KinemaComposerButtonLabel(secondaryAction.title, systemImage: secondaryAction.systemImage)
            }
            .buttonStyle(.bordered)
            .tint(accent)
            .kinemaComposerButtonStyle()
        }
    }

    @ViewBuilder
    private var apiKeyStatus: some View {
        if trimmedDraft.isEmpty {
            Label(KinemaCopy.playbillTMDBHint, systemImage: "info.circle")
                .font(KinemaType.metadata)
                .foregroundStyle(KinemaTheme.secondaryText)
        } else if canSave {
            Label("Ready to save", systemImage: "checkmark.circle.fill")
                .font(KinemaType.metadata)
                .foregroundStyle(accent)
        } else {
            Label(KinemaCopy.playbillKeySaved, systemImage: "checkmark.circle.fill")
                .font(KinemaType.metadata)
                .foregroundStyle(accent)
        }
    }

    private func save() {
        let trimmed = trimmedDraft
        guard !trimmed.isEmpty else { return }
        apiKey = trimmed
        PlaybillPreferencesStore.tmdbAPIKey = trimmed
        draftKey = trimmed
        focused = false
        onSaved?()
    }

    private func pasteKey() {
        #if os(iOS)
        guard let value = UIPasteboard.general.string else { return }
        #elseif os(macOS)
        guard let value = NSPasteboard.general.string(forType: .string) else { return }
        #else
        return
        #endif
        draftKey = value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Inline TMDB key entry — used on the Playbill tab when Playbill is not configured yet.
struct PlaybillAPIKeyCard: View {
    @Binding var apiKey: String
    var showsPreferencesLink: Bool = true
    var onSaved: (() -> Void)?
    var onOpenPreferences: (() -> Void)?

    var body: some View {
        KinemaCard(title: KinemaCopy.playbillSetupTitle, icon: "key.fill") {
            Text(KinemaCopy.playbillSetupMessage)
                .font(KinemaType.label)
                .foregroundStyle(KinemaTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            PlaybillTMDBKeyEntry(
                apiKey: $apiKey,
                secondaryAction: showsPreferencesLink && onOpenPreferences != nil
                    ? PlaybillTMDBKeyEntry.SecondaryAction(
                        title: KinemaCopy.playbillMoreSettings,
                        systemImage: "gearshape",
                        action: onOpenPreferences!
                    )
                    : nil,
                onSaved: onSaved
            )
        }
    }
}
