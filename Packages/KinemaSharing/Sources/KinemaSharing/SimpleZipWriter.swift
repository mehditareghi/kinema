import Foundation

/// Minimal ZIP (store-only) so Wi‑Fi Sharing can download whole folders.
enum SimpleZipWriter {
    static func zipData(from files: [(name: String, data: Data)]) -> Data {
        var central = Data()
        var local = Data()
        var offset: UInt32 = 0
        var entries: UInt16 = 0

        for file in files {
            let nameData = Data(file.name.utf8)
            let crc = crc32(file.data)
            let size = UInt32(file.data.count)

            var localHeader = Data()
            localHeader.append(contentsOf: UInt32(0x04034b50).littleEndianBytes)
            localHeader.append(contentsOf: UInt16(20).littleEndianBytes) // version needed
            localHeader.append(contentsOf: UInt16(0).littleEndianBytes) // flags
            localHeader.append(contentsOf: UInt16(0).littleEndianBytes) // store
            localHeader.append(contentsOf: UInt16(0).littleEndianBytes) // time
            localHeader.append(contentsOf: UInt16(0).littleEndianBytes) // date
            localHeader.append(contentsOf: crc.littleEndianBytes)
            localHeader.append(contentsOf: size.littleEndianBytes)
            localHeader.append(contentsOf: size.littleEndianBytes)
            localHeader.append(contentsOf: UInt16(nameData.count).littleEndianBytes)
            localHeader.append(contentsOf: UInt16(0).littleEndianBytes) // extra
            localHeader.append(nameData)
            localHeader.append(file.data)

            var centralHeader = Data()
            centralHeader.append(contentsOf: UInt32(0x02014b50).littleEndianBytes)
            centralHeader.append(contentsOf: UInt16(20).littleEndianBytes)
            centralHeader.append(contentsOf: UInt16(20).littleEndianBytes)
            centralHeader.append(contentsOf: UInt16(0).littleEndianBytes)
            centralHeader.append(contentsOf: UInt16(0).littleEndianBytes)
            centralHeader.append(contentsOf: UInt16(0).littleEndianBytes)
            centralHeader.append(contentsOf: UInt16(0).littleEndianBytes)
            centralHeader.append(contentsOf: crc.littleEndianBytes)
            centralHeader.append(contentsOf: size.littleEndianBytes)
            centralHeader.append(contentsOf: size.littleEndianBytes)
            centralHeader.append(contentsOf: UInt16(nameData.count).littleEndianBytes)
            centralHeader.append(contentsOf: UInt16(0).littleEndianBytes)
            centralHeader.append(contentsOf: UInt16(0).littleEndianBytes)
            centralHeader.append(contentsOf: UInt16(0).littleEndianBytes)
            centralHeader.append(contentsOf: UInt16(0).littleEndianBytes)
            centralHeader.append(contentsOf: UInt32(0).littleEndianBytes)
            centralHeader.append(contentsOf: offset.littleEndianBytes)
            centralHeader.append(nameData)

            offset += UInt32(localHeader.count)
            local.append(localHeader)
            central.append(centralHeader)
            entries += 1
        }

        var end = Data()
        end.append(contentsOf: UInt32(0x06054b50).littleEndianBytes)
        end.append(contentsOf: UInt16(0).littleEndianBytes)
        end.append(contentsOf: UInt16(0).littleEndianBytes)
        end.append(contentsOf: entries.littleEndianBytes)
        end.append(contentsOf: entries.littleEndianBytes)
        end.append(contentsOf: UInt32(central.count).littleEndianBytes)
        end.append(contentsOf: offset.littleEndianBytes)
        end.append(contentsOf: UInt16(0).littleEndianBytes)

        var result = Data()
        result.append(local)
        result.append(central)
        result.append(end)
        return result
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffff_ffff
        for byte in data {
            let idx = Int((crc ^ UInt32(byte)) & 0xff)
            crc = (crc >> 8) ^ crcTable[idx]
        }
        return crc ^ 0xffff_ffff
    }

    private static let crcTable: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? (0xedb88320 ^ (c >> 1)) : (c >> 1)
            }
            return c
        }
    }()
}

private extension FixedWidthInteger {
    var littleEndianBytes: [UInt8] {
        withUnsafeBytes(of: littleEndian, Array.init)
    }
}
