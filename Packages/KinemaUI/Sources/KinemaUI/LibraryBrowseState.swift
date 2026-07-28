import Foundation
import KinemaCore
import KinemaMedia

public struct BrowseBreadcrumb: Identifiable, Equatable {
    public enum Kind: Equatable {
        case library
        case root
        case folder
        case virtual
    }

    public let id: String
    public let title: String
    public let systemImage: String
    public let kind: Kind
    public let isCurrent: Bool

    public init(id: String, title: String, systemImage: String, kind: Kind, isCurrent: Bool) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.kind = kind
        self.isCurrent = isCurrent
    }
}

@MainActor
@Observable
public final class LibraryBrowseState {
    public var selectedRootID: UUID?
    public var currentDirectory: URL?
    public var folderTrail: [URL] = []
    public var virtualPath: [VirtualBrowseSegment] = []

    /// Stable reference — never assign this from a computed getter during SwiftUI body.
    public let rootStore: LibraryRootStore

    public init(rootStore: LibraryRootStore) {
        self.rootStore = rootStore
    }

    public init() {
        self.rootStore = .shared
    }

    public var isAtLibraryHome: Bool { selectedRootID == nil }

    public var selectedRoot: LibraryRoot? {
        guard let selectedRootID else { return nil }
        return rootStore.root(for: selectedRootID)
    }

    public var libraryRootURL: URL? {
        guard let selectedRoot else { return nil }
        return rootStore.resolveURL(for: selectedRoot)
    }

    public var canGoUp: Bool {
        if !virtualPath.isEmpty { return true }
        if !folderTrail.isEmpty { return true }
        if selectedRootID != nil { return true }
        return false
    }

    public func openRoot(_ root: LibraryRoot) {
        guard let url = rootStore.resolveURL(for: root) else { return }
        folderTrail = []
        virtualPath = []
        // Set destination path before selection so reload never lands on a nil directory
        // for a selected root (which briefly showed the empty state).
        currentDirectory = url
        selectedRootID = root.id
    }

    public func goToLibraryHome() {
        selectedRootID = nil
        currentDirectory = nil
        folderTrail = []
        virtualPath = []
    }

    public func openFolder(_ url: URL) {
        guard let rootURL = libraryRootURL else { return }
        let standardized = url.standardizedFileURL
        let rootPath = rootURL.standardizedFileURL.path
        guard standardized.path.hasPrefix(rootPath) else { return }
        folderTrail.append(standardized)
        currentDirectory = standardized
        virtualPath = []
    }

    public func openVirtual(_ segment: VirtualBrowseSegment) {
        virtualPath.append(segment)
    }

    public func goUp() {
        if !virtualPath.isEmpty {
            virtualPath.removeLast()
            return
        }
        if !folderTrail.isEmpty {
            folderTrail.removeLast()
            currentDirectory = folderTrail.last ?? libraryRootURL
            return
        }
        if selectedRootID != nil {
            goToLibraryHome()
        }
    }

    public func navigateToBreadcrumb(_ breadcrumb: BrowseBreadcrumb) {
        switch breadcrumb.kind {
        case .library:
            goToLibraryHome()
        case .root:
            if let root = selectedRoot {
                openRoot(root)
            }
        case .folder:
            guard let url = folderURL(forBreadcrumbID: breadcrumb.id) else { return }
            if let index = folderTrail.firstIndex(of: url) {
                folderTrail = Array(folderTrail.prefix(index + 1))
                currentDirectory = url
                virtualPath = []
            }
        case .virtual:
            if let index = virtualPath.firstIndex(where: { virtualBreadcrumbID($0) == breadcrumb.id }) {
                virtualPath = Array(virtualPath.prefix(index + 1))
            }
        }
    }

    public var breadcrumbs: [BrowseBreadcrumb] {
        var crumbs: [BrowseBreadcrumb] = []

        crumbs.append(BrowseBreadcrumb(
            id: "library",
            title: KinemaCopy.collection,
            systemImage: "square.grid.2x2.fill",
            kind: .library,
            isCurrent: isAtLibraryHome
        ))

        guard let root = selectedRoot, let rootURL = libraryRootURL else { return crumbs }

        let atRootFolder = folderTrail.isEmpty && virtualPath.isEmpty
        crumbs.append(BrowseBreadcrumb(
            id: "root-\(root.id.uuidString)",
            title: root.name,
            systemImage: root.isBuiltIn ? "film.stack.fill" : "externaldrive.fill",
            kind: .root,
            isCurrent: atRootFolder
        ))

        for (index, folderURL) in folderTrail.enumerated() {
            let isLastPhysical = index == folderTrail.count - 1 && virtualPath.isEmpty
            crumbs.append(BrowseBreadcrumb(
                id: folderBreadcrumbID(folderURL),
                title: folderURL.lastPathComponent,
                systemImage: "folder.fill",
                kind: .folder,
                isCurrent: isLastPhysical
            ))
        }

        for (index, segment) in virtualPath.enumerated() {
            let isLast = index == virtualPath.count - 1
            crumbs.append(BrowseBreadcrumb(
                id: virtualBreadcrumbID(segment),
                title: segment.displayTitle,
                systemImage: "rectangle.stack.fill",
                kind: .virtual,
                isCurrent: isLast
            ))
        }

        return crumbs
    }

    private func folderBreadcrumbID(_ url: URL) -> String {
        "folder-\(url.standardizedFileURL.path)"
    }

    private func folderURL(forBreadcrumbID id: String) -> URL? {
        folderTrail.first { folderBreadcrumbID($0) == id }
    }

    private func virtualBreadcrumbID(_ segment: VirtualBrowseSegment) -> String {
        switch segment {
        case .show(let key, _):
            return "virtual-show-\(key)"
        case .season(let number, let showKey, _):
            return "virtual-season-\(showKey)-\(number)"
        }
    }
}
