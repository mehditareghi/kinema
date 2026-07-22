#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers
import KinemaCore
import KinemaUI

struct MacOSDropModifier: ViewModifier {
    @Bindable var viewModel: PlayerViewModel

    func body(content: Content) -> some View {
        content.onDrop(of: [.fileURL, .movie, .video, .audio], isTargeted: nil) { providers in
            Task {
                var urls: [URL] = []
                for provider in providers {
                    if let item = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier),
                       let data = item as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil) {
                        urls.append(url)
                    }
                }
                guard !urls.isEmpty else { return }
                let items = urls.map { MediaItem(url: $0) }
                await viewModel.openItems(items)
            }
            return true
        }
    }
}

extension View {
    func macOSFileDrop(viewModel: PlayerViewModel) -> some View {
        modifier(MacOSDropModifier(viewModel: viewModel))
    }
}
#endif
