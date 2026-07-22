#if os(macOS)
import AppKit
import KinemaCore

class ShareViewController: NSViewController {
    override func loadView() {
        view = NSView()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            complete()
            return
        }
        for item in items {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier("public.url") {
                    provider.loadItem(forTypeIdentifier: "public.url") { [weak self] obj, _ in
                        if let url = obj as? URL, let link = DeepLinkParser.buildOpenURL(mediaURL: url) {
                            NSWorkspace.shared.open(link)
                        }
                        self?.complete()
                    }
                    return
                }
            }
        }
        complete()
    }

    private func complete() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
#endif
