import Foundation

public actor PlaybillArtworkCache {
    public static let shared = PlaybillArtworkCache()

    private let maximumBytes: Int64 = 150 * 1_024 * 1_024

    public func data(for url: URL) async throws -> Data {
        let fileURL = cacheFileURL(for: url)
        if let data = try? Data(contentsOf: fileURL) {
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: fileURL.path)
            return data
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        trimIfNeeded()
        return data
    }

    private func cacheFileURL(for url: URL) -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let size = url.deletingLastPathComponent().lastPathComponent
        let name = url.lastPathComponent.isEmpty ? UUID().uuidString : url.lastPathComponent
        return base
            .appendingPathComponent("Kinema/PlaybillArtwork", isDirectory: true)
            .appendingPathComponent(size, isDirectory: true)
            .appendingPathComponent(name)
    }

    private func trimIfNeeded() {
        let base = (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("Kinema/PlaybillArtwork", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: base,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        var files: [(URL, Int64, Date)] = []
        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = values.fileSize else { continue }
            let bytes = Int64(size)
            total += bytes
            files.append((url, bytes, values.contentModificationDate ?? .distantPast))
        }
        guard total > maximumBytes else { return }
        for file in files.sorted(by: { $0.2 < $1.2 }) {
            try? FileManager.default.removeItem(at: file.0)
            total -= file.1
            if total <= maximumBytes { break }
        }
    }
}
