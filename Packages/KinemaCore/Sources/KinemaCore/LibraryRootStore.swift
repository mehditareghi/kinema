import Foundation

public enum LibraryRootKind: String, Codable, Sendable, Equatable, Hashable {
    case builtIn
    case user
}

public struct LibraryRoot: Identifiable, Codable, Sendable, Equatable, Hashable {
    public let id: UUID
    public var name: String
    public var bookmarkData: Data?
    public var path: String?
    public var dateAdded: Date
    public var kind: LibraryRootKind

    public var isBuiltIn: Bool { kind == .builtIn }

    public init(
        id: UUID = UUID(),
        name: String,
        bookmarkData: Data? = nil,
        path: String? = nil,
        dateAdded: Date = Date(),
        kind: LibraryRootKind = .user
    ) {
        self.id = id
        self.name = name
        self.bookmarkData = bookmarkData
        self.path = path
        self.dateAdded = dateAdded
        self.kind = kind
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, bookmarkData, path, dateAdded, kind
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        bookmarkData = try container.decodeIfPresent(Data.self, forKey: .bookmarkData)
        path = try container.decodeIfPresent(String.self, forKey: .path)
        dateAdded = try container.decode(Date.self, forKey: .dateAdded)
        kind = try container.decodeIfPresent(LibraryRootKind.self, forKey: .kind) ?? .user
    }
}

@MainActor
@Observable
public final class LibraryRootStore {
    public static let shared = LibraryRootStore()

    public private(set) var roots: [LibraryRoot] = []

    private let rootsKey = "io.kinema.library.roots"
    private let legacyBookmarkKey = "io.kinema.library.folderBookmark"
    private let builtInRootID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    private var accessedURLs: [UUID: URL] = [:]
    private var didPrepareServices = false

    private init() {
        load()
        migrateLegacySingleFolderIfNeeded()
        ensureBuiltInRoot()
        // Bookmark restore / placeholder creation deferred to prepareLibraryServices().
    }

    public var builtInMediaURL: URL {
        LibraryMediaPaths.builtInMediaURL
    }

    /// Legacy alias — prefer `builtInMediaURL`.
    public var documentsURL: URL { builtInMediaURL }

    public var builtInRoot: LibraryRoot? {
        roots.first(where: \.isBuiltIn)
    }

    /// Call once after the first UI frame. Safe to call repeatedly.
    public func prepareLibraryServices() {
        guard !didPrepareServices else { return }
        didPrepareServices = true
        _ = LibraryMediaPaths.ensureBuiltInDirectory()
        LibraryMediaPaths.removeLegacyPlaceholderIfNeeded()
        restoreAccessForAllRoots()
    }

    public func handleAppBecameActive() {
        prepareLibraryServices()
        // Intentionally do not create/delete files under Documents here.
        // Finder/USB file sharing mounts that folder — concurrent writes drop the link.
    }

    @discardableResult
    public func addRoot(from url: URL) -> LibraryRoot? {
        let standardized = url.standardizedFileURL
        guard isExistingDirectory(standardized) else { return nil }

        if standardized == LibraryMediaPaths.ensureBuiltInDirectory().standardizedFileURL {
            return builtInRoot
        }

        if let existing = roots.first(where: { root in
            guard let resolved = resolveURL(for: root) else { return false }
            return resolved.standardizedFileURL == standardized
        }) {
            return existing
        }

        _ = url.startAccessingSecurityScopedResource()

        var bookmarkData: Data?
        #if os(iOS) || os(tvOS)
        bookmarkData = try? url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #endif

        let name = displayName(for: url)
        let root = LibraryRoot(
            name: name,
            bookmarkData: bookmarkData,
            path: standardized.path,
            kind: .user
        )
        roots.append(root)
        accessedURLs[root.id] = standardized
        save()
        return root
    }

    public func removeRoot(id: UUID) {
        guard let root = roots.first(where: { $0.id == id }), !root.isBuiltIn else { return }
        if let url = accessedURLs[id] {
            url.stopAccessingSecurityScopedResource()
        }
        accessedURLs.removeValue(forKey: id)
        roots.removeAll { $0.id == id }
        save()
    }

    public func renameRoot(id: UUID, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = roots.firstIndex(where: { $0.id == id }),
              !roots[index].isBuiltIn else { return }
        roots[index].name = trimmed
        save()
    }

