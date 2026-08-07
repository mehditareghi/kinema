import SwiftUI
import KinemaCore
import KinemaPlayback

/// Compact in-row speed control (before the audio button).
/// Wide: native stepped `Slider` + labels under each step. Tight: menu label.
struct PlaybackSpeedControl: View {
    enum Style {
        case inlineSteps
        case menu
    }

    @Bindable var viewModel: PlayerViewModel
    let accent: Color
    var style: Style = .inlineSteps

    static let steps: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0]
    static let inlineMinChromeWidth: CGFloat = 700
    static let inlineSliderWidth: CGFloat = 248

    var body: some View {
        Group {
            switch style {
            case .inlineSteps:
                NativeSteppedSpeedSlider(
                    index: speedIndexBinding,
                    steps: Self.steps,
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
                .accessibilityValue(String(format: "%.2g times", viewModel.session.info.speed))
            case .menu:
                compactMenu
            }
        }
        .foregroundStyle(.white)
    }

    private var speedIndexBinding: Binding<Double> {
        Binding(
            get: { Double(Self.nearestIndex(to: viewModel.session.info.speed)) },
            set: { raw in
                let index = min(max(Int(raw.rounded()), 0), Self.steps.count - 1)
                let speed = Self.steps[index]
                guard abs(viewModel.session.info.speed - speed) >= 0.01 else { return }
                viewModel.session.setSpeed(speed)
                viewModel.showOSD(String(format: "%.2g×", speed))
            }
        )
    }

    private var compactMenu: some View {
        Menu {
            ForEach(Self.steps, id: \.self) { speed in
                Button {
                    viewModel.session.setSpeed(speed)
                    viewModel.showOSD(String(format: "%.2g×", speed))
                    viewModel.scheduleHideControls()
                } label: {
                    if abs(viewModel.session.info.speed - speed) < 0.01 {
                        Label(String(format: "%.2g×", speed), systemImage: "checkmark")
                    } else {
                        Text(String(format: "%.2g×", speed))
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(String(format: "%.2g×", viewModel.session.info.speed))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
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

    static func nearestIndex(to speed: Double) -> Int {
        var best = 0
        var bestDistance = Double.greatestFiniteMagnitude
        for (index, step) in steps.enumerated() {
            let distance = abs(step - speed)
            if distance < bestDistance {
                bestDistance = distance
                best = index
            }
        }
        return best
    }

    static func shortLabel(for speed: Double) -> String {
        if abs(speed - 0.5) < 0.01 { return ".5" }
        if abs(speed - 0.75) < 0.01 { return ".75" }
        if speed == speed.rounded() { return String(format: "%.0f", speed) }
        return String(format: "%g", speed)
    }
}

/// Native `Slider` thumb/track (same as progress / settings), ticks + labels under each step.
/// Track is centered with sibling controls; labels hang below.
private struct NativeSteppedSpeedSlider: View {
    @Binding var index: Double
    let steps: [Double]
    let accent: Color
    var onEditingChanged: (Bool) -> Void

    /// Matches where the system slider thumb rests at min/max (regular control size).
    private let thumbTravelInset: CGFloat = 15

    private var lastIndex: Double { Double(max(steps.count - 1, 1)) }

    var body: some View {
        // Fixed height participates in the row’s center alignment with icons.
        // Slider sits on that center line; labels are drawn below it.
        Color.clear
            .frame(height: 44)
            .overlay(alignment: .center) {
                sliderWithTicks
                    .frame(height: 28)
            }
            .overlay(alignment: .center) {
                stepLabels
                    .offset(y: 22)
            }
    }

    private var sliderWithTicks: some View {
        ZStack {
            GeometryReader { geo in
                let width = max(geo.size.width, 1)
                let usable = max(width - thumbTravelInset * 2, 1)
                let midY = geo.size.height / 2

                ForEach(0..<steps.count, id: \.self) { step in
                    let tx = thumbTravelInset + usable * CGFloat(Double(step) / lastIndex)
                    Capsule()
                        .fill(Color.white.opacity(step <= Int(index.rounded()) ? 0.9 : 0.35))
                        .frame(width: 2, height: 8)
                        .position(x: tx, y: midY)
                }
            }

            Slider(
                value: $index,
                in: 0...lastIndex,
                step: 1,
                onEditingChanged: onEditingChanged
            )
            .labelsHidden()
            .tint(accent)
            .controlSize(.regular)
        }
    }

    private var stepLabels: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let usable = max(width - thumbTravelInset * 2, 1)

            ZStack {
                ForEach(Array(steps.enumerated()), id: \.offset) { offset, speed in
                    let selected = abs(index - Double(offset)) < 0.01
                    let tx = thumbTravelInset + usable * CGFloat(Double(offset) / lastIndex)
                    Text(PlaybackSpeedControl.shortLabel(for: speed))
                        .font(.system(size: 9, weight: selected ? .bold : .medium).monospacedDigit())
                        .foregroundStyle(selected ? accent : .white.opacity(0.55))
                        .position(x: tx, y: 6)
                }
            }
        }
        .frame(height: 12)
    }
}
