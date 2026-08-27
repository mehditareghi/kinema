import SwiftUI
import KinemaCore
import KinemaPlayback

/// Cycles / picks lineup Off · Repeat One · Repeat All · Shuffle.
struct PlaylistModeControl: View {
    @Bindable var viewModel: PlayerViewModel
    let accent: Color

    private var mode: PlaylistPlaybackMode { viewModel.session.playlistMode }

    var body: some View {
        Menu {
            ForEach(PlaylistPlaybackMode.allCases) { option in
                Button {
                    let message = viewModel.session.setPlaylistMode(option)
                    viewModel.showOSD(message)
                    viewModel.scheduleHideControls()
                } label: {
                    if mode == option {
                        Label(option.displayName, systemImage: "checkmark")
                    } else {
                        Label(option.displayName, systemImage: option.systemImage)
                    }
                }
            }
        } label: {
            Image(systemName: mode.systemImage)
                .font(KinemaType.bodyMedium)
                .frame(width: 44, height: 44)
                .foregroundStyle(mode == .off ? Color.white : accent)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .accessibilityLabel(KinemaCopy.playlistMode)
        .accessibilityValue(mode.displayName)
    }
}
