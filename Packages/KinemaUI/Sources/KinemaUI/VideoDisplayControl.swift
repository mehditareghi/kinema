import SwiftUI
import KinemaCore
import KinemaPlayback

/// VLC-style picture menu: fit / fill / stretch, zoom, rotate.
struct VideoDisplayControl: View {
    @Bindable var viewModel: PlayerViewModel
    let accent: Color

    var body: some View {
        Menu {
            Section(KinemaCopy.picture) {
                ForEach(VideoFitMode.allCases) { mode in
                    Button {
                        apply(viewModel.session.setVideoFitMode(mode))
                    } label: {
                        if viewModel.session.videoFitMode == mode {
                            Label(mode.displayName, systemImage: "checkmark")
                        } else {
                            Text(mode.displayName)
                        }
                    }
                }
            }

            Section {
                Button {
                    apply(viewModel.session.adjustVideoZoom(by: 0.1))
                } label: {
                    Label(KinemaCopy.pictureZoomIn, systemImage: "plus.magnifyingglass")
                }
                Button {
                    apply(viewModel.session.adjustVideoZoom(by: -0.1))
                } label: {
                    Label(KinemaCopy.pictureZoomOut, systemImage: "minus.magnifyingglass")
                }
                Button {
                    apply(viewModel.session.rotateVideo90())
                } label: {
                    Label(KinemaCopy.pictureRotate, systemImage: "rotate.right")
                }
            }

            if viewModel.session.isVideoDisplayCustomized {
                Button {
                    apply(viewModel.session.resetVideoDisplay())
                } label: {
                    Label(KinemaCopy.pictureReset, systemImage: "arrow.counterclockwise")
                }
            }
        } label: {
            Image(systemName: "aspectratio")
                .font(KinemaType.bodyMedium)
                .frame(width: 44, height: 44)
                .foregroundStyle(viewModel.session.isVideoDisplayCustomized ? accent : .white)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .accessibilityLabel(KinemaCopy.picture)
    }

    private func apply(_ message: String) {
        viewModel.cancelAutoHideControls()
        viewModel.showOSD(message)
        viewModel.scheduleHideControls()
    }
}
