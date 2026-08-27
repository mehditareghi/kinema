import SwiftUI
import KinemaCore
import KinemaPlayback

public struct AudioSheet: View {
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
                        icon: "slider.horizontal.3",
                        title: "Audio",
                        subtitle: "Tracks, volume, equalizer, and effects for this playback."
                    )
                    tracksCard
                    volumeCard
                    equalizerCard
                    channelCard
                    effectsCard
                    compressorCard
                    pitchCard
                    Text("Preferred language, Replay Gain, output device, and visualizations are in Preferences.")
                        .font(KinemaType.metadata)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
                .padding(20)
            }
            .background(KinemaTheme.settingsBackground)
            .navigationTitle("Audio")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(KinemaCopy.done) { dismiss() }
                }
            }
            .onAppear {
                session.refreshCaptionTracks()
            }
            .tint(accent)
        }
        #if os(macOS)
        .frame(minWidth: 440, idealWidth: 480, minHeight: 560)
        #endif
    }

    private var tracksCard: some View {
        KinemaCard(title: "Audio tracks", icon: "waveform") {
            Button {
                session.selectAudioTrack(id: nil)
            } label: {
                trackRow(title: "Off", selected: session.activeAudioTrack == nil)
            }
            .buttonStyle(.plain)

            ForEach(session.audioTracks) { track in
                Button {
                    session.selectAudioTrack(id: track.id)
                } label: {
                    trackRow(
                        title: PlayerSession.audioTrackLabel(track),
                        selected: track.isSelected
                    )
                }
                .buttonStyle(.plain)
            }

            if session.audioTracks.count > 1 {
                Button("Cycle audio") {
                    session.cycleAudio()
                }
                .font(KinemaType.label)
            }
        }
    }

    private func trackRow(title: String, selected: Bool) -> some View {
        HStack {
            Text(title)
                .font(KinemaType.labelRegular)
                .foregroundStyle(.primary)
            Spacer()
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(accent)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var volumeCard: some View {
        KinemaCard(title: "Volume", icon: "speaker.wave.2") {
            HStack {
                Text("Level")
                Spacer()
                Text("\(Int(session.info.volume.rounded()))%")
                    .font(KinemaType.timecode)
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { session.info.volume },
                    set: { session.setVolume($0) }
                ),
                in: 0...KinemaPreferences.volumeMax
            )
            .tint(accent)

            Toggle(isOn: Binding(
                get: { preferences.preferences.isMuted },
                set: { muted in
                    viewModel.isMuted = muted
                    session.setMuted(muted)
                }
            )) {
                Text("Mute")
            }
            .tint(accent)
        }
    }

    private var equalizerCard: some View {
        KinemaCard(title: "Equalizer", icon: "slider.horizontal.3") {
            Toggle(isOn: prefBinding(\.audioEqualizerEnabled, apply: true)) {
                Text("Enable equalizer")
            }
            .tint(accent)

            HStack {
                Text("Preset")
                Spacer()
                Menu {
                    ForEach(AudioEqualizerCatalog.presets) { preset in
                        Button(preset.displayName) {
                            applyEqualizerPreset(preset)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(AudioEqualizerCatalog.preset(id: preferences.preferences.audioEqualizerPresetID).displayName)
                            .font(KinemaType.label)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(KinemaType.microStrong)
                            .foregroundStyle(accent)
                    }
                }
                .buttonStyle(.plain)
            }

            HStack {
                Text("Preamp")
                Spacer()
                Text(String(format: "%+.1f dB", preferences.preferences.audioEqualizerPreamp))
                    .font(KinemaType.timecode)
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { preferences.preferences.audioEqualizerPreamp },
                    set: { value in
                        preferences.preferences.audioEqualizerPreamp = value
                        preferences.preferences.audioEqualizerPresetID = "custom"
                        session.applyAudioPipeline()
                    }
                ),
                in: -20...20
            )
            .tint(accent)
            .disabled(!preferences.preferences.audioEqualizerEnabled)

            ForEach(0..<10, id: \.self) { index in
                HStack(spacing: 10) {
                    Text(AudioEqualizerCatalog.bandLabels[index])
                        .font(KinemaType.timecode)
                        .frame(width: 36, alignment: .leading)
                        .foregroundStyle(.secondary)
                    Slider(
                        value: Binding(
                            get: {
                                let bands = preferences.preferences.audioEqualizerBands
                                return index < bands.count ? bands[index] : 0
                            },
                            set: { value in
                                var bands = AudioEqualizerCatalog.normalizedBands(preferences.preferences.audioEqualizerBands)
                                bands[index] = value
                                preferences.preferences.audioEqualizerBands = bands
                                preferences.preferences.audioEqualizerPresetID = "custom"
                                session.applyAudioPipeline()
                            }
                        ),
                        in: -20...20
                    )
                    .tint(accent)
                    Text(String(format: "%+.0f", index < preferences.preferences.audioEqualizerBands.count
                               ? preferences.preferences.audioEqualizerBands[index] : 0))
                        .font(KinemaType.timecodeSmall)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, alignment: .trailing)
                }
                .disabled(!preferences.preferences.audioEqualizerEnabled)
            }
        }
    }

    private var channelCard: some View {
        KinemaCard(title: "Channels", icon: "hifispeaker.2") {
            HStack {
                Text("Mode")
                Spacer()
                Menu {
                    ForEach(AudioChannelMode.allCases) { mode in
                        Button(mode.displayName) {
                            preferences.preferences.audioChannelMode = mode
                            if mode != .stereo {
                                preferences.preferences.audioForceMono = false
                            }
                            session.applyAudioPipeline()
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(preferences.preferences.audioChannelMode.displayName)
                            .font(KinemaType.label)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(KinemaType.microStrong)
                            .foregroundStyle(accent)
                    }
                }
                .buttonStyle(.plain)
                .disabled(preferences.preferences.audioForceMono)
            }

            Toggle(isOn: Binding(
                get: { preferences.preferences.audioForceMono },
                set: { value in
                    preferences.preferences.audioForceMono = value
                    session.applyAudioPipeline()
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Force mono")
                    Text("Downmix all channels to mono.")
                        .font(KinemaType.metadata)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(accent)
        }
    }

    private var effectsCard: some View {
        KinemaCard(title: "Effects", icon: "waveform.path") {
            Toggle(isOn: prefBinding(\.audioNormalizeEnabled, apply: true)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Normalize volume")
                    Text("Smooth quiet and loud passages.")
                        .font(KinemaType.metadata)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(accent)

            Toggle(isOn: prefBinding(\.audioHeadphoneVirtualizer, apply: true)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Headphone virtualization")
                    Text("Earwax crossfeed for headphones.")
                        .font(KinemaType.metadata)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(accent)

            Toggle(isOn: prefBinding(\.audioStereoWidenerEnabled, apply: true)) {
                Text("Stereo widener")
            }
            .tint(accent)

            if preferences.preferences.audioStereoWidenerEnabled {
                HStack {
                    Text("Width")
                    Spacer()
                    Text(String(format: "%.1f", preferences.preferences.audioStereoWidenerAmount))
                        .font(KinemaType.timecode)
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { preferences.preferences.audioStereoWidenerAmount },
                        set: {
                            preferences.preferences.audioStereoWidenerAmount = $0
                            session.applyAudioPipeline()
                        }
                    ),
                    in: 0...4
                )
                .tint(accent)
            }

            Toggle(isOn: prefBinding(\.audioSpatializerEnabled, apply: true)) {
                Text("Spatializer")
            }
            .tint(accent)

            if preferences.preferences.audioSpatializerEnabled {
                HStack {
                    Text("Amount")
                    Spacer()
                    Text(String(format: "%.0f%%", preferences.preferences.audioSpatializerAmount * 100))
                        .font(KinemaType.timecode)
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { preferences.preferences.audioSpatializerAmount },
                        set: {
                            preferences.preferences.audioSpatializerAmount = $0
                            session.applyAudioPipeline()
                        }
                    ),
                    in: 0...1
                )
                .tint(accent)
            }
        }
    }

    private var compressorCard: some View {
        KinemaCard(title: "Compressor", icon: "chart.bar.xaxis") {
            Toggle(isOn: prefBinding(\.audioCompressorEnabled, apply: true)) {
                Text("Enable compressor")
            }
            .tint(accent)

            Group {
                effectSlider(
                    title: "Threshold",
                    valueText: String(format: "%.0f dB", preferences.preferences.audioCompressorThreshold),
                    value: prefBinding(\.audioCompressorThreshold, apply: true),
                    range: -60...0
                )
                effectSlider(
                    title: "Ratio",
                    valueText: String(format: "%.1f:1", preferences.preferences.audioCompressorRatio),
                    value: prefBinding(\.audioCompressorRatio, apply: true),
                    range: 1...20
                )
                effectSlider(
                    title: "Attack",
                    valueText: String(format: "%.0f ms", preferences.preferences.audioCompressorAttack),
                    value: prefBinding(\.audioCompressorAttack, apply: true),
                    range: 1...200
                )
                effectSlider(
                    title: "Release",
                    valueText: String(format: "%.0f ms", preferences.preferences.audioCompressorRelease),
                    value: prefBinding(\.audioCompressorRelease, apply: true),
                    range: 10...2000
                )
                effectSlider(
                    title: "Makeup",
                    valueText: String(format: "%+.1f dB", preferences.preferences.audioCompressorMakeup),
                    value: prefBinding(\.audioCompressorMakeup, apply: true),
                    range: 0...24
                )
            }
            .disabled(!preferences.preferences.audioCompressorEnabled)
        }
    }

    private var pitchCard: some View {
        KinemaCard(title: "Pitch", icon: "tuningfork") {
            HStack {
                Text("Pitch scale")
                Spacer()
                Text(String(format: "%.2f×", preferences.preferences.audioPitchScale))
                    .font(KinemaType.timecode)
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { preferences.preferences.audioPitchScale },
                    set: {
                        preferences.preferences.audioPitchScale = $0
                        session.applyAudioPipeline()
                    }
                ),
                in: 0.5...1.5,
                step: 0.01
            )
            .tint(accent)

            Button("Reset pitch") {
                preferences.preferences.audioPitchScale = 1
                session.applyAudioPipeline()
            }
            .font(KinemaType.label)
        }
    }

    private func applyEqualizerPreset(_ preset: AudioEqualizerPreset) {
        preferences.preferences.audioEqualizerPresetID = preset.id
        preferences.preferences.audioEqualizerBands = preset.bands
        preferences.preferences.audioEqualizerPreamp = preset.preamp
        preferences.preferences.audioEqualizerEnabled = true
        session.applyAudioPipeline()
    }

    private func prefBinding<T>(
        _ keyPath: WritableKeyPath<KinemaPreferences, T>,
        apply: Bool
    ) -> Binding<T> {
        Binding(
            get: { preferences.preferences[keyPath: keyPath] },
            set: { value in
                preferences.preferences[keyPath: keyPath] = value
                if apply {
                    session.applyAudioPipeline()
                }
            }
        )
    }

    private func effectSlider(
        title: String,
        valueText: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(valueText)
                    .font(KinemaType.timecode)
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
                .tint(accent)
        }
    }
}

/// Lightweight reactive bars — decorative, not a real FFT.
public struct AudioVisualizationOverlay: View {
    let volume: Double
    let isPaused: Bool
    let isMuted: Bool

    @State private var phase: Double = 0
    private let barCount = 24

    public init(volume: Double, isPaused: Bool, isMuted: Bool) {
        self.volume = volume
        self.isPaused = isPaused
        self.isMuted = isMuted
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: isPaused || isMuted)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule()
                        .fill(KinemaTheme.accent.opacity(0.55 + 0.35 * barHeight(index: index, t: t)))
                        .frame(width: 4, height: 8 + 56 * barHeight(index: index, t: t))
                }
            }
            .frame(maxWidth: 220)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .kinemaLiquidGlass(cornerRadius: 18)
            .opacity(isMuted ? 0.35 : 1)
        }
        .allowsHitTesting(false)
    }

    private func barHeight(index: Int, t: Double) -> Double {
        guard !isPaused, !isMuted else { return 0.12 }
        let level = min(1, max(0.05, volume / KinemaPreferences.volumeMax))
        let wave = sin(t * 6.2 + Double(index) * 0.55) * 0.5 + 0.5
        let pulse = sin(t * 2.4 + Double(index) * 0.2) * 0.5 + 0.5
        return min(1, (0.25 + 0.75 * level) * (0.35 + 0.65 * wave * pulse))
    }
}
