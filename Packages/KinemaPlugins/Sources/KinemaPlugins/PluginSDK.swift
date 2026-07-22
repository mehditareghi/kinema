import Foundation
import KinemaCore
import KinemaPlayback

public protocol KinemaPlugin: Sendable {
    var identifier: String { get }
    var name: String { get }
    var version: String { get }
    func activate(context: PluginContext) async
    func deactivate() async
}

public struct PluginContext: @unchecked Sendable {
    @MainActor public let session: PlayerSession

    @MainActor
    public init(session: PlayerSession) {
        self.session = session
    }
}

public struct PluginManifest: Codable, Sendable, Identifiable {
    public var id: String { identifier }
    public let identifier: String
    public let name: String
    public let version: String
    public let description: String
    public let permissions: [String]

    public init(identifier: String, name: String, version: String, description: String, permissions: [String] = []) {
        self.identifier = identifier
        self.name = name
        self.version = version
        self.description = description
        self.permissions = permissions
    }
}

@MainActor
public final class PluginRegistry {
    public static let shared = PluginRegistry()

    private var plugins: [String: any KinemaPlugin] = [:]

    private init() {}

    public func register(_ plugin: any KinemaPlugin) {
        plugins[plugin.identifier] = plugin
    }

    public func activateAll(for session: PlayerSession) async {
        let context = PluginContext(session: session)
        for plugin in plugins.values {
            await plugin.activate(context: context)
        }
    }

    public var manifests: [PluginManifest] {
        plugins.values.map {
            PluginManifest(identifier: $0.identifier, name: $0.name, version: $0.version, description: "")
        }
    }
}

/// Built-in sample plugin stub demonstrating the SDK.
public struct SamplePlugin: KinemaPlugin {
    public let identifier = "io.kinema.sample"
    public let name = "Sample Plugin"
    public let version = "1.0.0"

    public init() {}

    public func activate(context: PluginContext) async {}
    public func deactivate() async {}
}
