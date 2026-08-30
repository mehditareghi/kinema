import SwiftUI
import KinemaCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

public enum KinemaTheme {
    /// Semantic colours shared by the warm-paper and auditorium appearances.
    public static let accent = adaptive(light: 0xA73531, dark: 0xDF5A52)
    public static let brass = adaptive(light: 0x9A651F, dark: 0xE5B56B)
    public static let ink = adaptive(light: 0xF1E9DC, dark: 0x090807)
    public static let auditorium = adaptive(light: 0xFAF6EE, dark: 0x12100F)
    public static let velvet = adaptive(light: 0x7B201E, dark: 0x350E0C)
    public static let paper = adaptive(light: 0x211B18, dark: 0xF2E9D8)
    public static let projectorWhite = Color(red: 0.965, green: 0.929, blue: 0.863)
    public static let secondaryText = adaptive(light: 0x675E57, dark: 0xB8ADA0)
    public static let hairline = adaptive(light: 0xD7CCBD, dark: 0x3A332E)

    public static let playerBackground = Color.black
    public static let glassBackground = adaptive(light: 0xFFFDF8, dark: 0x201C19).opacity(0.86)
    public static let glassBorder = hairline.opacity(0.72)
    public static let sidebarBackground = adaptive(light: 0xEDE3D5, dark: 0x0C0A09)
    public static let settingsBackground = auditorium
    public static let cardBackground = adaptive(light: 0xFFFDF9, dark: 0x201C19).opacity(0.92)
    public static let raisedBackground = adaptive(light: 0xFFFFFF, dark: 0x2A2420)

    #if os(macOS)
    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return nsColor(value)
        })
    }

    private static func nsColor(_ value: UInt32) -> NSColor {
        NSColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
    #else
    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            uiColor(traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    private static func uiColor(_ value: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
    #endif
}

public enum KinemaType {
    // Editorial hierarchy — the voice of programmes, titles, and films.
    public static let display = Font.system(size: 40, weight: .bold, design: .serif)
    public static let pageTitle = Font.system(.largeTitle, design: .serif, weight: .bold)
    public static let title = Font.system(.title2, design: .serif, weight: .semibold)
    public static let subtitle = Font.system(.title3, design: .serif, weight: .semibold)
    public static let cardTitle = Font.system(.headline, design: .serif, weight: .semibold)
    public static let posterTitle = Font.system(.subheadline, design: .serif, weight: .semibold)

    // Reading and interaction — quiet, consistent, and highly legible.
    public static let body = Font.system(.body, design: .default, weight: .regular)
    public static let bodyMedium = Font.system(.body, design: .default, weight: .medium)
    public static let bodyStrong = Font.system(.body, design: .default, weight: .semibold)
    public static let labelRegular = Font.system(.subheadline, design: .default, weight: .regular)
    public static let label = Font.system(.subheadline, design: .default, weight: .medium)
    public static let labelStrong = Font.system(.subheadline, design: .default, weight: .semibold)
    public static let metadata = Font.system(.caption, design: .default, weight: .regular)
    public static let metadataMedium = Font.system(.caption, design: .default, weight: .medium)
    public static let metadataStrong = Font.system(.caption, design: .default, weight: .semibold)
    public static let metadataBold = Font.system(.caption, design: .default, weight: .bold)
    public static let micro = Font.system(.caption2, design: .default, weight: .regular)
    public static let microMedium = Font.system(.caption2, design: .default, weight: .medium)
    public static let microStrong = Font.system(.caption2, design: .default, weight: .semibold)
    public static let microBold = Font.system(.caption2, design: .default, weight: .bold)
    public static let note = Font.system(.footnote, design: .default, weight: .regular)
    public static let noteStrong = Font.system(.footnote, design: .default, weight: .bold)
    public static let eyebrow = Font.system(size: 10, weight: .bold, design: .default)

    // Purposeful exceptions: tactile controls, time, and technical strings.
    public static let control = Font.system(.body, design: .rounded, weight: .semibold)
    public static let controlLabel = Font.system(.subheadline, design: .rounded, weight: .semibold)
    public static let timecode = Font.system(.caption, design: .monospaced, weight: .semibold)
    public static let timecodeSmall = Font.system(.caption2, design: .monospaced, weight: .semibold)
    public static let timecodeLabel = Font.system(.subheadline, design: .monospaced, weight: .semibold)
    public static let code = Font.system(.body, design: .monospaced, weight: .regular)
    public static let codeSmall = Font.system(.caption, design: .monospaced, weight: .regular)
    public static let playerTag = Font.system(size: 10, weight: .heavy, design: .rounded)
    public static let playerMarker = Font.system(size: 8, weight: .bold, design: .rounded)
    public static let speedReadout = Font.system(size: 9, weight: .semibold, design: .monospaced)
}

public extension AppAppearance {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Shared atmospheric background for browsing surfaces. It suggests projector
/// light and theatre velvet without competing with poster artwork.
public struct KinemaBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public var body: some View {
        ZStack {
            KinemaTheme.auditorium

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .clear, location: 0.42),
                    .init(color: .black.opacity(colorScheme == .dark ? 0.18 : 0.025), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                stops: [
                    .init(color: KinemaTheme.velvet.opacity(colorScheme == .dark ? 0.30 : 0.10), location: 0),
                    .init(color: KinemaTheme.velvet.opacity(colorScheme == .dark ? 0.10 : 0.035), location: 0.44),
                    .init(color: .clear, location: 1)
                ],
                center: UnitPoint(x: 0.08, y: 0.02),
                startRadius: 0,
                endRadius: 720
            )

            RadialGradient(
                stops: [
                    .init(color: KinemaTheme.brass.opacity(colorScheme == .dark ? 0.09 : 0.065), location: 0),
                    .init(color: KinemaTheme.brass.opacity(0.025), location: 0.50),
                    .init(color: .clear, location: 1)
                ],
                center: UnitPoint(x: 0.88, y: 0.04),
                startRadius: 0,
                endRadius: 680
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

public struct KinemaSectionTitle: View {
    let title: String
    let systemImage: String?

    public init(_ title: String, systemImage: String? = nil) {
        self.title = title
        self.systemImage = systemImage
    }

    public var body: some View {
        HStack(spacing: 9) {
            Rectangle()
                .fill(KinemaTheme.accent)
                .frame(width: 3, height: 18)

            Text(title.uppercased())
                .font(KinemaType.eyebrow)
                .tracking(1.8)
                .foregroundStyle(KinemaTheme.paper.opacity(0.86))

            Spacer(minLength: 0)

            if let systemImage {
                Image(systemName: systemImage)
                    .font(KinemaType.metadataStrong)
                    .foregroundStyle(KinemaTheme.brass.opacity(0.75))
            }
        }
    }
}

public struct GlassBackground: ViewModifier {
    var cornerRadius: CGFloat = 14

    public func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.20), .white.opacity(0.045), .clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.24), KinemaTheme.hairline.opacity(0.52)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.5
                            )
                    }
                    .shadow(color: .black.opacity(0.42), radius: 22, y: 10)
            }
    }
}

