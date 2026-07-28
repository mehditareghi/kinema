import AVFoundation
import Foundation
import KinemaCore
import KinemaMedia
import GCDWebServer
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Local HTTP + Bonjour Wi‑Fi Sharing server (GCDWebServer-backed).
@MainActor
@Observable
public final class WiFiSharingServer {
    public static let shared = WiFiSharingServer()

    public private(set) var isRunning = false
    public private(set) var serverURLString: String?
    public private(set) var bonjourName = "Kinema"
    public private(set) var lastError: String?
    private var preferIPv6Addresses = true

    private var webServer: GCDWebServer?
    private var thumbnailCache: [String: Data] = [:]
    #if os(iOS)
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    #endif

    private init() {}

    public var uploadDirectory: URL {
        LibraryMediaPaths.ensureBuiltInDirectory()
    }

    @discardableResult
    public func start(passcode: String?, preferIPv6: Bool = true) -> Bool {
        stop()
        lastError = nil
        preferIPv6Addresses = preferIPv6
        thumbnailCache.removeAll(keepingCapacity: true)

        let server = GCDWebServer()
        webServer = server
        let trimmedPasscode = passcode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        server.addDefaultHandler(forMethod: "GET", request: GCDWebServerRequest.self) { [weak self] request in
            guard let self else { return GCDWebServerResponse(statusCode: 500) }
            return self.handleGET(request)
        }

        server.addHandler(
            forMethod: "POST",
            path: "/upload",
            request: GCDWebServerMultiPartFormRequest.self
        ) { [weak self] request in
            guard let self, let form = request as? GCDWebServerMultiPartFormRequest else {
                return GCDWebServerResponse(statusCode: 500)
            }
            return self.handleUpload(form, query: request.url.query)
        }

        var options: [String: Any] = [
            GCDWebServerOption_Port: 8080,
            GCDWebServerOption_BonjourName: bonjourName,
            GCDWebServerOption_ServerName: "Kinema",
            GCDWebServerOption_BindToLocalhost: false
        ]
        #if os(iOS)
        options[GCDWebServerOption_AutomaticallySuspendInBackground] = false
        #endif

        if !trimmedPasscode.isEmpty {
            options[GCDWebServerOption_AuthenticationMethod] = GCDWebServerAuthenticationMethod_Basic
            options[GCDWebServerOption_AuthenticationRealm] = "Kinema Wi-Fi Sharing"
            options[GCDWebServerOption_AuthenticationAccounts] = ["kinema": trimmedPasscode]
        }

        do {
            try server.start(options: options)
            isRunning = true
            serverURLString = primaryURLString(from: server)
            beginBackgroundTaskIfNeeded()
            EventBus.shared.emit(.libraryChanged)
            return true
        } catch {
            lastError = error.localizedDescription
            isRunning = false
            serverURLString = nil
            webServer = nil
            return false
        }
    }

    public func stop() {
        webServer?.stop()
        webServer = nil
        isRunning = false
        serverURLString = nil
        thumbnailCache.removeAll()
        endBackgroundTaskIfNeeded()
    }

    public func refreshAddress() {
        guard let server = webServer, isRunning else { return }
        serverURLString = primaryURLString(from: server)
    }

    // MARK: - GET

    private func handleGET(_ request: GCDWebServerRequest) -> GCDWebServerResponse {
        let path = request.path
        let query = Self.queryItems(from: request.url)

        if path == "/" || path.isEmpty {
            return GCDWebServerDataResponse(html: WiFiSharingWebUI.indexPage())
                ?? GCDWebServerResponse(statusCode: 500)
        }

        if path == "/logo.png" {
            if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
               let data = try? Data(contentsOf: url) {
                return GCDWebServerDataResponse(data: data, contentType: "image/png")
            }
            return GCDWebServerResponse(statusCode: 404)
        }

        if path == "/api/library" {
            let folder = query["path"] ?? ""
            let payload = libraryPayload(relativePath: folder)
            return jsonResponse(payload, status: 200)
        }

        if path.hasPrefix("/thumb/") {
            return thumbnailResponse(relativePath: String(path.dropFirst("/thumb/".count)))
        }

        if path.hasPrefix("/download/") {
            guard let fileURL = resolvedFile(relativePath: String(path.dropFirst("/download/".count))),
                  !isDirectory(fileURL) else {
                return GCDWebServerResponse(statusCode: 404)
            }
            return GCDWebServerFileResponse(file: fileURL.path, isAttachment: true)
                ?? GCDWebServerResponse(statusCode: 404)
        }

        if path == "/zip" {
            return zipResponse(query: query)
        }

        return GCDWebServerResponse(statusCode: 404)
    }

