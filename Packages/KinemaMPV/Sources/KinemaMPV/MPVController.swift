import Foundation
import KinemaCore
import LibMPV
#if os(iOS) || os(tvOS)
import UIKit
#endif

public protocol MPVRenderSurface: AnyObject {
    func attach(to controller: MPVController)
    func detach()
    func setNeedsDisplay()
}

/// Thread-safe mpv controller — only class that talks to libmpv C APIs.
public final class MPVController: @unchecked Sendable {
    private var handle: OpaquePointer?
    private let eventQueue = DispatchQueue(label: "io.kinema.mpv.events", qos: .userInitiated)
    private let commandQueue = DispatchQueue(label: "io.kinema.mpv.commands", qos: .userInitiated)
    private var isRunning = false
    private weak var renderSurface: MPVRenderSurface?
    private var isInitialized = false
    private var isShuttingDown = false
    #if os(iOS) || os(tvOS)
    private var readyContinuations: [CheckedContinuation<Void, Error>] = []

    private static let wakeupCallback: @convention(c) (UnsafeMutableRawPointer?) -> Void = { context in
        guard let context else { return }
        let controller = Unmanaged<MPVController>.fromOpaque(context).takeUnretainedValue()
        controller.readEvents()
    }
    #endif

    public var onEvent: (@Sendable (MPVClientEvent) -> Void)?
    public var onReady: (@Sendable () -> Void)?

    public var isReady: Bool { isInitialized }

    public init() {}

    #if os(iOS) || os(tvOS)
    private static var mpvLogPath: String {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return directory.appendingPathComponent("kinema-mpv.log").path
    }
    #endif

    public func initialize(options: [String: String] = [:]) throws {
        guard handle == nil else { return }

        guard let mpv = mpv_create() else {
            throw MPVError.creationFailed
        }
        handle = mpv

        do {
            try configureEngine(options: options)
            try completeInitialization()
        } catch {
            // Leave a clean slate so the next open can retry.
            mpv_terminate_destroy(mpv)
            handle = nil
            isInitialized = false
            isRunning = false
            throw error
        }
    }

    private func configureEngine(options: [String: String]) throws {
        #if os(macOS)
        try setOption(name: MPVOption.vo.rawValue, value: "libmpv")
        if options["ao"] == nil {
            try setOption(name: "ao", value: "coreaudio")
        }
        try setOption(name: "video-timing-offset", value: "0")
        try setOption(name: "audio-buffer", value: "0.1")
        #elseif os(iOS) || os(tvOS)
        try setOption(name: MPVOption.vo.rawValue, value: "libmpv")
        if options["ao"] == nil {
            try setOption(name: "ao", value: "audiounit")
        }
        try setOption(name: "keepaspect", value: "yes")
        try setOption(name: "keepaspect-window", value: "yes")
        try setOption(name: "video-unscaled", value: "no")
        try setOption(name: "demuxer-lavf-analyzeduration", value: "1")
        try setOption(name: "cache-pause-initial", value: "yes")
        #endif

        try setOption(name: "volume-max", value: "200")

        try setOption(name: MPVOption.keepOpen.rawValue, value: "yes")
        try setOption(name: MPVOption.hrSeek.rawValue, value: "yes")
        try setOption(name: MPVOption.inputDefaultBindings.rawValue, value: "no")
        try setOption(name: MPVOption.inputVideol.rawValue, value: "no")
        try setOption(name: MPVOption.subAuto.rawValue, value: "fuzzy")
        try setOption(name: "sub-use-margins", value: "yes")

        #if os(iOS) || os(tvOS)
        let logPath = Self.mpvLogPath
        try? setOption(name: "log-file", value: logPath)
        if let handle {
            mpv_request_log_messages(handle, "info")
        }
        NSLog("Kinema: mpv log at %@", logPath)
        #endif

        for (key, value) in options {
            #if os(iOS) || os(tvOS)
            if key == MPVOption.vo.rawValue { continue }
            if key == MPVOption.hwdec.rawValue { continue }
            #endif
            // Preference / subtitle options must not block player startup if unsupported
            // by the bundled libmpv (e.g. secondary-sub-align-x on older builds).
            do {
                try setOption(name: key, value: value)
            } catch {
                NSLog("Kinema: skipping unsupported mpv option %@=%@ (%@)", key, value, "\(error)")
            }
        }

        #if os(iOS) || os(tvOS)
        let hwdec = options[MPVOption.hwdec.rawValue]
        if hwdec == "no" {
            try setOption(name: "hwdec", value: "no")
        } else {
            // OpenGL ES has no videotoolbox-gl interop in this MPVKit build.
            try setOption(name: "hwdec", value: "videotoolbox-copy")
        }
        #endif
    }

