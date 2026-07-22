import SwiftUI
import KinemaCore
import KinemaPlayback

public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    private var preferences: PreferencesStore { PreferencesStore.shared }

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    settingsHero
                    settingsCards
                }
                .padding(20)
            }
            .background(KinemaTheme.settingsBackground)
            .navigationTitle(KinemaCopy.preferences)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(KinemaCopy.done) { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 520, minHeight: 560)
        #endif
    }

    private var settingsHero: some View {
        KinemaSheetHero(
            icon: "gearshape.fill",
            title: KinemaCopy.appName,
            subtitle: "Tune playback, captions, and your collection."
        )
    }

    private var settingsCards: some View {
        VStack(spacing: 16) {
            KinemaCard(title: "Playback", icon: "play.circle") {
                SettingsToggleRow(title: "Resume playback", subtitle: "Continue videos from the last watched position.", isOn: binding(\.resumePlayback))
                SettingsSliderRow(title: "Default volume", valueText: "\(Int(preferences.preferences.volume))%", value: binding(\.volume), range: 0...100)
                SettingsSliderRow(title: "Playback speed", valueText: String(format: "%.2gx", preferences.preferences.speed), value: binding(\.speed), range: 0.25...4, step: 0.25)
                SettingsToggleRow(title: "Hardware decoding", subtitle: "Use VideoToolbox/mpv hardware paths when available.", isOn: binding(\.hardwareDecoding))
            }

            KinemaCard(title: KinemaCopy.captions, icon: "captions.bubble") {
                SettingsToggleRow(
                    title: "Auto-load captions",
                    subtitle: "Turn on embedded captions or matching sidecar files when a title starts.",
                    isOn: binding(\.autoLoadSubtitles)
                )
                Stepper("\(KinemaCopy.captionsSize): \(preferences.preferences.subtitleFontSize)",
                        value: binding(\.subtitleFontSize), in: 20...80)
            }

            #if os(macOS)
            KinemaCard(title: "macOS", icon: "macbook") {
                Toggle("Enable Music Mode window", isOn: binding(\.musicModeEnabled))
                Text("Open via Window → Music Mode when a track is playing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            #endif

            KinemaCard(title: "Keyboard Shortcuts", icon: "keyboard") {
                ForEach(KeyBindingDefaults.load()) { keyBinding in
                    HStack {
                        Text(keyBinding.description)
                            .font(.subheadline)
                        Spacer()
                        Text(keyBinding.keys.joined(separator: " · "))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
            }

            KinemaCard(title: "About", icon: "info.circle") {
                LabeledContent("Version", value: "1.0.0")
                LabeledContent("Engine", value: "libmpv")
                Text("κίνημα — motion, cinema")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func binding<T>(_ keyPath: WritableKeyPath<KinemaPreferences, T>) -> Binding<T> {
        Binding(
            get: { preferences.preferences[keyPath: keyPath] },
            set: { preferences.preferences[keyPath: keyPath] = $0 }
        )
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SettingsSliderRow: View {
    let title: String
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text(valueText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if let step {
                Slider(value: $value, in: range, step: step)
                    .tint(KinemaTheme.accent)
            } else {
                Slider(value: $value, in: range)
                    .tint(KinemaTheme.accent)
            }
        }
    }
}