    // MARK: - Upload

    private func handleUpload(_ request: GCDWebServerMultiPartFormRequest, query: String?) -> GCDWebServerResponse {
        let wantsJSON = query?.contains("json=1") == true
        let files = request.files
        guard !files.isEmpty else {
            if wantsJSON { return jsonResponse(["ok": false, "error": "No files received."], status: 400) }
            return GCDWebServerDataResponse(
                html: WiFiSharingWebUI.resultPage(message: "No files received.", success: false)
            ) ?? GCDWebServerResponse(statusCode: 400)
        }

        var saved: [String] = []
        for part in files {
            let rawName = part.fileName.isEmpty ? "upload-\(UUID().uuidString)" : part.fileName
            let relative = sanitizeRelativeUploadPath(rawName)
            guard !relative.isEmpty else { continue }
            let destination = uniqueDestination(forRelativePath: relative)
            do {
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(atPath: part.temporaryPath, toPath: destination.path)
                saved.append(relative)
                thumbnailCache.removeValue(forKey: destination.path)
            } catch {
                if wantsJSON {
                    return jsonResponse(["ok": false, "error": error.localizedDescription], status: 500)
                }
                return GCDWebServerDataResponse(
                    html: WiFiSharingWebUI.resultPage(
                        message: "Upload failed: \(error.localizedDescription)",
                        success: false
                    )
                ) ?? GCDWebServerResponse(statusCode: 500)
            }
        }

        Task { @MainActor in
            EventBus.shared.emit(.libraryChanged)
            #if os(iOS) || os(macOS)
            LibrarySpotlightIndexer.shared.indexBuiltInLibrary()
            #endif
        }

        if wantsJSON {
            return jsonResponse(["ok": !saved.isEmpty, "files": saved], status: 200)
        }
        let message = saved.isEmpty ? "Nothing saved." : "Uploaded: \(saved.joined(separator: ", "))"
        return GCDWebServerDataResponse(
            html: WiFiSharingWebUI.resultPage(message: message, success: !saved.isEmpty)
        ) ?? GCDWebServerResponse(statusCode: 200)
    }