    #if os(iOS) || os(tvOS)
    func readEvents() {
        eventQueue.async { [weak self] in
            guard let self, let handle = self.handle else { return }
            while self.isRunning {
                guard let event = mpv_wait_event(handle, 0) else { break }
                if event.pointee.event_id == MPV_EVENT_NONE {
                    break
                }
                if event.pointee.event_id == MPV_EVENT_SHUTDOWN {
                    break
                }
                let clientEvent = self.mapEvent(event)
                if let clientEvent {
                    self.onEvent?(clientEvent)
                }
            }
        }
    }

    public func waitUntilReady(timeout seconds: TimeInterval = 10) async throws {
        if isInitialized { return }
        try await withCheckedThrowingContinuation { continuation in
            readyContinuations.append(continuation)
            _ = Task { [weak self] in
                do {
                    try await Task.sleep(for: .seconds(seconds))
                } catch {
                    return
                }
                guard let self, !self.isInitialized else { return }
                self.resumeReadyWaiters(with: MPVError.notInitialized)
            }
        }
    }

    private func resumeReadyWaiters(with error: Error? = nil) {
        let waiters = readyContinuations
        readyContinuations.removeAll()
        if let error {
            waiters.forEach { $0.resume(throwing: error) }
        } else {
            waiters.forEach { $0.resume() }
        }
    }

    #endif

    private func completeInitialization() throws {
        guard let handle else { throw MPVError.notInitialized }

        let status = mpv_initialize(handle)
        guard status >= 0 else {
            throw MPVError.initializationFailed(status)
        }

        observe(properties: [
            MPVProperty.pause.rawValue,
            MPVProperty.duration.rawValue,
            MPVProperty.volume.rawValue,
            MPVProperty.speed.rawValue,
            MPVProperty.mediaTitle.rawValue,
            MPVProperty.trackList.rawValue,
            MPVProperty.chapterList.rawValue,
            MPVProperty.abLoopA.rawValue,
            MPVProperty.abLoopB.rawValue,
            MPVProperty.sid.rawValue,
            MPVProperty.secondarySid.rawValue,
            MPVProperty.subDelay.rawValue,
            MPVProperty.secondarySubDelay.rawValue,
            MPVProperty.audioDelay.rawValue,
            MPVProperty.mute.rawValue,
            MPVProperty.eofReached.rawValue
        ])

        #if os(iOS) || os(tvOS)
        mpv_set_wakeup_callback(handle, Self.wakeupCallback, Unmanaged.passUnretained(self).toOpaque())
        isRunning = true
        #else
        startEventLoop()
        #endif

        isInitialized = true
        onReady?()
        #if os(iOS) || os(tvOS)
        resumeReadyWaiters()
        #endif
    }

    public func attachRenderSurface(_ surface: MPVRenderSurface) {
        renderSurface = surface
        surface.attach(to: self)
    }

    public func loadFile(_ url: URL) {
        commandQueue.async { [weak self] in
            guard let self, self.isInitialized, self.handle != nil else {
                NSLog("Kinema: loadFile skipped — mpv not initialized (%@)", url.lastPathComponent)
                return
            }
            let path: String
            if url.isFileURL {
                path = url.path
            } else {
                path = url.absoluteString
            }
            NSLog("Kinema: loadfile %@", path)
            self.command(["loadfile", path, "replace"])
        }
    }

    public func play() { setProperty(MPVProperty.pause.rawValue, flag: 0) }
    public func pause() { setProperty(MPVProperty.pause.rawValue, flag: 1) }

