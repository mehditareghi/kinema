import Foundation

/// Optional lightweight notifier for library refresh.
/// Intentionally does **not** use DispatchSource file watching on the built-in
/// Documents directory — that feedback loop freezes / watchdog-kills iOS apps.
@MainActor
public final class LibraryDirectoryWatcher {
    public static let shared = LibraryDirectoryWatcher()

    private var isEmitting = false

    private init() {}

    public func startWatching(url: URL) {
        // No-op: FS watching disabled (see type comment).
    }

    public func stopWatching(url: URL) {}

    public func stopAll() {}

    public func watchBuiltInRoot() {
        // No-op: refresh via scenePhase / manual Rescan instead.
    }

    public func suppressEvents(for interval: TimeInterval = 1.0) {}

    public func forceNotify() {
        guard !isEmitting else { return }
        isEmitting = true
        EventBus.shared.emit(.libraryChanged)
        isEmitting = false
    }
}
