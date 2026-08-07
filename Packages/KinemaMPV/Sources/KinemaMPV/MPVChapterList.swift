import Foundation
import KinemaCore
import LibMPV

enum MPVChapterList {
    static func parseChapters(from handle: OpaquePointer) -> [Chapter] {
        var node = mpv_node()
        guard mpv_get_property(handle, MPVProperty.chapterList.rawValue, MPV_FORMAT_NODE, &node) >= 0 else {
            return []
        }
        defer { mpv_free_node_contents(&node) }

        guard node.format == MPV_FORMAT_NODE_ARRAY, let listPointer = node.u.list else { return [] }
        let list = listPointer.pointee
        guard let values = list.values else { return [] }

        var chapters: [Chapter] = []
        chapters.reserveCapacity(Int(list.num))

        for index in 0 ..< Int(list.num) {
            let entry = values[index]
            guard entry.format == MPV_FORMAT_NODE_MAP, let mapPointer = entry.u.list else { continue }

            let fields = mapFields(mapPointer.pointee)
            guard let time = fields["time"]?.doubleValue else { continue }

            let title = fields["title"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let id = fields["id"]?.intValue ?? index

            chapters.append(Chapter(id: id, title: title, time: time))
        }

        // Keep timeline order; fall back to stable index ids if mpv duplicates ids.
        chapters.sort { $0.time < $1.time }
        if Set(chapters.map(\.id)).count != chapters.count {
            chapters = chapters.enumerated().map { offset, chapter in
                Chapter(id: offset, title: chapter.title, time: chapter.time)
            }
        }

        return chapters
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
}