    public func togglePause() {
        commandQueue.async { [weak self] in
            self?.command(["cycle", "pause"])
        }
    }

    public func seek(to seconds: TimeInterval, relative: Bool = false) {
        commandQueue.async { [weak self] in
            guard let self else { return }
            if relative {
                self.command(["seek", "\(seconds)", "relative"])
            } else {
                self.command(["seek", "\(seconds)", "absolute"])
            }
        }
    }

    public func stop() {
        commandQueue.async { [weak self] in
            self?.command([MPVCommand.stop.rawValue])
        }
    }

    public func setVolume(_ volume: Double) {
        setProperty(MPVProperty.volume.rawValue, double: volume)
    }

    public func setSpeed(_ speed: Double) {
        setProperty(MPVProperty.speed.rawValue, double: speed)
    }

    public func setMute(_ muted: Bool) {
        setProperty(MPVProperty.mute.rawValue, flag: muted ? 1 : 0)
    }

    public func isMuted() -> Bool {
        guard isInitialized, !isShuttingDown else { return false }
        return commandQueue.sync {
            guard isInitialized, !isShuttingDown, handle != nil else { return false }
            return (getFlag(MPVProperty.mute.rawValue) ?? 0) != 0
        }
    }

    public func setAudioFilters(_ filterGraph: String?) {
        let value = (filterGraph?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? ""
        setStringOption(MPVProperty.af.rawValue, value.isEmpty ? "" : value)
    }

    public func clearAudioFilters() {
        setAudioFilters(nil)
    }

    public func setReplayGain(_ mode: String) {
        setStringOption(MPVProperty.replaygain.rawValue, mode)
    }

    public func setAudioDevice(_ deviceID: String) {
        let trimmed = deviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        setStringOption(MPVProperty.audioDevice.rawValue, trimmed.isEmpty ? "auto" : trimmed)
    }

    public func cycleAudio() {
        commandQueue.async { [weak self] in
            self?.command(["cycle", "audio"])
        }
    }

    public struct AudioDevice: Sendable, Identifiable, Hashable {
        public let id: String
        public let description: String
    }

    public func audioDeviceList() -> [AudioDevice] {
        guard isInitialized, !isShuttingDown else { return [] }
        return commandQueue.sync {
            guard isInitialized, !isShuttingDown, let handle else { return [] }
            return MPVAudioDevices.parse(from: handle)
        }
    }

    public func setVideoEnabled(_ enabled: Bool) {
        commandQueue.async { [weak self] in
            self?.command(["set", "vid", enabled ? "auto" : "no"])
        }
    }

    public func addSubtitle(url: URL) {
        commandQueue.async { [weak self] in
            self?.command([MPVCommand.subAdd.rawValue, url.path])
        }
    }

    public func removeSubtitle(id: Int) {
        commandQueue.async { [weak self] in
            self?.command([MPVCommand.subRemove.rawValue, "\(id)"])
        }
    }

    public func disableSubtitles() {
        commandQueue.async { [weak self] in
            self?.command(["set", MPVProperty.sid.rawValue, "no"])
        }
    }

    public func disableSecondarySubtitles() {
        commandQueue.async { [weak self] in
            self?.command(["set", MPVProperty.secondarySid.rawValue, "no"])
        }
    }

    public func selectSecondarySubtitleTrack(id: Int) {
        commandQueue.async { [weak self] in
            self?.command(["set", MPVProperty.secondarySid.rawValue, "\(id)"])
        }
    }

    /// Show or hide mpv's secondary subtitle draw.
    public func setSecondarySubtitleVisible(_ visible: Bool) {
        setStringOption(MPVProperty.secondarySubVisibility.rawValue, visible ? "yes" : "no")
    }

    public func secondarySubtitleText() -> String {
        guard isInitialized, !isShuttingDown else { return "" }
        return commandQueue.sync {
            guard isInitialized, !isShuttingDown else { return "" }
            return getString(MPVProperty.secondarySubText.rawValue)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
    }

    public func setSubtitleFontSize(_ size: Int) {
        setStringOption(MPVOption.subFontSize.rawValue, "\(size)")
    }

    public func setSubtitleFont(_ fontName: String) {
        guard !fontName.isEmpty else { return }
        setStringOption(MPVOption.subFont.rawValue, fontName)
    }

    public func setSubtitleColor(_ hex: String) {
        setStringOption(MPVOption.subColor.rawValue, hex)
    }

    public func setSubtitleCodepage(_ codepage: String) {
        setStringOption(MPVOption.subCodepage.rawValue, codepage)
    }

    public func setSubtitleBorderSize(_ size: Double) {
        setStringOption(MPVOption.subBorderSize.rawValue, "\(size)")
    }

    public func setSubtitleBorderColor(_ hex: String) {
        setStringOption(MPVOption.subBorderColor.rawValue, hex)
    }

    public func setSubtitleShadowOffset(_ offset: Double) {
        setStringOption(MPVOption.subShadowOffset.rawValue, "\(offset)")
    }

    public func setSubtitleShadowColor(_ hex: String) {
        setStringOption(MPVOption.subShadowColor.rawValue, hex)
    }

    public func setSubtitleBackColor(_ hex: String) {
        setStringOption(MPVOption.subBackColor.rawValue, hex)
    }

    public func setSubtitleBold(_ bold: Bool) {
        setStringOption(MPVOption.subBold.rawValue, bold ? "yes" : "no")
    }

    public func setSubtitleItalic(_ italic: Bool) {
        setStringOption(MPVOption.subItalic.rawValue, italic ? "yes" : "no")
    }

    public func setSubtitlePos(_ pos: Int) {
        setStringOption(MPVOption.subPos.rawValue, "\(pos)")
    }

    public func setSecondarySubtitlePos(_ pos: Int) {
        setStringOption(MPVOption.secondarySubPos.rawValue, "\(pos)")
    }

    public func setSubtitleAlignX(_ align: SubtitleHorizontalAlign) {
        setStringOption(MPVOption.subAlignX.rawValue, align.rawValue)
    }

    public func setSubtitleAlignY(_ align: SubtitleVerticalAlign) {
        setStringOption(MPVOption.subAlignY.rawValue, align.rawValue)
    }

    public func setSecondarySubtitleAlignX(_ align: SubtitleHorizontalAlign) {
        setStringOption(MPVOption.secondarySubAlignX.rawValue, align.rawValue)
    }

    public func setSubtitlePlacement(_ anchor: SubtitlePlacementAnchor) {
        setSubtitleAlignX(anchor.alignX)
        setSubtitleAlignY(anchor.alignY)
        setSubtitlePos(anchor.verticalPos)
    }

    public func setSecondarySubtitlePlacement(_ anchor: SubtitlePlacementAnchor) {
        setSecondarySubtitleAlignX(anchor.alignX)
        setSecondarySubtitlePos(anchor.verticalPos)
        // Independent L/R for secondary: ASS Alignment via force-style (shared string),
        // applied only when secondary-sub-ass-override=force.
        setStringOption(MPVOption.secondarySubASSOverride.rawValue, "force")
    }

    public func setSecondarySubtitleASSOverride(_ mode: String) {
        setStringOption(MPVOption.secondarySubASSOverride.rawValue, mode)
    }

    public func setSubtitleASSOverride(_ mode: SubtitleASSOverrideMode) {
        // Avoid `force` on primary so secondary Alignment in force-style doesn't move primary.
        let effective = mode == .force ? SubtitleASSOverrideMode.scale : mode
        setStringOption(MPVOption.subASSOverride.rawValue, effective.rawValue)
    }

    public func setSubtitleASSForceStyle(_ style: String) {
        setStringOption(MPVOption.subASSForceStyle.rawValue, style)
    }

    public func setSubtitleDelay(_ delay: Double) {
        setProperty(MPVProperty.subDelay.rawValue, double: delay)
    }

    public func setSecondarySubtitleDelay(_ delay: Double) {
        setProperty(MPVProperty.secondarySubDelay.rawValue, double: delay)
    }

    public func setAudioDelay(_ delay: Double) {
        setProperty(MPVProperty.audioDelay.rawValue, double: delay)
    }

    public func setSubtitleSpeed(_ speed: Double) {
        setStringOption(MPVOption.subSpeed.rawValue, "\(speed)")
    }

    public func subtitleDelay() -> Double {
        guard isInitialized, !isShuttingDown else { return 0 }
        return commandQueue.sync {
            guard isInitialized, !isShuttingDown, handle != nil else { return 0 }
            return getDouble(MPVProperty.subDelay.rawValue) ?? 0
        }
    }

    public func secondarySubtitleDelay() -> Double {
        guard isInitialized, !isShuttingDown else { return 0 }
        return commandQueue.sync {
            guard isInitialized, !isShuttingDown, handle != nil else { return 0 }
            return getDouble(MPVProperty.secondarySubDelay.rawValue) ?? 0
        }
    }

    public func audioDelay() -> Double {
        guard isInitialized, !isShuttingDown else { return 0 }
        return commandQueue.sync {
            guard isInitialized, !isShuttingDown, handle != nil else { return 0 }
            return getDouble(MPVProperty.audioDelay.rawValue) ?? 0
        }
    }

    public func subtitleSpeed() -> Double {
        guard isInitialized, !isShuttingDown else { return 1 }
        return commandQueue.sync {
            guard isInitialized, !isShuttingDown, handle != nil else { return 1 }
            if let value = getDouble(MPVOption.subSpeed.rawValue) { return value }
            if let string = getString(MPVOption.subSpeed.rawValue), let value = Double(string) {
                return value
            }
            return 1
        }
    }

    public func cycleSubtitle() {
        commandQueue.async { [weak self] in
            self?.command(["cycle", "sub"])
        }
    }

    public func selectTrack(id: Int, kind: TrackKind) {
        let name: String
        switch kind {
        case .video: name = "vid"
        case .audio: name = "aid"
        case .subtitle: name = "sid"
        }
        commandQueue.async { [weak self] in
            self?.command(["set", name, "\(id)"])
        }
    }

    public func disableAudioTrack() {
        commandQueue.async { [weak self] in
            self?.command(["set", "aid", "no"])
        }
    }

    private func setStringOption(_ name: String, _ value: String) {
        commandQueue.async { [weak self] in
            self?.command(["set", name, value])
        }
    }

    public func showOSD(_ text: String) {
        commandQueue.async { [weak self] in
            self?.command([MPVCommand.showText.rawValue, text, "3000"])
        }
    }

    public func trackSnapshot() -> TrackSnapshot {
        guard isInitialized, !isShuttingDown else {
            return TrackSnapshot(tracks: [], activeSubtitleTrackID: nil, activeSecondarySubtitleTrackID: nil)
        }
        return commandQueue.sync {
            guard isInitialized, !isShuttingDown, let handle else {
                return TrackSnapshot(tracks: [], activeSubtitleTrackID: nil, activeSecondarySubtitleTrackID: nil)
            }
            return TrackSnapshot(
                tracks: MPVTrackList.parseTracks(from: handle),
                activeSubtitleTrackID: MPVTrackList.currentSubtitleTrackID(from: handle),
                activeSecondarySubtitleTrackID: MPVTrackList.currentSecondarySubtitleTrackID(from: handle)
            )
        }
    }

    public func chapterSnapshot() -> [Chapter] {
        guard isInitialized, !isShuttingDown else { return [] }
        return commandQueue.sync {
            guard isInitialized, !isShuttingDown, let handle else { return [] }
            return MPVChapterList.parseChapters(from: handle)
        }
    }

    public func setABLoopA(_ time: TimeInterval?) {
        setABLoopPoint(MPVProperty.abLoopA.rawValue, time: time)
    }

    public func setABLoopB(_ time: TimeInterval?) {
        setABLoopPoint(MPVProperty.abLoopB.rawValue, time: time)
    }

    public func clearABLoop() {
        setABLoopA(nil)
        setABLoopB(nil)
    }

    public func abLoopSnapshot() -> (a: TimeInterval?, b: TimeInterval?) {
        guard isInitialized, !isShuttingDown else { return (nil, nil) }
        return commandQueue.sync {
            guard isInitialized, !isShuttingDown, handle != nil else { return (nil, nil) }
            return (readABLoopPoint(MPVProperty.abLoopA.rawValue), readABLoopPoint(MPVProperty.abLoopB.rawValue))
        }
    }

    private func setABLoopPoint(_ name: String, time: TimeInterval?) {
        if let time {
            setProperty(name, double: time)
        } else {
            setStringOption(name, "no")
        }
    }

    private func readABLoopPoint(_ name: String) -> TimeInterval? {
        if let string = getString(name) {
            let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalized.isEmpty || normalized == "no" { return nil }
            if let value = Double(normalized), value.isFinite { return value }
        }
        if let value = getDouble(name), value.isFinite {
            return value
        }
        return nil
    }

    public func playbackInfo() -> PlaybackInfo {
        guard isInitialized, !isShuttingDown else {
            return PlaybackInfo()
        }
        return commandQueue.sync {
            guard isInitialized, !isShuttingDown, handle != nil else {
                return PlaybackInfo()
            }
            return PlaybackInfo(
                position: getDouble(MPVProperty.timePos.rawValue) ?? 0,
                duration: getDouble(MPVProperty.duration.rawValue) ?? 0,
                isPaused: (getFlag(MPVProperty.pause.rawValue) ?? 1) == 1,
                volume: getDouble(MPVProperty.volume.rawValue) ?? 100,
                speed: getDouble(MPVProperty.speed.rawValue) ?? 1,
                title: getString(MPVProperty.mediaTitle.rawValue) ?? getString(MPVProperty.filename.rawValue) ?? ""
            )
        }
    }

    public var hasReachedEOF: Bool {
        guard isInitialized, !isShuttingDown, handle != nil else { return false }
        return commandQueue.sync {
            guard isInitialized, !isShuttingDown, handle != nil else { return false }
            return (getFlag(MPVProperty.eofReached.rawValue) ?? 0) != 0
        }
    }

    public func shutdown() {
        guard handle != nil else { return }
        isShuttingDown = true
        isRunning = false
        isInitialized = false
        #if os(iOS) || os(tvOS)
        resumeReadyWaiters(with: MPVError.notInitialized)
        #endif
        renderSurface?.detach()
        renderSurface = nil
        commandQueue.sync { [weak self] in
            guard let self, let handle = self.handle else { return }
            mpv_command_string(handle, "quit")
            mpv_terminate_destroy(handle)
            self.handle = nil
        }
        isShuttingDown = false
    }

    // MARK: - Internal

    func mpvHandle() -> OpaquePointer? { handle }

    private func setOption(name: String, value: String) throws {
        guard let handle else { throw MPVError.notInitialized }
        let status = mpv_set_option_string(handle, name, value)
        guard status >= 0 else { throw MPVError.optionFailed(name, status) }
    }

    private func observe(properties: [String]) {
        guard let handle else { return }
        for property in properties {
            mpv_observe_property(handle, 0, property, MPV_FORMAT_NONE)
        }
    }

    private func startEventLoop() {
        isRunning = true
        eventQueue.async { [weak self] in
            guard let self, let handle = self.handle else { return }
            while self.isRunning {
                guard let event = mpv_wait_event(handle, 0.1) else { continue }
                guard event.pointee.event_id != MPV_EVENT_NONE else { continue }
                if event.pointee.event_id == MPV_EVENT_SHUTDOWN {
                    break
                }
                let clientEvent = self.mapEvent(event)
                if let clientEvent {
                    self.onEvent?(clientEvent)
                }
            }
        }
    }

    private func mapEvent(_ event: UnsafeMutablePointer<mpv_event>) -> MPVClientEvent? {
        switch event.pointee.event_id {
        case MPV_EVENT_FILE_LOADED:
            return .fileLoaded
        case MPV_EVENT_END_FILE:
            guard let data = event.pointee.data else { return nil }
            let end = data.load(as: mpv_event_end_file.self)
            return .endFile(reason: MPVEndFileReason(mpv: end.reason), error: end.error)
        case MPV_EVENT_PROPERTY_CHANGE:
            return .propertyChanged
        case MPV_EVENT_LOG_MESSAGE:
            return nil
        default:
            return nil
        }
    }

    private func command(_ args: [String]) {
        guard isInitialized, let handle else { return }
        var cargs: [UnsafePointer<CChar>?] = args.map { arg in
            strdup(arg).map { UnsafePointer($0) }
        }
        cargs.append(nil)
        defer {
            for ptr in cargs where ptr != nil {
                free(UnsafeMutableRawPointer(mutating: ptr!))
            }
        }
        mpv_command(handle, &cargs)
    }

    private func setProperty(_ name: String, flag: Int32) {
        commandQueue.async { [weak self] in
            guard let self, self.isInitialized, let handle = self.handle else { return }
            var value = flag
            mpv_set_property(handle, name, MPV_FORMAT_FLAG, &value)
        }
    }

    private func setProperty(_ name: String, double: Double) {
        commandQueue.async { [weak self] in
            guard let self, self.isInitialized, let handle = self.handle else { return }
            var value = double
            mpv_set_property(handle, name, MPV_FORMAT_DOUBLE, &value)
        }
    }

    private func getDouble(_ name: String) -> Double? {
        guard let handle else { return nil }
        var value = Double(0)
        let status = mpv_get_property(handle, name, MPV_FORMAT_DOUBLE, &value)
        return status >= 0 ? value : nil
    }

    private func getFlag(_ name: String) -> Int32? {
        guard let handle else { return nil }
        var value: Int32 = 0
        let status = mpv_get_property(handle, name, MPV_FORMAT_FLAG, &value)
        return status >= 0 ? value : nil
    }

    private func getString(_ name: String) -> String? {
        guard let handle else { return nil }
        guard let cString = mpv_get_property_string(handle, name) else { return nil }
        defer { mpv_free(cString) }
        return String(cString: cString)
    }
}

public enum MPVEndFileReason: Sendable, Equatable {
    case eof
    case stop
    case quit
    case error
    case redirect

    init(mpv reason: mpv_end_file_reason) {
        switch reason {
        case MPV_END_FILE_REASON_EOF: self = .eof
        case MPV_END_FILE_REASON_STOP: self = .stop
        case MPV_END_FILE_REASON_QUIT: self = .quit
        case MPV_END_FILE_REASON_ERROR: self = .error
        case MPV_END_FILE_REASON_REDIRECT: self = .redirect
        default: self = .stop
        }
    }
}

public enum MPVClientEvent: Sendable {
    case fileLoaded
    case endFile(reason: MPVEndFileReason, error: Int32)
    case propertyChanged
}

public struct TrackSnapshot: Sendable {
    public let tracks: [Track]
    public let activeSubtitleTrackID: Int?
    public let activeSecondarySubtitleTrackID: Int?

    public init(
        tracks: [Track],
        activeSubtitleTrackID: Int?,
        activeSecondarySubtitleTrackID: Int? = nil
    ) {
        self.tracks = tracks
        self.activeSubtitleTrackID = activeSubtitleTrackID
        self.activeSecondarySubtitleTrackID = activeSecondarySubtitleTrackID
    }

    public var subtitleTracks: [Track] {
        tracks.filter { $0.kind == .subtitle }
    }

    public var embeddedSubtitleTracks: [Track] {
        subtitleTracks.filter { !$0.isExternal }
    }

    public var externalSubtitleTracks: [Track] {
        subtitleTracks.filter { $0.isExternal }
    }

    public var subtitlesAreActive: Bool {
        activeSubtitleTrackID != nil
    }
}

public enum MPVError: Error, LocalizedError {
    case creationFailed
    case notInitialized
    case initializationFailed(Int32)
    case optionFailed(String, Int32)

    public var errorDescription: String? {
        switch self {
        case .creationFailed: return "Failed to create mpv instance"
        case .notInitialized: return "mpv is not initialized"
        case .initializationFailed(let code): return "mpv_initialize failed (\(code))"
        case .optionFailed(let name, let code): return "Failed to set option \(name) (\(code))"
        }
    }
}
