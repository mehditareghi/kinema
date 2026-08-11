import Foundation

public struct KeyBinding: Codable, Sendable, Identifiable, Hashable {
    public var id: String { action }
    public let action: String
    public var keys: [String]
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
        KeyBinding(action: "seek-back-5", keys: ["left", "j"], description: "Seek back (step)"),
        KeyBinding(action: "seek-forward-5", keys: ["right", "l"], description: "Seek forward (step)"),
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
        KeyBinding(action: "ab-loop", keys: ["b"], description: "A–B loop (set A / set B / clear)"),
        KeyBinding(action: "subtitle-delay-down", keys: ["g"], description: "Subtitle delay −0.1s"),
        KeyBinding(action: "subtitle-delay-up", keys: ["h"], description: "Subtitle delay +0.1s"),
        KeyBinding(action: "subtitle-bookmark-audio", keys: ["z"], description: "Mark audio for subtitle sync"),
        KeyBinding(action: "subtitle-bookmark-sub", keys: ["x"], description: "Mark subtitle for sync"),
        KeyBinding(action: "subtitle-bookmark-apply", keys: ["c"], description: "Apply subtitle bookmark sync")
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

/// Normalizes player / Settings key capture tokens to the binding vocabulary.
public enum KeyBindingNormalizer {
    public static func normalizeToken(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lower = trimmed.lowercased()
        switch lower {
        case " ", "space", "\u{00a0}":
            return "space"
        case "\u{1f}", "\u{F700}", "uparrow", "up arrow":
            return "up"
        case "\u{1e}", "\u{F701}", "downarrow", "down arrow":
            return "down"
        case "\u{1c}", "\u{F702}", "leftarrow", "left arrow":
            return "left"
        case "\u{1d}", "\u{F703}", "rightarrow", "right arrow":
            return "right"
        case "\r", "\n", "return", "enter":
            return "return"
        case "\u{1b}", "escape", "esc":
            return "escape"
        default:
            break
        }

        // Single printable character (letters, digits, punctuation).
        if trimmed.count == 1 {
            return lower
        }

        // Named tokens already in our vocabulary.
        let allowed = Set([
            "space", "left", "right", "up", "down", "return", "escape",
            "tab", "delete", "forwarddelete"
        ])
        if allowed.contains(lower) { return lower }

        return nil
    }

    public static func displayName(for token: String) -> String {
        switch token {
        case "space": return "Space"
        case "left": return "←"
        case "right": return "→"
        case "up": return "↑"
        case "down": return "↓"
        case "return": return "Return"
        case "escape": return "Esc"
        default: return token
        }
    }
}

@MainActor
@Observable
public final class KeyBindingStore {
    public static let shared = KeyBindingStore()

    private let defaults = UserDefaults.standard
    private let overridesKey = "kinema.keyBindingOverrides"

    /// action → custom keys (nil / missing means use default).
    private var overrides: [String: [String]] = [:]

    public private(set) var bindings: [KeyBinding] = []

    private init() {
        loadOverrides()
        rebuild()
    }

    public var hasOverrides: Bool { !overrides.isEmpty }

    public func binding(for action: String) -> KeyBinding? {
        bindings.first { $0.action == action }
    }

    public func handlesKey(_ key: String) -> Bool {
        let token = KeyBindingNormalizer.normalizeToken(key) ?? key.lowercased()
        return bindings.contains { $0.keys.contains(token) }
    }

    public func bindingMatchingKey(_ key: String) -> KeyBinding? {
        let token = KeyBindingNormalizer.normalizeToken(key) ?? key.lowercased()
        return bindings.first { $0.keys.contains(token) }
    }

    /// Other actions (besides `action`) that already use `key`.
    public func conflicts(for key: String, excluding action: String) -> [KeyBinding] {
        let token = KeyBindingNormalizer.normalizeToken(key) ?? key.lowercased()
        return bindings.filter { $0.action != action && $0.keys.contains(token) }
    }

    public func isCustomized(_ action: String) -> Bool {
        overrides[action] != nil
    }

    /// Replace keys for an action. Conflicting keys are removed from other actions.
    @discardableResult
    public func setKeys(_ keys: [String], for action: String) -> [KeyBinding] {
        let normalized = keys.compactMap(KeyBindingNormalizer.normalizeToken(_:))
        var unique: [String] = []
        for key in normalized where !unique.contains(key) {
            unique.append(key)
        }

        let stolenFrom = steal(keys: unique, excluding: action)
        let defaults = KeyBindingDefaults.load()
        if let defaultBinding = defaults.first(where: { $0.action == action }),
           defaultBinding.keys == unique {
            overrides.removeValue(forKey: action)
        } else {
            overrides[action] = unique
        }
        persist()
        rebuild()
        return stolenFrom
    }

    /// Append a key to an action (stealing from others if needed).
    @discardableResult
    public func addKey(_ key: String, to action: String) -> [KeyBinding] {
        guard let token = KeyBindingNormalizer.normalizeToken(key) else { return [] }
        var current = binding(for: action)?.keys ?? []
        if current.contains(token) { return [] }
        current.append(token)
        return setKeys(current, for: action)
    }

    public func removeKey(_ key: String, from action: String) {
        guard var current = binding(for: action)?.keys else { return }
        current.removeAll { $0 == key }
        _ = setKeys(current, for: action)
    }

    public func reset(_ action: String) {
        overrides.removeValue(forKey: action)
        persist()
        rebuild()
    }

    public func resetAll() {
        overrides.removeAll()
        persist()
        rebuild()
    }

    private func steal(keys: [String], excluding action: String) -> [KeyBinding] {
        var affected: [KeyBinding] = []
        let defaults = KeyBindingDefaults.load()
        for other in bindings where other.action != action {
            let overlap = other.keys.filter(keys.contains)
            guard !overlap.isEmpty else { continue }
            let remaining = other.keys.filter { !keys.contains($0) }
            affected.append(other)
            if let defaultBinding = defaults.first(where: { $0.action == other.action }),
               defaultBinding.keys == remaining {
                overrides.removeValue(forKey: other.action)
            } else {
                overrides[other.action] = remaining
            }
        }
        return affected
    }

    private func rebuild() {
        bindings = KeyBindingDefaults.load().map { defaultBinding in
            if let custom = overrides[defaultBinding.action] {
                return KeyBinding(
                    action: defaultBinding.action,
                    keys: custom,
                    description: defaultBinding.description
                )
            }
            return defaultBinding
        }
    }

    private func loadOverrides() {
        guard let data = defaults.data(forKey: overridesKey),
              let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) else {
            overrides = [:]
            return
        }
        overrides = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(overrides) else { return }
        defaults.set(data, forKey: overridesKey)
    }
}
