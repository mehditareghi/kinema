import Foundation
import KinemaCore

@MainActor
@Observable
public final class PlaybillPromptCenter {
    public static let shared = PlaybillPromptCenter()

    public private(set) var pendingPrompt: PlaybillMatchPrompt?

    private init() {}

    public func present(_ prompt: PlaybillMatchPrompt) {
        pendingPrompt = prompt
        EventBus.shared.emit(.playbillMatchPromptRequested)
    }

    public func clear() {
        pendingPrompt = nil
    }
}
