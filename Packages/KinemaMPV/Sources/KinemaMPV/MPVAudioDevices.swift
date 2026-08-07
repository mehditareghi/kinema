import Foundation
import LibMPV

enum MPVAudioDevices {
    static func parse(from handle: OpaquePointer) -> [MPVController.AudioDevice] {
        var node = mpv_node()
        guard mpv_get_property(handle, MPVProperty.audioDeviceList.rawValue, MPV_FORMAT_NODE, &node) >= 0 else {
            return []
        }
        defer { mpv_free_node_contents(&node) }

        guard node.format == MPV_FORMAT_NODE_ARRAY, let listPointer = node.u.list else { return [] }
        let list = listPointer.pointee
        guard let values = list.values else { return [] }

        var devices: [MPVController.AudioDevice] = []
        devices.reserveCapacity(Int(list.num))

        for index in 0 ..< Int(list.num) {
            let entry = values[index]
            guard entry.format == MPV_FORMAT_NODE_MAP, let mapPointer = entry.u.list else { continue }
            let fields = mapFields(mapPointer.pointee)
            guard let name = fields["name"]?.stringValue, !name.isEmpty else { continue }
            let description = fields["description"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            devices.append(
                MPVController.AudioDevice(
                    id: name,
                    description: (description?.isEmpty == false) ? description! : name
                )
            )
        }
        return devices
    }

    private static func mapFields(_ map: mpv_node_list) -> [String: MPVNodeValue] {
        guard let keys = map.keys, let values = map.values else { return [:] }
        var fields: [String: MPVNodeValue] = [:]
        for index in 0 ..< Int(map.num) {
            guard let keyPointer = keys[index] else { continue }
            let key = String(cString: keyPointer)
            fields[key] = MPVNodeValue(values[index])
        }
        return fields
    }
}