public struct LiquidGlassBackground: ViewModifier {
    var cornerRadius: CGFloat = 22

    public func body(content: Content) -> some View {
        content.modifier(GlassBackground(cornerRadius: cornerRadius))
    }
}

public extension View {
    func kinemaGlass(cornerRadius: CGFloat = 14) -> some View {
        modifier(GlassBackground(cornerRadius: cornerRadius))
    }

    func kinemaLiquidGlass(cornerRadius: CGFloat = 22) -> some View {
        modifier(LiquidGlassBackground(cornerRadius: cornerRadius))
    }

    /// Native Liquid Glass on iOS 26+, material fallback on earlier OS versions.
    @ViewBuilder
    func kinemaNativeGlass(cornerRadius: CGFloat = 22) -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self.kinemaLiquidGlass(cornerRadius: cornerRadius)
        }
        #else
        self.kinemaLiquidGlass(cornerRadius: cornerRadius)
        #endif
    }

    @ViewBuilder
    func kinemaNativeGlassCircle() -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: .circle)
        } else {
            self.kinemaLiquidGlass(cornerRadius: 999)
        }
        #else
        self.kinemaLiquidGlass(cornerRadius: 999)
        #endif
    }
}

#if os(iOS)
@available(iOS 26.0, *)
struct KinemaGlassProminentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .glassEffect(.regular.interactive(), in: .circle)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
#endif

public func formatTime(_ interval: TimeInterval) -> String {
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

// MARK: - Shared sheet / settings cards

public struct KinemaCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    public init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon)
                .font(KinemaType.cardTitle)
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 12) {
                content
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KinemaTheme.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(KinemaTheme.hairline.opacity(0.78), lineWidth: 0.6)
        }
        .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
    }
}

