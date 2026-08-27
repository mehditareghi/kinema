import SwiftUI
import KinemaCore
import KinemaPlayback

/// Compact in-row speed control (before the audio button).
/// Wide: continuous slider with the current value under the thumb. Tight: menu label.
struct PlaybackSpeedControl: View {
    enum Style {
        case inlineSteps
        case menu
    }

    @Bindable var viewModel: PlayerViewModel
    let accent: Color
    var style: Style = .inlineSteps

    /// Discrete presets for the compact menu; inline slider uses continuous `range`.
    static let steps: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0]
    static let range: ClosedRange<Double> = 0.5...3.0
    static let inlineMinChromeWidth: CGFloat = 700
    static let inlineSliderWidth: CGFloat = 160

    /// Keeps meaningful decimals (`1.25×`); `%.2g` wrongly truncates to `1.2×`.
    static func formatSpeed(_ speed: Double) -> String {
        "\(formatSpeedValue(speed))×"
    }

    static func formatSpeedValue(_ speed: Double) -> String {
        if abs(speed - speed.rounded()) < 0.001 {
            return String(format: "%.0f", speed)
        }
        var text = String(format: "%.2f", speed)
        while text.hasSuffix("0") {
            text.removeLast()
        }
        if text.hasSuffix(".") {
            text.removeLast()
        }
        return text
    }

    /// Two-decimal playback speeds keep the control stable at the range ends.
    static func quantizedSpeed(_ raw: Double) -> Double {
        let clamped = min(max(raw, range.lowerBound), range.upperBound)
        return (clamped * 100).rounded() / 100
    }

    var body: some View {
        Group {
            switch style {
            case .inlineSteps:
                HStack(spacing: 4) {
                    if !isNormalSpeed {
                        resetSpeedButton
                    }
                    ContinuousSpeedSlider(
                        speed: speedBinding,
                        range: Self.range,
                        accent: accent,
                        onEditingChanged: { editing in
                            if editing {
                                viewModel.cancelAutoHideControls()
                            } else {
                                viewModel.scheduleHideControls()
                            }
                        }
                    )
                    .frame(width: Self.inlineSliderWidth, height: 44)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Playback speed")
                    .accessibilityValue("\(Self.formatSpeedValue(viewModel.session.info.speed)) times")
                }
            case .menu:
                compactMenu
            }
        }
        .foregroundStyle(.white)
    }

    private var isNormalSpeed: Bool {
        abs(viewModel.session.info.speed - 1) < 0.005
    }

    private var speedBinding: Binding<Double> {
        Binding(
            get: {
                Self.quantizedSpeed(viewModel.session.info.speed)
            },
            set: { raw in
                let speed = Self.quantizedSpeed(raw)
                guard abs(viewModel.session.info.speed - speed) >= 0.005 else { return }
                viewModel.session.setSpeed(speed)
                viewModel.showOSD(Self.formatSpeed(speed))
            }
        )
    }

    private var resetSpeedButton: some View {
        Button {
            viewModel.session.setSpeed(1)
            viewModel.showOSD(Self.formatSpeed(1))
            viewModel.scheduleHideControls()
        } label: {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
                .frame(width: 18, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Reset playback speed to 1×")
    }

    private var compactMenu: some View {
        Menu {
            ForEach(Self.steps, id: \.self) { speed in
                Button {
                    viewModel.session.setSpeed(speed)
                    viewModel.showOSD(Self.formatSpeed(speed))
                    viewModel.scheduleHideControls()
                } label: {
                    if abs(viewModel.session.info.speed - speed) < 0.01 {
                        Label(Self.formatSpeed(speed), systemImage: "checkmark")
                    } else {
                        Text(Self.formatSpeed(speed))
                    }
                }
            }
            if !isNormalSpeed {
                Divider()
                Button {
                    viewModel.session.setSpeed(1)
                    viewModel.showOSD(Self.formatSpeed(1))
                    viewModel.scheduleHideControls()
                } label: {
                    Label("Reset to 1×", systemImage: "arrow.counterclockwise")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(Self.formatSpeed(viewModel.session.info.speed))
                    .font(KinemaType.timecodeLabel)
                Image(systemName: "chevron.up.chevron.down")
                    .font(KinemaType.microStrong)
                    .foregroundStyle(.white.opacity(0.65))
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(.white.opacity(0.1), in: Capsule())
            .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel("Playback speed")
        .simultaneousGesture(
            TapGesture().onEnded {
                viewModel.cancelAutoHideControls()
                viewModel.scheduleHideControls(after: 12)
            }
        )
    }
}

/// Custom continuous slider so the value label shares the thumb’s x and ends don’t jump.
private struct ContinuousSpeedSlider: View {
    @Binding var speed: Double
    let range: ClosedRange<Double>
    let accent: Color
    var onEditingChanged: (Bool) -> Void

    private let trackHeight: CGFloat = 3
    private let thumbDiameter: CGFloat = 14
    private let labelColor = Color.white.opacity(0.88)

    @State private var isEditing = false
    @State private var localSpeed: Double?

    private var displayed: Double {
        localSpeed ?? speed
    }

    var body: some View {
        // Fixed height participates in the row’s center alignment with icons.
        // Track sits on that center line; label hangs below the thumb.
        Color.clear
            .frame(height: 44)
            .overlay(alignment: .center) {
                GeometryReader { geo in
                    let width = max(geo.size.width, 1)
                    let usable = max(width - thumbDiameter, 1)
                    let span = max(range.upperBound - range.lowerBound, .leastNonzeroMagnitude)
                    let progress = min(max((displayed - range.lowerBound) / span, 0), 1)
                    let thumbX = thumbDiameter / 2 + usable * CGFloat(progress)
                    let midY = geo.size.height / 2

                    ZStack {
                        Capsule()
                            .fill(Color.white.opacity(0.28))
                            .frame(width: width - 2, height: trackHeight)
                            .position(x: width / 2, y: midY)

                        Capsule()
                            .fill(accent)
                            .frame(width: max(thumbX - 1, trackHeight), height: trackHeight)
                            .position(x: (max(thumbX - 1, trackHeight) / 2) + 1, y: midY)

                        Circle()
                            .fill(Color.white)
                            .frame(width: thumbDiameter, height: thumbDiameter)
                            .shadow(color: .black.opacity(0.22), radius: 1, y: 0.5)
                            .position(x: thumbX, y: midY)

                        Text(PlaybackSpeedControl.formatSpeedValue(displayed))
                            .font(KinemaType.speedReadout)
                            .foregroundStyle(labelColor)
                            .position(x: thumbX, y: midY + 16)
                    }
                    .contentShape(Rectangle())
                    .gesture(dragGesture(usable: usable, span: span))
                }
                .frame(height: 28)
            }
    }

    private func dragGesture(usable: CGFloat, span: Double) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isEditing {
                    isEditing = true
                    onEditingChanged(true)
                }
                let x = min(max(value.location.x - thumbDiameter / 2, 0), usable)
                let raw = range.lowerBound + Double(x / usable) * span
                let quantized = PlaybackSpeedControl.quantizedSpeed(raw)
                localSpeed = quantized
                speed = quantized
            }
            .onEnded { _ in
                if let localSpeed {
                    speed = localSpeed
                }
                localSpeed = nil
                isEditing = false
                onEditingChanged(false)
            }
    }
}
