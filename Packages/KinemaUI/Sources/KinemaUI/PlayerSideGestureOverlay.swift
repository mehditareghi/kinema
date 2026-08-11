import SwiftUI
import KinemaCore
import KinemaPlayback
#if os(iOS) || os(tvOS)
import UIKit
#endif

/// VLC-style player gestures:
/// - Left half vertical → brightness
/// - Right half vertical → volume
/// - Horizontal drag → scrub position
/// - Double-tap left/right → ±10s (chrome stays put)
/// - Single-tap → show/hide chrome (delayed so double-tap never trips it)
struct PlayerSideGestureOverlay: View {
    @Bindable var viewModel: PlayerViewModel
    let accent: Color

    @State private var brightness: Double = 0.6
    @State private var activeControl: SideControl?
    @State private var panMode: PanMode = .none
    @State private var dragAnchor: Double?
    @State private var seekAnchor: TimeInterval?
    @State private var hideIndicatorTask: Task<Void, Never>?
    @State private var pendingSingleTap: Task<Void, Never>?
    @State private var lastDoubleTapAt: Date?

    private enum SideControl: Equatable {
        case brightness
        case volume
    }

    private enum PanMode: Equatable {
        case none
        case seek
        case brightness
        case volume
    }

    /// Full-width horizontal drag maps to this many seconds (clamped by duration).
    private let seekSecondsPerScreenWidth: Double = 90

    private var chromeVisible: Bool { viewModel.showControls }

    private var showBrightnessRail: Bool {
        #if os(iOS)
        (chromeVisible && panMode != .seek) || activeControl == .brightness
        #else
        false
        #endif
    }

    private var showVolumeRail: Bool {
        (chromeVisible && panMode != .seek) || activeControl == .volume
    }

    private var volumeFraction: Double {
        if viewModel.isMuted { return 0 }
        return min(1, max(0, viewModel.session.info.volume / KinemaPreferences.volumeMax))
    }

    var body: some View {
        GeometryReader { geo in
            let railInset = min(34, max(22, geo.size.width * 0.04))
            let topDead = chromeVisible ? max(72, geo.safeAreaInsets.top + 56) : 0
            let bottomDead = chromeVisible ? max(118, geo.safeAreaInsets.bottom + 100) : 0
            let gestureHeight = max(120, geo.size.height - topDead - bottomDead)

            ZStack {
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: topDead)
                        .allowsHitTesting(false)

                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: gestureHeight)
                        .contentShape(Rectangle())
                        .gesture(playerPan(size: CGSize(width: geo.size.width, height: gestureHeight)))
                        .highPriorityGesture(doubleTapSeekGesture(width: geo.size.width))
                        .onTapGesture {
                            // Ignore the second tap of a double-tap pair (it also hits onTapGesture).
                            if let lastDoubleTapAt,
                               Date().timeIntervalSince(lastDoubleTapAt) < 0.28 {
                                return
                            }
                            scheduleSingleTapChromeToggle()
                        }

                    Color.clear
                        .frame(height: bottomDead)
                        .allowsHitTesting(false)
                }

