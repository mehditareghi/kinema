import Foundation

public struct LibraryRoot: Identifiable, Codable, Sendable, Equatable, Hashable {
    public let id: UUID
    public var name: String
    public var bookmarkData: Data?
    public var path: String?
    public var dateAdded: Date

    public init(
        id: UUID = UUID(),
        name: String,
        bookmarkData: Data? = nil,
        path: String? = nil,
        dateAdded: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.bookmarkData = bookmarkData
        self.path = path
        self.dateAdded = dateAdded
    }
}

@MainActor
@Observable
public final class LibraryRootStore {
    public static let shared = LibraryRootStore()

    public private(set) var roots: [LibraryRoot] = []

    private let rootsKey = "io.kinema.library.roots"
    private let legacyBookmarkKey = "io.kinema.library.folderBookmark"
    private var accessedURLs: [UUID: URL] = [:]

    private init() {
        load()
        migrateLegacySingleFolderIfNeeded()
        restoreAccessForAllRoots()
    }

    public var documentsURL: URL {
        #if os(iOS) || os(tvOS)
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        #else
        FileManager.default.homeDirectoryForCurrentUser
        #endif
    }

    @discardableResult
    public func addRoot(from url: URL) -> LibraryRoot? {
        let standardized = url.standardizedFileURL
        guard isExistingDirectory(standardized) else { return nil }

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
            path: standardized.path
        )
        roots.append(root)
        accessedURLs[root.id] = standardized
        save()
        return root
    }

    public func removeRoot(id: UUID) {
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
              let index = roots.firstIndex(where: { $0.id == id }) else { return }
        roots[index].name = trimmed
        save()
    }

    public func resolveURL(for root: LibraryRoot) -> URL? {
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
                accessedURLs[root.id] = url.standardizedFileURL
                return url.standardizedFileURL
            }
        }

        if let path = root.path {
            let url = URL(fileURLWithPath: path, isDirectory: true)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            _ = url.startAccessingSecurityScopedResource()
            accessedURLs[root.id] = url.standardizedFileURL
            return url.standardizedFileURL
        }

        return nil
    }

    public func root(for id: UUID) -> LibraryRoot? {
        roots.first { $0.id == id }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: rootsKey),
              let decoded = try? JSONDecoder().decode([LibraryRoot].self, from: data) else {
            roots = []
            return
        }
        roots = decoded.sorted { $0.dateAdded < $1.dateAdded }
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
            path: url.standardizedFileURL.path
        )
        roots = [root]
        accessedURLs[root.id] = url.standardizedFileURL
        save()
        UserDefaults.standard.removeObject(forKey: legacyBookmarkKey)
    }

    private func restoreAccessForAllRoots() {
        for root in roots {
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
