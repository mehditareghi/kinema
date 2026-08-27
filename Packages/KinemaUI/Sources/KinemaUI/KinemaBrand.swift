import SwiftUI
import KinemaCore

/// The Cut: one image split into two moments and displaced in motion.
public struct KinemaMark: View {
    let size: CGFloat

    public init(size: CGFloat = 40) {
        self.size = size
    }

    public var body: some View {
        ZStack {
            KinemaHalfDisc(isTop: true)
                .fill(KinemaTheme.accent)
                .frame(width: size * 0.72, height: size * 0.72)
                .offset(x: size * 0.075, y: -size * 0.055)

            KinemaHalfDisc(isTop: false)
                .fill(KinemaTheme.paper)
                .frame(width: size * 0.72, height: size * 0.72)
                .offset(x: -size * 0.075, y: size * 0.055)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct KinemaHalfDisc: Shape {
    let isTop: Bool

    func path(in rect: CGRect) -> Path {
        let k: CGFloat = 0.5522847498
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let rx = rect.width / 2
        let ry = rect.height / 2
        var path = Path()

        path.move(to: CGPoint(x: center.x - rx, y: center.y))
        if isTop {
            path.addCurve(
                to: CGPoint(x: center.x, y: center.y - ry),
                control1: CGPoint(x: center.x - rx, y: center.y - ry * k),
                control2: CGPoint(x: center.x - rx * k, y: center.y - ry)
            )
            path.addCurve(
                to: CGPoint(x: center.x + rx, y: center.y),
                control1: CGPoint(x: center.x + rx * k, y: center.y - ry),
                control2: CGPoint(x: center.x + rx, y: center.y - ry * k)
            )
        } else {
            path.addCurve(
                to: CGPoint(x: center.x, y: center.y + ry),
                control1: CGPoint(x: center.x - rx, y: center.y + ry * k),
                control2: CGPoint(x: center.x - rx * k, y: center.y + ry)
            )
            path.addCurve(
                to: CGPoint(x: center.x + rx, y: center.y),
                control1: CGPoint(x: center.x + rx * k, y: center.y + ry),
                control2: CGPoint(x: center.x + rx, y: center.y + ry * k)
            )
        }
        path.closeSubpath()
        return path
    }
}

public struct KinemaBrandHeader: View {
    var compact: Bool

    public init(compact: Bool = false) {
        self.compact = compact
    }

    public var body: some View {
        HStack(spacing: compact ? 10 : 14) {
            KinemaMark(size: compact ? 32 : 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("Kinema")
                    .font(compact ? KinemaType.cardTitle : KinemaType.title)
                if !compact {
                    Text("YOUR PRIVATE SCREENING ROOM")
                        .font(KinemaType.eyebrow)
                        .tracking(1.5)
                        .foregroundStyle(KinemaTheme.brass.opacity(0.78))
                }
            }
            Spacer(minLength: 0)
        }
    }
}

public struct KinemaEmptyState: View {
    let onOpenFiles: () -> Void

    public init(onOpenFiles: @escaping () -> Void) {
        self.onOpenFiles = onOpenFiles
    }

    public var body: some View {
        VStack(spacing: 30) {
            KinemaMark(size: 82)
                .padding(.bottom, 4)

            VStack(spacing: 10) {
                Text("The screen is waiting")
                    .font(KinemaType.title)
                    .foregroundStyle(KinemaTheme.paper)
                Text("Choose a film from your collection, or bring something new to tonight’s programme.")
                    .font(KinemaType.label)
                    .foregroundStyle(KinemaTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 390)
            }

            Button(action: onOpenFiles) {
                Label("Choose a Film", systemImage: "play.rectangle.fill")
                    .font(KinemaType.control)
            }
            .buttonStyle(.borderedProminent)
            .tint(KinemaTheme.accent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .background(KinemaBackdrop())
    }
}
