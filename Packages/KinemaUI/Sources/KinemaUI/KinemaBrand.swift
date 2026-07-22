import SwiftUI
import KinemaCore

/// Minimal Kinema mark — wine/cinema-rose K glyph matching the app icon.
public struct KinemaMark: View {
    let size: CGFloat

    public init(size: CGFloat = 40) {
        self.size = size
    }

    public var body: some View {
        KinemaKGlyph()
            .fill(KinemaTheme.accent)
            .padding(size * 0.14)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct KinemaKGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let cx = rect.midX
        let cy = rect.midY
        let scale = min(w, h)
        let t = scale * 0.17
        let stemLeft = cx - scale * 0.34
        let stemRight = stemLeft + t
        let top = cy - scale * 0.46
        let bottom = cy + scale * 0.46
        let joint = cy

        var path = Path()
        path.addRoundedRect(
            in: CGRect(x: stemLeft, y: top, width: t, height: bottom - top),
            cornerSize: CGSize(width: t * 0.34, height: t * 0.34)
        )

        path.move(to: CGPoint(x: stemRight - t * 0.08, y: joint - t * 0.62))
        path.addLine(to: CGPoint(x: cx + scale * 0.34, y: top + t * 0.35))
        path.addLine(to: CGPoint(x: cx + scale * 0.34 - t, y: top + t * 0.35 + t * 0.82))
        path.addLine(to: CGPoint(x: stemRight - t * 0.08, y: joint - t * 0.62 + t * 0.82))
        path.closeSubpath()

        path.move(to: CGPoint(x: stemRight - t * 0.08, y: joint + t * 0.62 - t * 0.82))
        path.addLine(to: CGPoint(x: cx + scale * 0.36, y: bottom - t * 0.35 - t * 0.82))
        path.addLine(to: CGPoint(x: cx + scale * 0.36 - t, y: bottom - t * 0.35))
        path.addLine(to: CGPoint(x: stemRight - t * 0.08, y: joint + t * 0.62))
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
                    .font(compact ? .headline.weight(.semibold) : .title2.weight(.bold))
                if !compact {
                    Text("κίνημα · motion")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
        VStack(spacing: 28) {
            KinemaMark(size: 88)
                .padding(.bottom, 4)

            VStack(spacing: 8) {
                Text("Nothing playing")
                    .font(.title2.weight(.semibold))
                Text("Open a video from the library or drop a file here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }

            Button(action: onOpenFiles) {
                Label("Open Media", systemImage: "folder")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .tint(KinemaTheme.accent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}
