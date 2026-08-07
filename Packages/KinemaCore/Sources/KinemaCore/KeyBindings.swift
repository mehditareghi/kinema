import Foundation

public struct KeyBinding: Codable, Sendable, Identifiable, Hashable {
    public var id: String { action }
    public let action: String
    public let keys: [String]
    public let description: String

    public init(action: String, keys: [String], description: String) {
        self.action = action
        self.keys = keys
        self.description = description
    }
}

public enum KeyBindingDefaults {
    public static let bindings: [KeyBinding] = [
        KeyBinding(action: "play-pause", keys: ["space"], description: "Play / Pause"),
        KeyBinding(action: "seek-back-5", keys: ["left", "j"], description: "Seek back 5 seconds"),
        KeyBinding(action: "seek-forward-5", keys: ["right", "l"], description: "Seek forward 5 seconds"),
        KeyBinding(action: "pause", keys: ["k"], description: "Pause"),
        KeyBinding(action: "volume-up", keys: ["up"], description: "Volume up"),
        KeyBinding(action: "volume-down", keys: ["down"], description: "Volume down"),
        KeyBinding(action: "mute", keys: ["m"], description: "Mute"),
        KeyBinding(action: "fullscreen", keys: ["f"], description: "Toggle fullscreen"),
        KeyBinding(action: "speed-up", keys: ["]"], description: "Increase speed"),
        KeyBinding(action: "speed-down", keys: ["["], description: "Decrease speed"),
        KeyBinding(action: "subtitle-cycle", keys: ["v"], description: "Cycle subtitles"),
        KeyBinding(action: "audio-cycle", keys: ["a"], description: "Cycle audio tracks"),
        KeyBinding(action: "chapter-prev", keys: [","], description: "Previous chapter"),
        KeyBinding(action: "chapter-next", keys: ["."], description: "Next chapter"),
        KeyBinding(action: "ab-loop", keys: ["b"], description: "A–B loop (set A / set B / clear)")
    ]

    public static func load() -> [KeyBinding] {
        guard let url = Bundle.module.url(forResource: "DefaultKeyBindings", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([KeyBinding].self, from: data) else {
            return bindings
        }
        return decoded
    }
}