/// Shared address / key field used on Open Stream, Playbill setup, and similar forms.
public struct KinemaComposerField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var isURLField: Bool = false
    var accent: Color = KinemaTheme.accent
    @FocusState.Binding var isFocused: Bool
    var onSubmit: (() -> Void)? = nil
    var onPaste: (() -> Void)? = nil

    public init(
        icon: String,
        placeholder: String,
        text: Binding<String>,
        isSecure: Bool = false,
        isURLField: Bool = false,
        accent: Color = KinemaTheme.accent,
        isFocused: FocusState<Bool>.Binding,
        onSubmit: (() -> Void)? = nil,
        onPaste: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.placeholder = placeholder
        self._text = text
        self.isSecure = isSecure
        self.isURLField = isURLField
        self.accent = accent
        self._isFocused = isFocused
        self.onSubmit = onSubmit
        self.onPaste = onPaste
    }

    private var iconColor: Color {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? KinemaTheme.secondaryText
            : accent
    }

    public var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(KinemaType.bodyStrong)
                .foregroundStyle(iconColor)

            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .textFieldStyle(.plain)
            .font(KinemaType.code)
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(isURLField ? .URL : .default)
            .submitLabel(isURLField ? .go : .done)
            #endif
            .focused($isFocused)
            .onSubmit { onSubmit?() }

            if !text.isEmpty {
                Button {
                    text = ""
                    isFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(KinemaTheme.secondaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }

            if let onPaste {
                Button(action: onPaste) {
                    Label("Paste", systemImage: "doc.on.clipboard")
                        .font(KinemaType.metadataStrong)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 40)
        .background(KinemaTheme.raisedBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isFocused ? accent.opacity(0.72) : KinemaTheme.hairline.opacity(0.82),
                    lineWidth: isFocused ? 1.4 : 0.6
                )
        }
        .animation(.easeOut(duration: 0.16), value: isFocused)
    }
}

/// Responsive action row — side-by-side when wide, stacked when narrow.
public struct KinemaComposerActionLayout<Content: View>: View {
    @ViewBuilder let content: () -> Content

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { content() }
            VStack(spacing: 8) { content() }
        }
    }
}

public struct KinemaComposerButtonLabel: View {
    let title: String
    var systemImage: String? = nil
    var showsProgress: Bool = false

    public init(_ title: String, systemImage: String? = nil, showsProgress: Bool = false) {
        self.title = title
        self.systemImage = systemImage
        self.showsProgress = showsProgress
    }

    public var body: some View {
        HStack(spacing: 6) {
            if showsProgress {
                ProgressView()
                    .controlSize(.small)
            } else if let systemImage {
                Image(systemName: systemImage)
                    .font(KinemaType.controlLabel)
            }
            Text(title)
        }
        .font(KinemaType.controlLabel)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}

/// Apply to composer action buttons for consistent compact sizing.
public extension View {
    func kinemaComposerButtonStyle() -> some View {
        controlSize(.small)
    }
}

public struct KinemaSheetHero: View {
    let icon: String
    let title: String
    let subtitle: String

    public init(icon: String, title: String, subtitle: String) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
    }

    public var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(KinemaType.title)
                .foregroundStyle(KinemaTheme.accent)
                .frame(width: 48, height: 48)
                .background(KinemaTheme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(KinemaType.cardTitle)
                Text(subtitle)
                    .font(KinemaType.metadata)
                    .foregroundStyle(KinemaTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .background(
            LinearGradient(
                stops: [
                    .init(color: KinemaTheme.accent.opacity(0.16), location: 0),
                    .init(color: KinemaTheme.velvet.opacity(0.08), location: 0.42),
                    .init(color: KinemaTheme.cardBackground, location: 1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(KinemaTheme.hairline.opacity(0.78), lineWidth: 0.6)
        }
    }
}

/// 3×3 screen placement picker for primary/secondary subtitles.
public struct SubtitlePlacementGrid: View {
    let title: String
    let selection: SubtitlePlacementAnchor
    let onSelect: (SubtitlePlacementAnchor) -> Void

    private let rows: [[SubtitlePlacementAnchor]] = [
        [.topLeft, .topCenter, .topRight],
        [.centerLeft, .center, .centerRight],
        [.bottomLeft, .bottomCenter, .bottomRight]
    ]

    public init(
        title: String,
        selection: SubtitlePlacementAnchor,
        onSelect: @escaping (SubtitlePlacementAnchor) -> Void
    ) {
        self.title = title
        self.selection = selection
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(KinemaType.label)
                Spacer()
                Text(selection.accessibilityLabel)
                    .font(KinemaType.metadata)
                    .foregroundStyle(KinemaTheme.secondaryText)
            }

            VStack(spacing: 6) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 6) {
                        ForEach(row) { anchor in
                            let isSelected = selection == anchor
                            Button {
                                onSelect(anchor)
                            } label: {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(isSelected ? KinemaTheme.accent.opacity(0.22) : Color.primary.opacity(0.05))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 36)
                                    .overlay {
                                        Image(systemName: "circle.fill")
                                            .font(.system(size: isSelected ? 7 : 5))
                                            .foregroundStyle(isSelected ? KinemaTheme.accent : Color.secondary.opacity(0.55))
                                    }
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .strokeBorder(
                                                isSelected ? KinemaTheme.accent.opacity(0.45) : Color.primary.opacity(0.08),
                                                lineWidth: isSelected ? 1.5 : 0.5
                                            )
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(anchor.accessibilityLabel)
                        }
                    }
                }
            }
            .padding(8)
            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}
