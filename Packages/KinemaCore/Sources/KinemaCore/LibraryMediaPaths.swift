import Foundation

/// Platform-specific permanent media root and housekeeping for the built-in library.
public enum LibraryMediaPaths {
    public static let builtInDisplayName = "Kinema"
    public static let placeholderFileName = "Add media files here"
    public static let logsFolderName = "Logs"
    public static let trashFolderName = ".Trash"
    public static let wifiUploadTempFolderName = "WiFiUploadTemp"

    /// Folders/files that must never appear as browsable library content.
    public static let ignoredNames: Set<String> = [
        logsFolderName,
        trashFolderName,
        placeholderFileName,
        wifiUploadTempFolderName,
        ".DS_Store",
        "Inbox"
    ]

    public static let incompleteNameSuffixes = [
        ".download", ".part", ".partial", ".tmp", ".temp", ".crdownload", ".iktemp"
    ]

    public static var builtInMediaURL: URL {
        #if os(macOS)
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Kinema/Media", isDirectory: true)
        #elseif os(tvOS)
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return caches.appendingPathComponent("KinemaMedia", isDirectory: true)
        #else
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        #endif
    }

    @discardableResult
    public static func ensureBuiltInDirectory() -> URL {
        let url = builtInMediaURL
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Legacy no-op — never write placeholder files into Documents.
    /// Doing so while Finder/USB file sharing is active can drop the device connection.
    public static func ensurePlaceholder() {}

    /// One-time cleanup of the old empty placeholder file (safe at first prepare only).
    public static func removeLegacyPlaceholderIfNeeded() {
        let placeholder = builtInMediaURL.appendingPathComponent(placeholderFileName)
        guard FileManager.default.fileExists(atPath: placeholder.path) else { return }
        try? FileManager.default.removeItem(at: placeholder)
    }

    public static func cleanTrashIfNeeded() {
        let trash = builtInMediaURL.appendingPathComponent(trashFolderName, isDirectory: true)
        guard FileManager.default.fileExists(atPath: trash.path) else { return }
        try? FileManager.default.removeItem(at: trash)
    }

    public static func isIgnoredName(_ name: String) -> Bool {
        ignoredNames.contains(name) || name.hasPrefix(".")
    }

    public static func isInsideBuiltInLibrary(_ url: URL) -> Bool {
        let filePath = url.standardizedFileURL.path
        let rootPath = builtInMediaURL.standardizedFileURL.path
        return filePath == rootPath || filePath.hasPrefix(rootPath + "/")
    }

    /// True when a media file looks finished enough to browse / thumbnail / play.
    /// Incomplete Finder/AFC copies are often 0 bytes or use temp suffixes — touching them
    /// (especially via NSFileCoordinator) can interrupt USB file sharing.
    public static func isStableMediaFile(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        guard !isIgnoredName(name) else { return false }

        let lower = name.lowercased()
        if incompleteNameSuffixes.contains(where: { lower.hasSuffix($0) }) {
            return false
        }

        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isDirectoryKey]),
              values.isDirectory != true,
              values.isRegularFile == true,
              let size = values.fileSize else {
            return false
        }

        // Growing USB copies and empty stubs — wait until there is real content.
        return size >= 4_096
    }

    public static func shouldBrowse(_ url: URL) -> Bool {
        if isIgnoredName(url.lastPathComponent) { return false }
        return MediaFileTypes.isBrowsable(url)
    }

    /// Cover-art-only folder cleanup (VLC-style) after deleting a media file.
    public static func deleteMediaAndCleanupParent(at url: URL, builtInRoot: URL) throws {
        let parent = url.deletingLastPathComponent().standardizedFileURL
        let builtIn = builtInRoot.standardizedFileURL
        try FileManager.default.removeItem(at: url)

        // Never delete the built-in root itself.
        guard parent != builtIn else { return }

        try deleteFolderIfOnlyCoverArt(at: parent, mediaBaseName: url.deletingPathExtension().lastPathComponent)
    }

    public static func deleteFolderIfOnlyCoverArt(at path: URL, mediaBaseName: String) throws {
        let builtIn = builtInMediaURL.standardizedFileURL
        guard path.standardizedFileURL != builtIn else { return }

        let content = try FileManager.default.contentsOfDirectory(
            at: path,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        guard content.isEmpty || isCoverArtOnly(content: content, mediaBaseName: mediaBaseName) else { return }

        try FileManager.default.removeItem(at: path)

        let parent = path.deletingLastPathComponent()
        if parent.lastPathComponent == mediaBaseName,
           parent.standardizedFileURL != builtIn,
           let parentContent = try? FileManager.default.contentsOfDirectory(
               at: parent,
               includingPropertiesForKeys: nil,
               options: [.skipsHiddenFiles]
           ),
           parentContent.isEmpty {
            try FileManager.default.removeItem(at: parent)
        }
    }

    private static func isCoverArtOnly(content: [URL], mediaBaseName: String) -> Bool {
        var coverNames: Set<String> = [
            "album", "albumart", "albumartsmall", "back", "cover",
            ".folder", "folder", "front", "thumb"
        ]
        if !mediaBaseName.isEmpty {
            coverNames.insert(mediaBaseName.lowercased())
        }
        let coverExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "bmp", "webp"]
        for file in content {
            let base = file.deletingPathExtension().lastPathComponent.lowercased()
            let ext = file.pathExtension.lowercased()
            if !coverNames.contains(base) || !coverExtensions.contains(ext) {
                return false
            }
        }
        return true
    }
}