    private func sanitizeRelativeUploadPath(_ raw: String) -> String {
        let decoded = raw.removingPercentEncoding ?? raw
        let parts = decoded
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty && $0 != "." && $0 != ".." && !LibraryMediaPaths.isIgnoredName($0) }
        guard let last = parts.last, !LibraryMediaPaths.isIgnoredName(last) else { return "" }
        return parts.joined(separator: "/")
    }

    private func uniqueDestination(forRelativePath relative: String) -> URL {
        var destination = resolvedPath(relative)
        if !FileManager.default.fileExists(atPath: destination.path) {
            return destination
        }
        let parent = destination.deletingLastPathComponent()
        let base = destination.deletingPathExtension().lastPathComponent
        let ext = destination.pathExtension
        var index = 1
        repeat {
            let name = ext.isEmpty ? "\(base)-\(index)" : "\(base)-\(index).\(ext)"
            destination = parent.appendingPathComponent(name)
            index += 1
        } while FileManager.default.fileExists(atPath: destination.path)
        return destination
    }

    // MARK: - Library API

    private func libraryPayload(relativePath: String) -> [String: Any] {
        let directory = resolvedPath(relativePath)
        guard isDirectory(directory) || relativePath.isEmpty else {
            return ["folders": [], "spotlights": [], "files": [], "path": relativePath]
        }
        let root = relativePath.isEmpty ? uploadDirectory : directory

        let urls = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var folders: [[String: Any]] = []
        var mediaURLs: [URL] = []

        for url in urls {
            if LibraryMediaPaths.isIgnoredName(url.lastPathComponent) { continue }
            if isDirectory(url) {
                let childCount = ((try? FileManager.default.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )) ?? []).filter { !LibraryMediaPaths.isIgnoredName($0.lastPathComponent) }.count
                folders.append([
                    "name": url.lastPathComponent,
                    "count": childCount
                ])
            } else if MediaFileTypes.isMediaFile(url), fileSize(url) > 0 {
                mediaURLs.append(url)
            }
        }

        let organized = MediaSeriesOrganizer.organize(videoURLs: mediaURLs, virtualPath: [])
        let spotlightVideoSet = Set(organized.virtualFolders.flatMap(\.videoURLs))

        let spotlights: [[String: Any]] = organized.virtualFolders.map { folder in
            let files = folder.videoURLs.compactMap { fileDict(for: $0) }
            return [
                "id": folder.id,
                "title": folder.title,
                "files": files
            ]
        }

        let files: [[String: Any]] = organized.videoURLs.compactMap { url in
            guard !spotlightVideoSet.contains(url) else { return nil }
            return fileDict(for: url)
        }

        folders.sort {
            ($0["name"] as? String ?? "").localizedStandardCompare($1["name"] as? String ?? "") == .orderedAscending
        }

        return [
            "path": relativePath,
            "folders": folders,
            "spotlights": spotlights,
            "files": files
        ]
    }

    private func fileDict(for url: URL) -> [String: Any]? {
        guard let relative = relativePath(for: url) else { return nil }
        let ext = url.pathExtension.lowercased()
        let audio: Set<String> = ["mp3", "m4a", "aac", "flac", "wav", "opus"]
        return [
            "path": relative,
            "name": url.deletingPathExtension().lastPathComponent,
            "ext": url.pathExtension.uppercased(),
            "size": fileSize(url),
            "kind": audio.contains(ext) ? "audio" : "video"
        ]
    }

    // MARK: - Paths

    /// Resolve a relative library path without treating `/` as a single path component.
    private func resolvedPath(_ relative: String) -> URL {
        let trimmed = relative.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else { return uploadDirectory.standardizedFileURL }
        if #available(iOS 16.0, macOS 13.0, tvOS 16.0, *) {
            return uploadDirectory.appending(path: trimmed).standardizedFileURL
        }
        return URL(fileURLWithPath: trimmed, relativeTo: uploadDirectory).standardizedFileURL
    }

    private func resolvedFile(relativePath: String) -> URL? {
        let decoded = relativePath.removingPercentEncoding ?? relativePath
        let fileURL = resolvedPath(decoded)
        let root = uploadDirectory.standardizedFileURL.path
        guard fileURL.path.hasPrefix(root + "/") || fileURL.path == root,
              FileManager.default.fileExists(atPath: fileURL.path),
              !LibraryMediaPaths.isIgnoredName(fileURL.lastPathComponent) else {
            return nil
        }
        return fileURL
    }

    private func relativePath(for url: URL) -> String? {
        let root = uploadDirectory.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(root) else { return nil }
        return String(path.dropFirst(root.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    private func fileSize(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    // MARK: - Zip

    private func zipResponse(query: [String: String]) -> GCDWebServerResponse {
        var pairs: [(name: String, data: Data)] = []

        if let folderRel = query["path"], !folderRel.isEmpty,
           let folderURL = resolvedFile(relativePath: folderRel),
           isDirectory(folderURL) {
            let rootName = folderURL.lastPathComponent
            let media = WatchProgressStore.mediaURLs(under: folderURL)
            for file in media {
                guard let data = try? Data(contentsOf: file) else { continue }
                let rel = relativePath(for: file) ?? file.lastPathComponent
                let nameInZip = rel.hasPrefix(folderRel)
                    ? rootName + "/" + String(rel.dropFirst(folderRel.count).drop(while: { $0 == "/" }))
                    : rootName + "/" + file.lastPathComponent
                pairs.append((nameInZip, data))
            }
        } else if let joined = query["files"], !joined.isEmpty {
            let paths = joined.components(separatedBy: "|").filter { !$0.isEmpty }
            for path in paths {
                guard let fileURL = resolvedFile(relativePath: path),
                      !isDirectory(fileURL),
                      let data = try? Data(contentsOf: fileURL) else { continue }
                pairs.append((fileURL.lastPathComponent, data))
            }
        }

        guard !pairs.isEmpty else {
            return GCDWebServerResponse(statusCode: 404)
        }

        let zip = SimpleZipWriter.zipData(from: pairs)
        let response = GCDWebServerDataResponse(data: zip, contentType: "application/zip")
        response.setValue("attachment; filename=\"kinema-folder.zip\"", forAdditionalHeader: "Content-Disposition")
        return response
    }

    // MARK: - Thumbnails

    private func thumbnailResponse(relativePath: String) -> GCDWebServerResponse {
        guard let fileURL = resolvedFile(relativePath: relativePath), !isDirectory(fileURL) else {
            return GCDWebServerResponse(statusCode: 404)
        }
        if let cached = thumbnailCache[fileURL.path] {
            return GCDWebServerDataResponse(data: cached, contentType: "image/jpeg")
        }
        guard let jpeg = generateThumbnailJPEG(for: fileURL) else {
            return GCDWebServerResponse(statusCode: 404)
        }
        thumbnailCache[fileURL.path] = jpeg
        return GCDWebServerDataResponse(data: jpeg, contentType: "image/jpeg")
    }

    private func generateThumbnailJPEG(for url: URL) -> Data? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 270)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 3, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 3, preferredTimescale: 600)

        for seconds in [1.0, 3.0, 8.0, 0.0] {
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
                return jpegData(from: cgImage)
            }
        }
        return nil
    }

    private func jpegData(from image: CGImage) -> Data? {
        #if canImport(UIKit)
        return UIImage(cgImage: image).jpegData(compressionQuality: 0.74)
        #elseif canImport(AppKit)
        let rep = NSBitmapImageRep(cgImage: image)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.74])
        #else
        return nil
        #endif
    }

    // MARK: - Helpers

    private func jsonResponse(_ object: [String: Any], status: Int) -> GCDWebServerResponse {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else {
            return GCDWebServerResponse(statusCode: 500)
        }
        let response = GCDWebServerDataResponse(data: data, contentType: "application/json; charset=utf-8")
        response.statusCode = status
        return response
    }

    private static func queryItems(from url: URL) -> [String: String] {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            return [:]
        }
        var result: [String: String] = [:]
        for item in items {
            result[item.name] = item.value ?? ""
        }
        return result
    }

    private func primaryURLString(from server: GCDWebServer) -> String? {
        if let url = server.serverURL?.absoluteString { return url }
        if let bonjour = server.bonjourServerURL?.absoluteString { return bonjour }
        if let host = Self.firstLANAddress(preferIPv6: preferIPv6Addresses) {
            return "http://\(host):\(server.port)"
        }
        return nil
    }

    private static func firstLANAddress(preferIPv6: Bool) -> String? {
        var ipv4: [String] = []
        var ipv6: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(first) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let interface = ptr {
            defer { ptr = interface.pointee.ifa_next }
            let flags = Int32(interface.pointee.ifa_flags)
            guard flags & (IFF_UP | IFF_RUNNING) == (IFF_UP | IFF_RUNNING) else { continue }
            guard flags & IFF_LOOPBACK == 0 else { continue }
            guard let addr = interface.pointee.ifa_addr else { continue }
            let family = Int32(addr.pointee.sa_family)
            guard family == AF_INET || family == AF_INET6 else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(
                addr,
                socklen_t(addr.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            ) == 0 else { continue }
            let host = String(cString: hostname)
            if host.hasPrefix("fe80") { continue }
            if host.contains(":") { ipv6.append(host) } else { ipv4.append(host) }
        }
        return preferIPv6 ? (ipv6.first ?? ipv4.first) : (ipv4.first ?? ipv6.first)
    }

    private func beginBackgroundTaskIfNeeded() {
        #if os(iOS)
        endBackgroundTaskIfNeeded()
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "KinemaWiFiSharing") { [weak self] in
            Task { @MainActor in self?.endBackgroundTaskIfNeeded() }
        }
        #endif
    }

    private func endBackgroundTaskIfNeeded() {
        #if os(iOS)
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
        #endif
    }
}
