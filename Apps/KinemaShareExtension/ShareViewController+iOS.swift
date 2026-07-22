#if os(iOS)
import UIKit
import UniformTypeIdentifiers
import KinemaCore

class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        handleSharedItems()
    }

    private func handleSharedItems() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem else {
            complete()
            return
        }

        let providers = extensionItem.attachments ?? []
        let typeOrder: [UTType] = [
            .movie,
            .video,
            .audiovisualContent,
            .mpeg4Movie,
            .quickTimeMovie,
            .avi,
            .mpeg,
            .fileURL,
            .url,
            .data
        ]

        for type in typeOrder {
            guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(type.identifier) }) else {
                continue
            }
            provider.loadItem(forTypeIdentifier: type.identifier) { [weak self] item, _ in
                guard let self else { return }
                if let url = item as? URL {
                    self.openInKinema(url: url)
                    return
                }
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    self.openInKinema(url: url)
                    return
                }
                self.complete()
            }
            return
        }

        complete()
    }

    private func openInKinema(url: URL) {
        guard let deepLink = DeepLinkParser.buildOpenURL(mediaURL: url) else {
            complete()
            return
        }
        extensionContext?.open(deepLink, completionHandler: { _ in
            self.complete()
        })
    }

    private func complete() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
#endif
