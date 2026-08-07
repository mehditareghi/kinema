import Foundation
import KinemaCore
import LibMPV

enum MPVTrackList {
    static func parseTracks(from handle: OpaquePointer) -> [Track] {
        var node = mpv_node()
        guard mpv_get_property(handle, MPVProperty.trackList.rawValue, MPV_FORMAT_NODE, &node) >= 0 else {
            return []
        }
        defer { mpv_free_node_contents(&node) }

        guard node.format == MPV_FORMAT_NODE_ARRAY, let listPointer = node.u.list else { return [] }
        let list = listPointer.pointee
        guard let values = list.values else { return [] }

        var tracks: [Track] = []
        tracks.reserveCapacity(Int(list.num))

        for index in 0 ..< Int(list.num) {
            let entry = values[index]
            guard entry.format == MPV_FORMAT_NODE_MAP, let mapPointer = entry.u.list else { continue }

            let fields = mapFields(mapPointer.pointee)
            guard let type = fields["type"]?.stringValue else { continue }
            guard let kind = trackKind(for: type) else { continue }
            guard let id = fields["id"]?.intValue else { continue }

            let title = fields["title"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let language = fields["lang"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            let isSelected = fields["selected"]?.flagValue ?? false
            let isExternal = fields["external"]?.flagValue ?? false
            let isDefault = fields["default"]?.flagValue ?? false
            let isForced = fields["forced"]?.flagValue ?? false
            let isHearingImpaired = fields["hearing-impaired"]?.flagValue ?? false
            let codec = fields["codec"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            let mainSelection = fields["main-selection"]?.intValue
            let isSecondarySelected = mainSelection == 1
            let ffIndex = fields["ff-index"]?.intValue
            let externalFilename = fields["external-filename"]?.stringValue?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let displayTitle: String
            if title.isEmpty, let externalFilename, !externalFilename.isEmpty {
                displayTitle = URL(fileURLWithPath: externalFilename).lastPathComponent
            } else {
                displayTitle = title
            }

            tracks.append(
                Track(
                    id: id,
                    kind: kind,
                    title: displayTitle,
                    language: language?.isEmpty == true ? nil : language,
                    isSelected: isSelected && !isSecondarySelected,
                    isExternal: isExternal,
                    isDefault: isDefault,
                    isForced: isForced,
                    codec: codec?.isEmpty == true ? nil : codec,
                    isHearingImpaired: isHearingImpaired,
                    isSecondarySelected: isSecondarySelected,
                    ffIndex: ffIndex,
                    externalFilename: (externalFilename?.isEmpty == false) ? externalFilename : nil
                )
            )
        }

        return tracks
    }

    static func currentSubtitleTrackID(from handle: OpaquePointer) -> Int? {
        parseSID(from: handle, property: MPVProperty.sid.rawValue)
    }

    static func currentSecondarySubtitleTrackID(from handle: OpaquePointer) -> Int? {
        parseSID(from: handle, property: MPVProperty.secondarySid.rawValue)
    }

    private static func parseSID(from handle: OpaquePointer, property: String) -> Int? {
        if let string = getString(handle, property) {
            let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalized == "no" { return nil }
            if normalized == "auto" {
                return parseTracks(from: handle)
                    .first(where: { $0.kind == .subtitle && $0.isSelected })?
                    .id
            }
            if let id = Int(normalized) { return id }
        }

        if let id = getInt64(handle, property) {
            return Int(id)
        }

        return nil
    }

    private static func trackKind(for type: String) -> TrackKind? {
        switch type {
        case "video": return .video
        case "audio": return .audio
        case "sub": return .subtitle
        default: return nil
        }
    }

    private static func mapFields(_ map: mpv_node_list) -> [String: MPVNodeValue] {
        var fields: [String: MPVNodeValue] = [:]
        guard let keys = map.keys, let values = map.values else { return fields }
        for index in 0 ..< Int(map.num) {
            guard let keyPointer = keys[index] else { continue }
            let key = String(cString: keyPointer)
            fields[key] = MPVNodeValue(values[index])
        }
        return fields
    }

    private static func getString(_ handle: OpaquePointer, _ name: String) -> String? {
        guard let cString = mpv_get_property_string(handle, name) else { return nil }
        defer { mpv_free(cString) }
        return String(cString: cString)
    }

    private static func getInt64(_ handle: OpaquePointer, _ name: String) -> Int64? {
        var value: Int64 = 0
        guard mpv_get_property(handle, name, MPV_FORMAT_INT64, &value) >= 0 else { return nil }
        return value
    }
}

enum MPVNodeValue {
    case string(String)
    case flag(Bool)
    case int(Int)
    case double(Double)

    init(_ node: mpv_node) {
        switch node.format {
        case MPV_FORMAT_STRING:
            self = .string(node.u.string.flatMap { String(cString: $0) } ?? "")
        case MPV_FORMAT_FLAG:
            self = .flag(node.u.flag != 0)
        case MPV_FORMAT_INT64:
            self = .int(Int(node.u.int64))
        case MPV_FORMAT_DOUBLE:
            self = .double(node.u.double_)
        default:
            self = .string("")
        }
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var flagValue: Bool {
        if case .flag(let value) = self { return value }
        return false
    }

    var intValue: Int? {
        if case .int(let value) = self { return value }
        return nil
    }
}