                HStack {
                    if showBrightnessRail {
                        sideRail(kind: .brightness, progress: brightness, accessibility: "Brightness")
                            .padding(.leading, railInset)
                            .transition(.opacity)
                    }

                    Spacer(minLength: 0)

                    if showVolumeRail {
                        sideRail(kind: .volume, progress: volumeFraction, accessibility: "Volume")
                            .padding(.trailing, railInset)
                            .transition(.opacity)
                    }
                }
                .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            brightness = currentScreenBrightness()
        }
        .onDisappear {
            pendingSingleTap?.cancel()
            hideIndicatorTask?.cancel()
        }
    }

    // MARK: - Taps

    private func doubleTapSeekGesture(width: CGFloat) -> some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { event in
                pendingSingleTap?.cancel()
                pendingSingleTap = nil
                lastDoubleTapAt = Date()
                let left = event.location.x < width / 2
                viewModel.seekByConfiguredStep(forward: !left)
            }
    }

    private func scheduleSingleTapChromeToggle() {
        pendingSingleTap?.cancel()
        pendingSingleTap = Task { @MainActor in
            // Slightly under the system double-tap window so chrome feels snappier,
            // while still usually losing to SpatialTapGesture(count: 2).
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            guard panMode == .none else { return }
            viewModel.toggleControls()
            pendingSingleTap = nil
        }
    }

    // MARK: - Pan

    private func playerPan(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .local)
            .onChanged { value in
                pendingSingleTap?.cancel()
                pendingSingleTap = nil

                let dx = value.translation.width
                let dy = value.translation.height

                if panMode == .none {
                    let distance = hypot(dx, dy)
                    guard distance >= 14 else { return }

                    if abs(dx) > abs(dy) * 1.15 {
                        beginSeek()
                    } else if abs(dy) > abs(dx) * 1.05 {
                        #if os(iOS)
                        let side: SideControl = value.startLocation.x < size.width / 2
                            ? .brightness
                            : .volume
                        #else
                        let side: SideControl = .volume
                        #endif
                        beginVertical(side)
                    } else {
                        return
                    }
                }

                switch panMode {
                case .seek:
                    applySeek(dx: dx, width: size.width)
                case .brightness:
                    applyVertical(kind: .brightness, dy: dy, height: size.height)
                case .volume:
                    applyVertical(kind: .volume, dy: dy, height: size.height)
                case .none:
                    break
                }
            }
            .onEnded { _ in
                endPan()
            }
    }

    private func beginSeek() {
        hideIndicatorTask?.cancel()
        viewModel.cancelAutoHideControls()
        panMode = .seek
        activeControl = nil
        seekAnchor = viewModel.session.info.position
    }

    private func applySeek(dx: CGFloat, width: CGFloat) {
        guard let anchor = seekAnchor else { return }
        let duration = max(viewModel.session.info.duration, 0)
        let span = min(seekSecondsPerScreenWidth, max(30, duration * 0.25))
        let delta = Double(dx / max(width, 1)) * span
        let target = min(max(0, anchor + delta), max(duration, 0))
        viewModel.session.seek(to: target)

        let signed = Int((target - anchor).rounded())
        if signed >= 0 {
            viewModel.showOSD("+\(formatSeekDelta(signed)) → \(formatTime(target))")
        } else {
            viewModel.showOSD("\(formatSeekDelta(signed)) → \(formatTime(target))")
        }
    }

    private func beginVertical(_ kind: SideControl) {
        #if !os(iOS)
        guard kind == .volume else { return }
        #endif
        hideIndicatorTask?.cancel()
        viewModel.cancelAutoHideControls()
        panMode = kind == .brightness ? .brightness : .volume
        withAnimation(.easeOut(duration: 0.15)) {
            activeControl = kind
        }
        switch kind {
        case .brightness:
            brightness = currentScreenBrightness()
            dragAnchor = brightness
        case .volume:
            if viewModel.isMuted {
                viewModel.isMuted = false
                viewModel.session.setMuted(false)
            }
            dragAnchor = volumeFraction
        }
    }

    private func applyVertical(kind: SideControl, dy: CGFloat, height: CGFloat) {
        guard let anchor = dragAnchor else { return }
        let span = max(height * 0.55, 180)
        let next = min(1, max(0, anchor + Double(-dy / span)))
        switch kind {
        case .brightness:
            brightness = next
            setScreenBrightness(next)
        case .volume:
            viewModel.session.setVolume(next * KinemaPreferences.volumeMax)
        }
    }

    private func endPan() {
        let finished = panMode
        dragAnchor = nil
        seekAnchor = nil
        panMode = .none

        switch finished {
        case .brightness, .volume:
            if viewModel.showControls {
                activeControl = nil
                viewModel.scheduleHideControls()
            } else {
                scheduleHideSideIndicator()
            }
        case .seek:
            viewModel.scheduleHideControls()
        case .none:
            break
        }
    }

    private func scheduleHideSideIndicator() {
        hideIndicatorTask?.cancel()
        hideIndicatorTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.22)) {
                activeControl = nil
            }
        }
    }

    private func formatSeekDelta(_ seconds: Int) -> String {
        let absSeconds = abs(seconds)
        let minutes = absSeconds / 60
        let rem = absSeconds % 60
        if minutes > 0 {
            return String(format: "%d:%02d", minutes, rem)
        }
        return "\(absSeconds)s"
    }

    // MARK: - Rail chrome

    private func sideRail(kind: SideControl, progress: Double, accessibility: String) -> some View {
        let percent: Int = {
            switch kind {
            case .volume:
                if viewModel.isMuted { return 0 }
                return Int(viewModel.session.info.volume.rounded())
            case .brightness:
                return Int((progress * 100).rounded())
            }
        }()
        return VStack(spacing: 10) {
            railIcon(kind: kind, progress: progress)

            GeometryReader { proxy in
                let fill = max(0, min(1, progress))
                ZStack(alignment: .bottom) {
                    Capsule()
                        .fill(.white.opacity(0.18))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [accent, accent.opacity(0.82)],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(height: max(6, proxy.size.height * fill))
                }
            }
            .frame(width: 4)
            .frame(height: 112)

            Text("\(percent)%")
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.78))
                .frame(width: 40, alignment: .center)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(width: 40)
        .transaction { $0.animation = nil }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility)
        .accessibilityValue("\(percent) percent")
    }

    @ViewBuilder
    private func railIcon(kind: SideControl, progress: Double) -> some View {
        let symbols = iconNames(for: kind)
        let active = activeIconName(for: kind, progress: progress)
        ZStack {
            ForEach(symbols, id: \.self) { name in
                Image(systemName: name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .opacity(name == active ? 1 : 0)
            }
        }
        .frame(width: 36, height: 18)
    }

    private func iconNames(for kind: SideControl) -> [String] {
        switch kind {
        case .brightness:
            return ["sun.min.fill", "sun.max", "sun.max.fill"]
        case .volume:
            return [
                "speaker.slash.fill",
                "speaker.wave.1.fill",
                "speaker.wave.2.fill",
                "speaker.wave.3.fill"
            ]
        }
    }

    private func activeIconName(for kind: SideControl, progress: Double) -> String {
        switch kind {
        case .brightness:
            if progress < 0.2 { return "sun.min.fill" }
            if progress < 0.6 { return "sun.max" }
            return "sun.max.fill"
        case .volume:
            if viewModel.isMuted || progress == 0 { return "speaker.slash.fill" }
            if progress < 0.35 { return "speaker.wave.1.fill" }
            if progress < 0.7 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        }
    }

    // MARK: - Brightness helpers

    private func currentScreenBrightness() -> Double {
        #if os(iOS)
        Double(UIScreen.main.brightness)
        #else
        0.6
        #endif
    }

    private func setScreenBrightness(_ value: Double) {
        #if os(iOS)
        UIScreen.main.brightness = CGFloat(min(1, max(0, value)))
        #endif
    }
}