    public func resolveURL(for root: LibraryRoot) -> URL? {
        if root.isBuiltIn {
            // Never mutate `accessedURLs` here — this is called from SwiftUI body
            // (tiles / breadcrumbs). Writing @Observable state during body eval
            // causes an infinite render loop (~200% CPU → watchdog kill).
            return LibraryMediaPaths.builtInMediaURL.standardizedFileURL
        }

        if let cached = accessedURLs[root.id] {
            return cached
        }

        if let bookmarkData = root.bookmarkData {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: .withoutUI,
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                _ = url.startAccessingSecurityScopedResource()
                cacheAccessURL(url.standardizedFileURL, for: root.id)
                return url.standardizedFileURL
            }
        }

        if let path = root.path {
            let url = URL(fileURLWithPath: path, isDirectory: true)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            _ = url.startAccessingSecurityScopedResource()
            cacheAccessURL(url.standardizedFileURL, for: root.id)
            return url.standardizedFileURL
        }

        return nil
    }

    private func cacheAccessURL(_ url: URL, for id: UUID) {
        if accessedURLs[id] != url {
            accessedURLs[id] = url
        }
    }

    public func root(for id: UUID) -> LibraryRoot? {
        roots.first { $0.id == id }
    }

    private func ensureBuiltInRoot() {
        let mediaURL = LibraryMediaPaths.builtInMediaURL
        let mediaPath = mediaURL.path

        if let index = roots.firstIndex(where: \.isBuiltIn) {
            var root = roots[index]
            let needsUpdate =
                root.path != mediaPath
                || root.name != LibraryMediaPaths.builtInDisplayName
                || root.bookmarkData != nil
                || root.id != builtInRootID
            guard needsUpdate else { return }
            root = LibraryRoot(
                id: builtInRootID,
                name: LibraryMediaPaths.builtInDisplayName,
                bookmarkData: nil,
                path: mediaPath,
                dateAdded: root.dateAdded,
                kind: .builtIn
            )
            roots[index] = root
            sortRoots()
            save()
            return
        }

        if let index = roots.firstIndex(where: {
            $0.path == mediaPath || $0.name == LibraryMediaPaths.builtInDisplayName
        }) {
            // Promote legacy path-matched root if any.
            let promoted = roots.remove(at: index)
            let root = LibraryRoot(
                id: builtInRootID,
                name: LibraryMediaPaths.builtInDisplayName,
                bookmarkData: nil,
                path: mediaPath,
                dateAdded: promoted.dateAdded,
                kind: .builtIn
            )
            roots.insert(root, at: 0)
        } else {
            let root = LibraryRoot(
                id: builtInRootID,
                name: LibraryMediaPaths.builtInDisplayName,
                path: mediaPath,
                dateAdded: Date.distantPast,
                kind: .builtIn
            )
            roots.insert(root, at: 0)
        }
        sortRoots()
        save()
    }

    private func sortRoots() {
        roots.sort { lhs, rhs in
            if lhs.isBuiltIn != rhs.isBuiltIn { return lhs.isBuiltIn }
            return lhs.dateAdded < rhs.dateAdded
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: rootsKey),
              let decoded = try? JSONDecoder().decode([LibraryRoot].self, from: data) else {
            roots = []
            return
        }
        roots = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(roots) else { return }
        UserDefaults.standard.set(data, forKey: rootsKey)
    }

    private func migrateLegacySingleFolderIfNeeded() {
        guard roots.isEmpty,
              let data = UserDefaults.standard.data(forKey: legacyBookmarkKey) else { return }

        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withoutUI,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return }

        _ = url.startAccessingSecurityScopedResource()
        let root = LibraryRoot(
            name: displayName(for: url),
            bookmarkData: data,
            path: url.standardizedFileURL.path,
            kind: .user
        )
        roots = [root]
        accessedURLs[root.id] = url.standardizedFileURL
        save()
        UserDefaults.standard.removeObject(forKey: legacyBookmarkKey)
    }

    private func restoreAccessForAllRoots() {
        for root in roots where !root.isBuiltIn {
            _ = resolveURL(for: root)
        }
    }

    private func displayName(for url: URL) -> String {
        let name = url.lastPathComponent
        return name.isEmpty ? url.path : name
    }

    private func isExistingDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return false }
        return isDirectory.boolValue
    }
}
