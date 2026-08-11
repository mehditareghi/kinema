import SwiftUI
import KinemaCore
import KinemaPlayback

public struct VideoFiltersSheet: View {
    @Bindable var viewModel: PlayerViewModel
    @Bindable private var preferences = PreferencesStore.shared
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
                    KinemaSheetHero(
                        icon: "camera.filters",
                        title: KinemaCopy.videoFilters,
                        subtitle: "Brightness, contrast, and light enhance filters — applied live."
                    )
                    equalizerCard
                    enhanceCard
                    if !preferences.videoFilters.isAtDefaults {
                        Button {
                            preferences.videoFilters = VideoFilterSettings()
                            session.applyVideoFilters()
                        } label: {
                            Label(KinemaCopy.videoFiltersReset, systemImage: "arrow.counterclockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(accent)
                    }
                }
                .padding(20)
            }
            .background(KinemaTheme.settingsBackground)
            .navigationTitle(KinemaCopy.videoFilters)
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

    private var equalizerCard: some View {
        KinemaCard(title: "Equalizer", icon: "sun.max") {
            filterSlider(
                title: "Brightness",
                value: filterBinding(\.brightness),
                range: VideoFilterSettings.equalizerRange
            )
            filterSlider(
                title: "Contrast",
                value: filterBinding(\.contrast),
                range: VideoFilterSettings.equalizerRange
            )
            filterSlider(
                title: "Saturation",
                value: filterBinding(\.saturation),
                range: VideoFilterSettings.equalizerRange
            )
            filterSlider(
                title: "Gamma",
                value: filterBinding(\.gamma),
                range: VideoFilterSettings.equalizerRange
            )
        }
    }

    private var enhanceCard: some View {
        KinemaCard(title: "Enhance", icon: "sparkles") {
            Toggle("Deband", isOn: filterBinding(\.debandEnabled))
                .tint(accent)
            Text("Smooths banding in gradients and dark scenes.")
                .font(.caption)
                .foregroundStyle(.secondary)

            filterSlider(
                title: "Sharpen",
                value: filterBinding(\.sharpen),
                range: VideoFilterSettings.sharpenRange,
                format: { String(format: "%.1f", $0) }
            )
            Text("0 is off. Higher values can look harsh on soft sources.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func filterBinding<T>(_ keyPath: WritableKeyPath<VideoFilterSettings, T>) -> Binding<T> {
        Binding(
            get: { preferences.videoFilters[keyPath: keyPath] },
            set: { value in
                preferences.videoFilters[keyPath: keyPath] = value
                session.applyVideoFilters()
            }
        )
    }

    private func filterSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: ((Double) -> String)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(format?(value.wrappedValue) ?? Self.formatEqualizer(value.wrappedValue))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
                .tint(accent)
        }
    }

    private static func formatEqualizer(_ value: Double) -> String {
        let rounded = value.rounded()
        if abs(rounded) < 0.5 { return "0" }
        return String(format: "%.0f", rounded)
    }
}
