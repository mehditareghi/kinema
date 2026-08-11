import SwiftUI
import KinemaCore
import KinemaPlayback
import KinemaSharing

public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    private var preferences: PreferencesStore { PreferencesStore.shared }
    @State private var fontFamilies: [SubtitleFontOption] = []

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
            .onAppear {
                _ = SubtitleFontRegistry.prepare()
                if fontFamilies.isEmpty {
                    fontFamilies = SubtitleFontRegistry.availableFontFamilies()
                }
            }
            .tint(KinemaTheme.accent)
        }
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 520, minHeight: 560)
        #endif
    }

    private var settingsHero: some View {
        KinemaSheetHero(
            icon: "gearshape.fill",
            title: KinemaCopy.appName,
            subtitle: "Tune playback, subtitles, and your collection."
        )
    }

    private var settingsCards: some View {
        VStack(spacing: 16) {
            KinemaCard(title: "Playback", icon: "play.circle") {
                SettingsToggleRow(title: "Resume playback", subtitle: "Continue videos from the last watched position.", isOn: binding(\.resumePlayback))
                SettingsToggleRow(
                    title: KinemaCopy.upNext,
                    subtitle: KinemaCopy.upNextSettingsSubtitle,
                    isOn: binding(\.seriesUpNextEnabled)
                )
                SettingsMenuRow(
                    title: KinemaCopy.seekStep,
                    value: preferences.preferences.seekStep.displayName
                ) {
                    ForEach(SeekStep.allCases) { step in
                        Button(step.displayName) {
                            preferences.preferences.seekStep = step
                            NowPlayingController.shared.refreshSkipIntervals()
                        }
                    }
                }
                Text("Applies to seek buttons, double-tap, keyboard arrows, and Lock Screen skip.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SettingsSliderRow(title: "Default volume", valueText: "\(Int(preferences.preferences.volume))%", value: Binding(
                    get: { preferences.preferences.volume },
                    set: { PlayerSessionPool.sharedSession().setVolume($0) }
                ), range: 0...KinemaPreferences.volumeMax)
                SettingsSliderRow(title: "Playback speed", valueText: PlaybackSpeedControl.formatSpeed(preferences.preferences.speed), value: Binding(
                    get: { preferences.preferences.speed },
                    set: { PlayerSessionPool.sharedSession().setSpeed($0) }
                ), range: 0.25...4, step: 0.25)
                SettingsToggleRow(title: "Hardware decoding", subtitle: "Use VideoToolbox/mpv hardware paths when available.", isOn: binding(\.hardwareDecoding))
                VStack(alignment: .leading, spacing: 6) {
                    SettingsMenuRow(
                        title: KinemaCopy.hdrToneMapping,
                        value: preferences.preferences.hdrToneMappingMode.displayName
                    ) {
                        ForEach(HDRToneMappingMode.allCases) { mode in
                            Button(mode.displayName) {
                                preferences.preferences.hdrToneMappingMode = mode
                                PlayerSessionPool.sharedSession().applyHDRToneMappingPreferences()
                            }
                        }
                    }
                    Text(KinemaCopy.hdrToneMappingSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                SettingsSliderRow(
                    title: KinemaCopy.hdrTargetPeak,
                    valueText: "\(Int(preferences.preferences.hdrTargetPeak.rounded())) nits",
                    value: Binding(
                        get: { preferences.preferences.hdrTargetPeak },
                        set: { peak in
                            preferences.preferences.hdrTargetPeak = KinemaPreferences.clampHDRTargetPeak(peak)
                            PlayerSessionPool.sharedSession().applyHDRToneMappingPreferences()
                        }
                    ),
                    range: KinemaPreferences.hdrTargetPeakRange,
                    step: 50
                )
            }

            AudioSettingsCard()

            KinemaCard(title: KinemaCopy.captions, icon: "captions.bubble") {
                SettingsToggleRow(
                    title: KinemaCopy.captionsAutoLoad,
                    subtitle: KinemaCopy.captionsAutoLoadSubtitle,
                    isOn: binding(\.autoLoadSubtitles)
                )

                SettingsToggleRow(
                    title: "Prefer SDH / CC",
                    subtitle: "Prefer hearing-impaired caption tracks when available.",
                    isOn: binding(\.preferSDHSubtitles)
                )

                SettingsToggleRow(
                    title: "Forced only",
                    subtitle: "Prefer forced subtitle tracks for auto-select.",
                    isOn: binding(\.forcedSubtitlesOnly)
                )

                SettingsMenuRow(
                    title: "Preferred language",
                    value: SubtitlePreferenceCatalog.language(id: preferences.preferences.preferredSubtitleLanguage).displayName
                ) {
                    ForEach(SubtitlePreferenceCatalog.popularLanguages) { language in
                        Button(language.displayName) {
                            preferences.preferences.preferredSubtitleLanguage = language.id
                        }
                    }
                }

                SettingsMenuRow(
                    title: KinemaCopy.captionsFont,
                    value: selectedFontDisplayName
                ) {
                    ForEach(fontFamilies) { font in
                        Button(font.displayName) {
                            preferences.preferences.subtitleFontID = font.id
                        }
                    }
                }

                SettingsColorSwatchRow(
                    title: KinemaCopy.captionsColor,
                    hex: binding(\.subtitleColorHex)
                )

                SettingsColorSwatchRow(
                    title: "Outline color",
                    hex: binding(\.subtitleBorderColorHex)
                )

                SettingsColorSwatchRow(
                    title: "Shadow color",
                    hex: binding(\.subtitleShadowColorHex)
                )

                SettingsColorSwatchRow(
                    title: "Backdrop color",
                    hex: binding(\.subtitleBackColorHex)
                )

                SettingsSliderRow(
                    title: KinemaCopy.captionsSize,
                    valueText: "\(preferences.preferences.subtitleFontSize)",
                    value: Binding(
                        get: { Double(preferences.preferences.subtitleFontSize) },
                        set: { preferences.preferences.subtitleFontSize = Int($0.rounded()) }
                    ),
                    range: 20...80,
                    step: 1
                )

                SettingsSliderRow(
                    title: "Outline size",
                    valueText: String(format: "%.1f", preferences.preferences.subtitleBorderSize),
                    value: binding(\.subtitleBorderSize),
                    range: 0...8,
                    step: 0.5
                )

                SettingsSliderRow(
                    title: "Shadow offset",
                    valueText: String(format: "%.1f", preferences.preferences.subtitleShadowOffset),
                    value: binding(\.subtitleShadowOffset),
                    range: 0...8,
                    step: 0.5
                )

                SubtitlePlacementGrid(
                    title: "Placement",
                    selection: SubtitlePlacementAnchor.nearest(
                        alignX: preferences.preferences.subtitleAlignX,
                        verticalPos: preferences.preferences.subtitlePos
                    )
                ) { anchor in
                    preferences.preferences.subtitleAlignX = anchor.alignX
                    preferences.preferences.subtitleAlignY = anchor.alignY
                    preferences.preferences.subtitlePos = anchor.verticalPos
                    preferences.preferences.secondarySubtitleAlignX = anchor.alignX
                }

                SettingsSliderRow(
                    title: "Vertical fine-tune",
                    valueText: "\(preferences.preferences.subtitlePos)",
                    value: Binding(
                        get: { Double(preferences.preferences.subtitlePos) },
                        set: { preferences.preferences.subtitlePos = Int($0.rounded()) }
                    ),
                    range: 0...100,
                    step: 1
                )

                SettingsMenuRow(
                    title: "ASS override",
                    value: preferences.preferences.subtitleASSOverride.displayName
                ) {
                    ForEach(SubtitleASSOverrideMode.allCases) { mode in
                        Button(mode.displayName) {
                            preferences.preferences.subtitleASSOverride = mode
                        }
                    }
                }

                SettingsToggleRow(
                    title: "Bold",
                    subtitle: "Prefer bold text styling.",
                    isOn: binding(\.subtitleBold)
                )

                SettingsToggleRow(
                    title: "Italic",
                    subtitle: "Prefer italic text styling.",
                    isOn: binding(\.subtitleItalic)
                )

                SettingsToggleRow(
                    title: "Fade-out",
                    subtitle: "Soft ASS blur approximation when force styles are enabled.",
                    isOn: binding(\.subtitleFadeOut)
                )

                SettingsMenuRow(
                    title: KinemaCopy.captionsEncoding,
                    value: selectedEncodingDisplayName
                ) {
                    ForEach(SubtitlePreferenceCatalog.encodings) { encoding in
                        Button(encoding.displayName) {
                            preferences.preferences.subtitleEncodingID = encoding.id
                        }
                    }
                }
            }

            #if os(macOS)
            KinemaCard(title: "macOS", icon: "macbook") {
                Toggle("Enable Music Mode window", isOn: binding(\.musicModeEnabled))
                    .tint(KinemaTheme.accent)
                Text("Open via Window → Music Mode when a track is playing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            #endif

            WiFiSharingSettingsCard()

            KinemaCard(title: "Keyboard Shortcuts", icon: "keyboard") {
                KeyBindingsSettingsSection()
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

    private var selectedFontDisplayName: String {
        SubtitleFontRegistry.resolveStoredFontSelection(preferences.preferences.subtitleFontID).displayName
    }

    private var selectedEncodingDisplayName: String {
        SubtitlePreferenceCatalog.encoding(id: preferences.preferences.subtitleEncodingID).displayName
    }

    private func binding<T>(_ keyPath: WritableKeyPath<KinemaPreferences, T>) -> Binding<T> {
        Binding(
            get: { preferences.preferences[keyPath: keyPath] },
            set: { preferences.preferences[keyPath: keyPath] = $0 }
        )
    }
}

private struct AudioSettingsCard: View {
    private var preferences: PreferencesStore { PreferencesStore.shared }
    @State private var devices: [PlayerSession.AudioOutputDevice] = []

    var body: some View {
        KinemaCard(title: KinemaCopy.audio, icon: "speaker.wave.3") {
            SettingsMenuRow(
                title: "Preferred language",
                value: SubtitlePreferenceCatalog.language(id: preferences.preferences.preferredAudioLanguage).displayName
            ) {
                ForEach(SubtitlePreferenceCatalog.popularLanguages) { language in
                    Button(language.displayName) {
                        preferences.preferences.preferredAudioLanguage = language.id
                    }
                }
            }

            SettingsMenuRow(
                title: "Replay Gain",
                value: preferences.preferences.replayGain.displayName
            ) {
                ForEach(AudioReplayGainMode.allCases) { mode in
                    Button(mode.displayName) {
                        preferences.preferences.replayGain = mode
                        PlayerSessionPool.sharedSession().applyAudioPipeline()
                    }
                }
            }

            SettingsMenuRow(
                title: "Output module",
                value: preferences.preferences.audioOutputModule.displayName
            ) {
                ForEach(AudioOutputModule.available) { module in
                    Button(module.displayName) {
                        preferences.preferences.audioOutputModule = module
                    }
                }
            }

            SettingsMenuRow(
                title: "Output device",
                value: selectedDeviceLabel
            ) {
                Button("System default") {
                    preferences.preferences.audioOutputDeviceID = ""
                    PlayerSessionPool.sharedSession().applyAudioPipeline()
                }
                ForEach(devices) { device in
                    Button(device.description) {
                        preferences.preferences.audioOutputDeviceID = device.id
                        PlayerSessionPool.sharedSession().applyAudioPipeline()
                    }
                }
            }

            SettingsToggleRow(
                title: "Audio visualization",
                subtitle: "Show reactive bars while playing.",
                isOn: Binding(
                    get: { preferences.preferences.audioVisualizationEnabled },
                    set: { preferences.preferences.audioVisualizationEnabled = $0 }
                )
            )

            Text("Equalizer and effects are available from the player Audio sheet. Output module changes apply the next time the player starts.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            refreshDevices()
        }
    }

    private var selectedDeviceLabel: String {
        let id = preferences.preferences.audioOutputDeviceID
        if id.isEmpty { return "System default" }
        return devices.first(where: { $0.id == id })?.description ?? id
    }

    private func refreshDevices() {
        let session = PlayerSessionPool.sharedSession()
        devices = session.audioOutputDevices()
    }
}

private struct WiFiSharingSettingsCard: View {
    private var preferences: PreferencesStore { PreferencesStore.shared }
    private var server: WiFiSharingServer { WiFiSharingServer.shared }
    @State private var didCopy = false
    @State private var refreshTick = 0

    var body: some View {
        KinemaCard(title: KinemaCopy.wifiSharing, icon: "wifi") {
            SettingsToggleRow(
                title: KinemaCopy.wifiSharing,
                subtitle: KinemaCopy.wifiSharingSubtitle,
                isOn: Binding(
                    get: { preferences.preferences.wifiSharingEnabled },
                    set: { enabled in
                        preferences.preferences.wifiSharingEnabled = enabled
                        applyServerState()
                    }
                )
            )

            SecureField(KinemaCopy.wifiSharingPasscode, text: Binding(
                get: { preferences.preferences.wifiSharingPasscode },
                set: { preferences.preferences.wifiSharingPasscode = $0 }
            ))
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif

            Text(KinemaCopy.wifiSharingPasscodeHint)
                .font(.caption)
                .foregroundStyle(.secondary)

            SettingsToggleRow(
                title: KinemaCopy.wifiSharingPreferIPv6,
                subtitle: "Advertise dual-stack / IPv6 LAN addresses when available.",
                isOn: Binding(
                    get: { preferences.preferences.wifiSharingPreferIPv6 },
                    set: { value in
                        preferences.preferences.wifiSharingPreferIPv6 = value
                        if preferences.preferences.wifiSharingEnabled {
                            applyServerState()
                        }
                    }
                )
            )

            if server.isRunning, let url = server.serverURLString {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(KinemaCopy.wifiSharingURL)
                        Text(url)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            #if os(iOS) || os(macOS)
                            .textSelection(.enabled)
                            #endif
                    }
                    Spacer()
                    Button(didCopy ? "Copied" : KinemaCopy.copyURL) {
                        #if os(iOS)
                        UIPasteboard.general.string = url
                        #elseif os(macOS)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url, forType: .string)
                        #endif
                        didCopy = true
                    }
                    .buttonStyle(.bordered)
                }
                .id(refreshTick)
            } else if let error = server.lastError, preferences.preferences.wifiSharingEnabled {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onAppear {
            if preferences.preferences.wifiSharingEnabled {
                applyServerState()
            }
            server.refreshAddress()
            refreshTick += 1
        }
    }

    private func applyServerState() {
        if preferences.preferences.wifiSharingEnabled {
            _ = server.start(
                passcode: preferences.preferences.wifiSharingPasscode,
                preferIPv6: preferences.preferences.wifiSharingPreferIPv6
            )
        } else {
            server.stop()
        }
        refreshTick += 1
    }
}

#if os(iOS)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

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
        .tint(KinemaTheme.accent)
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

private struct SettingsMenuRow<Content: View>: View {
    let title: String
    let value: String
    @ViewBuilder let content: Content

    init(title: String, value: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.value = value
        self.content = content()
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            Menu {
                content
            } label: {
                HStack(spacing: 6) {
                    Text(value)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(KinemaTheme.accent)
                }
            }
            .buttonStyle(.plain)
        }
    }
}

private struct SettingsColorSwatchRow: View {
    let title: String
    @Binding var hex: String

    private let presets: [(name: String, hex: String)] = [
        ("Clear", "#00000000"),
        ("White", "#FFFFFFFF"),
        ("Yellow", "#FFFFFF00"),
        ("Cyan", "#FF00FFFF"),
        ("Lime", "#FF00FF00"),
        ("Orange", "#FFFFAA00"),
        ("Red", "#FFFF5555"),
        ("Gray", "#FFB0B0B0"),
        ("Black", "#FF000000")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                Spacer()
                Text(selectedPresetName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                ForEach(presets, id: \.hex) { preset in
                    let selected = normalizedSubtitleColorHex(hex) == normalizedSubtitleColorHex(preset.hex)
                    Button {
                        hex = preset.hex
                    } label: {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(subtitleHex: preset.hex))
                            .frame(width: 28, height: 28)
                            .overlay {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(
                                        selected ? KinemaTheme.accent : Color.primary.opacity(0.12),
                                        lineWidth: selected ? 2 : 0.5
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(preset.name)
                }
            }
        }
    }

    private var selectedPresetName: String {
        let current = normalizedSubtitleColorHex(hex)
        return presets.first(where: { normalizedSubtitleColorHex($0.hex) == current })?.name ?? "Custom"
    }
}

private extension Color {
    init(subtitleHex: String) {
        let normalized = normalizedSubtitleColorHex(subtitleHex)
        var value = normalized
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 8, let int = UInt32(value, radix: 16) else {
            self = .white
            return
        }
        let a = Double((int >> 24) & 0xFF) / 255
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

// MARK: - Keybindings editor

private struct KeyBindingsSettingsSection: View {
    @Bindable private var store = KeyBindingStore.shared
    @State private var recordingAction: String?
    @FocusState private var focusRecording: Bool
    @State private var statusMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            #if os(macOS)
            Text("Click Add key, then press a key. Conflicting shortcuts move off the other action.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(KinemaTheme.accent)
            }
            #endif

            ForEach(store.bindings) { binding in
                KeyBindingEditorRow(
                    binding: binding,
                    isRecording: recordingAction == binding.action,
                    isCustomized: store.isCustomized(binding.action),
                    onStartRecording: {
                        recordingAction = binding.action
                        focusRecording = true
                        statusMessage = nil
                    },
                    onCancelRecording: {
                        recordingAction = nil
                        focusRecording = false
                    },
                    onRemoveKey: { key in
                        store.removeKey(key, from: binding.action)
                        statusMessage = nil
                    },
                    onReset: {
                        store.reset(binding.action)
                        if recordingAction == binding.action {
                            recordingAction = nil
                            focusRecording = false
                        }
                        statusMessage = nil
                    }
                )
            }

            #if os(macOS)
            if store.hasOverrides {
                Button(KinemaCopy.keyboardResetAll) {
                    store.resetAll()
                    recordingAction = nil
                    focusRecording = false
                    statusMessage = nil
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }

            // Invisible focus target that receives the next key while recording.
            Color.clear
                .frame(width: 1, height: 1)
                .focusable(recordingAction != nil)
                .focused($focusRecording)
                .onKeyPress { press in
                    guard let action = recordingAction else { return .ignored }
                    if press.key == .escape {
                        recordingAction = nil
                        focusRecording = false
                        return .handled
                    }
                    guard let token = Self.token(from: press) else { return .ignored }
                    let stolen = store.addKey(token, to: action)
                    if !stolen.isEmpty {
                        let names = stolen.map(\.description).joined(separator: ", ")
                        statusMessage = "\(KinemaCopy.keyboardConflictPrefix) \(names)"
                    } else {
                        statusMessage = nil
                    }
                    recordingAction = nil
                    focusRecording = false
                    return .handled
                }
            #endif
        }
    }

    #if os(macOS)
    private static func token(from press: KeyPress) -> String? {
        switch press.key {
        case .space: return "space"
        case .leftArrow: return "left"
        case .rightArrow: return "right"
        case .upArrow: return "up"
        case .downArrow: return "down"
        case .return: return "return"
        case .escape: return "escape"
        case .tab: return "tab"
        case .delete: return "delete"
        case .deleteForward: return "forwarddelete"
        default:
            return KeyBindingNormalizer.normalizeToken(press.characters)
        }
    }
    #endif
}

private struct KeyBindingEditorRow: View {
    let binding: KeyBinding
    let isRecording: Bool
    let isCustomized: Bool
    let onStartRecording: () -> Void
    let onCancelRecording: () -> Void
    let onRemoveKey: (String) -> Void
    let onReset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(binding.description)
                    .font(.subheadline)
                if isCustomized {
                    Text("Custom")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(KinemaTheme.accent)
                }
                Spacer(minLength: 8)
                #if os(macOS)
                if isCustomized {
                    Button(KinemaCopy.keyboardReset, action: onReset)
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                #endif
            }

            HStack(spacing: 6) {
                ForEach(binding.keys, id: \.self) { key in
                    #if os(macOS)
                    Button {
                        onRemoveKey(key)
                    } label: {
                        keyChipLabel(KeyBindingNormalizer.displayName(for: key), showRemove: true)
                    }
                    .buttonStyle(.plain)
                    .help("Remove \(KeyBindingNormalizer.displayName(for: key))")
                    #else
                    keyChipLabel(KeyBindingNormalizer.displayName(for: key), showRemove: false)
                    #endif
                }

                #if os(macOS)
                if isRecording {
                    Button(action: onCancelRecording) {
                        keyChipLabel(KinemaCopy.keyboardRecord, showRemove: false, accented: true)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: onStartRecording) {
                        Text(KinemaCopy.keyboardAddKey)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(KinemaTheme.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(KinemaTheme.accent.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                #elseif os(iOS) || os(tvOS)
                if binding.keys.isEmpty {
                    Text("—")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                #endif
            }
        }
        .padding(.vertical, 2)
    }

    private func keyChipLabel(_ title: String, showRemove: Bool, accented: Bool = false) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption.monospaced())
            if showRemove {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .opacity(0.55)
            }
        }
        .foregroundStyle(accented ? KinemaTheme.accent : .secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            (accented ? KinemaTheme.accent.opacity(0.14) : Color.primary.opacity(0.06)),
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
    }
}

