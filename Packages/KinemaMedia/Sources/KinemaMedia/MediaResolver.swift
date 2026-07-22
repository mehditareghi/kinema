import Foundation
import KinemaCore

public protocol MediaResolver: Sendable {
    func canResolve(_ url: URL) -> Bool
    func resolve(_ url: URL) async throws -> URL
}

public struct PassthroughMediaResolver: MediaResolver {
    public init() {}

    public func canResolve(_ url: URL) -> Bool {
        url.scheme?.hasPrefix("http") == true || url.isFileURL
    }

    public func resolve(_ url: URL) async throws -> URL {
        url
    }
}

public enum MediaResolverFactory {
    public static func makeDefault() -> MediaResolver {
        #if os(macOS)
        return CompositeMediaResolver(resolvers: [YTDLPResolver(), PassthroughMediaResolver()])
        #else
        return PassthroughMediaResolver()
        #endif
    }
}

public struct CompositeMediaResolver: MediaResolver {
    private let resolvers: [MediaResolver]

    public init(resolvers: [MediaResolver]) {
        self.resolvers = resolvers
    }

    public func canResolve(_ url: URL) -> Bool {
        resolvers.contains { $0.canResolve(url) }
    }

    public func resolve(_ url: URL) async throws -> URL {
        for resolver in resolvers {
            if resolver.canResolve(url) {
                return try await resolver.resolve(url)
            }
        }
        return url
    }
}
