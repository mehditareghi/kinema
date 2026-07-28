import Foundation

public enum MediaFileTypes {
    public static let extensions: Set<String> = [
        "mp4", "mkv", "mov", "avi", "m4v", "webm", "mpg", "mpeg", "wmv", "flv",
        "mp3", "m4a", "aac", "flac", "wav", "opus", "ts", "m2ts"
    ]

    public static func isMediaFile(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }

    public static func isBrowsable(_ url: URL) -> Bool {
        if LibraryMediaPaths.isIgnoredName(url.lastPathComponent) { return false }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return false }
        if isDirectory.boolValue { return true }
        guard isMediaFile(url) else { return false }
        // Hide in-progress Finder/USB copies so we don't open or thumbnail them.
        return LibraryMediaPaths.isStableMediaFile(url)
    }
}
