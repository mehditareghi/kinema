import SwiftUI
import KinemaCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

public enum KinemaTheme {
    /// Kinema brand wine / cinema rose — κίνημα · your cinema.
    public static let accent = Color(red: 0.769, green: 0.357, blue: 0.416)

    public static let playerBackground = Color.black
    public static let glassBackground = Color.white.opacity(0.08)
    public static let glassBorder = Color.white.opacity(0.15)

    #if os(macOS)
    public static let sidebarBackground = Color(nsColor: .windowBackgroundColor)
    public static let settingsBackground = Color(nsColor: .windowBackgroundColor)
    public static let cardBackground = Color(nsColor: .controlBackgroundColor)
    #else
    public static let sidebarBackground = Color(uiColor: .systemGroupedBackground)
    public static let settingsBackground = Color(uiColor: .systemGroupedBackground)
    public static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
    #endif
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
                                    colors: [.white.opacity(0.16), .white.opacity(0.05), .clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.white.opacity(0.38), .white.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.5
                            )
                    }
                    .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
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
                .font(.headline)
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
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        }
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
                .font(.title2.weight(.semibold))
                .foregroundStyle(KinemaTheme.accent)
                .frame(width: 48, height: 48)
                .background(KinemaTheme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [KinemaTheme.accent.opacity(0.18), KinemaTheme.cardBackground],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
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
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(selection.accessibilityLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
