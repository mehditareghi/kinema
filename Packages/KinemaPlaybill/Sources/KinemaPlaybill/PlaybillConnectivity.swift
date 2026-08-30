import Foundation
import Network
import Observation

/// Reachability is presentation and retry guidance only. Individual requests remain
/// authoritative because a satisfied path does not guarantee that TMDB is reachable.
@MainActor
@Observable
public final class PlaybillConnectivity {
    public static let shared = PlaybillConnectivity()

    public private(set) var isOnline = true
    public private(set) var hasDeterminedStatus = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "app.kinema.playbill.connectivity")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasOnline = self.isOnline
                let wasDetermined = self.hasDeterminedStatus
                self.isOnline = online
                self.hasDeterminedStatus = true
                if online && (!wasDetermined || !wasOnline) {
                    await PendingWatchResolver.retryAll()
                }
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
