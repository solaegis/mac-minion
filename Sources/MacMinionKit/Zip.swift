import Foundation

/// A small ZIP writer: deflated entries, names exactly as given (Minion stores absolute paths, with the
/// leading slash), no ZIP64. Enough for settings and SavedVariables backups.
public struct ZipWriter {
    public struct Entry {
        public let name: String
        public let data: Data
        public let modified: Date

        public init(name: String, data: Data, modified: Date) {
            self.name = name; self.data = data; self.modified = modified
        }
    }

    public static func write(_ entries: [Entry], to url: URL) throws {
        var out = Data()
        var central = Data()
        for entry in entries {
            let name = Data(entry.name.utf8)
            let crc = CRC32.checksum(entry.data)
            // Deflate when it helps; store otherwise. NSData's .zlib is raw DEFLATE, as ZIP wants.
            let deflated = (try? (entry.data as NSData).compressed(using: .zlib) as Data) ?? entry.data
            let useDeflate = deflated.count < entry.data.count
            let body = useDeflate ? deflated : entry.data
            let (time, date) = dosDateTime(entry.modified)
            let offset = UInt32(out.count)

            out.append(le32(0x04034b50))
            out.append(le16(20)); out.append(le16(0x0800)) // version, flags: UTF-8 names
            out.append(le16(useDeflate ? 8 : 0)); out.append(le16(time)); out.append(le16(date))
            out.append(le32(crc)); out.append(le32(UInt32(body.count))); out.append(le32(UInt32(entry.data.count)))
            out.append(le16(UInt16(name.count))); out.append(le16(0))
            out.append(name); out.append(body)

            central.append(le32(0x02014b50))
            central.append(le16(20)); central.append(le16(20)); central.append(le16(0x0800))
            central.append(le16(useDeflate ? 8 : 0)); central.append(le16(time)); central.append(le16(date))
            central.append(le32(crc)); central.append(le32(UInt32(body.count))); central.append(le32(UInt32(entry.data.count)))
            central.append(le16(UInt16(name.count))); central.append(le16(0)); central.append(le16(0))
            central.append(le16(0)); central.append(le16(0)); central.append(le32(0)); central.append(le32(offset))
            central.append(name)
        }
        let centralOffset = UInt32(out.count)
        out.append(central)
        out.append(le32(0x06054b50)); out.append(le16(0)); out.append(le16(0))
        out.append(le16(UInt16(entries.count))); out.append(le16(UInt16(entries.count)))
        out.append(le32(UInt32(central.count))); out.append(le32(centralOffset)); out.append(le16(0))
        try out.write(to: url, options: .atomic)
    }

    static func dosDateTime(_ date: Date) -> (UInt16, UInt16) {
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let time = UInt16((c.hour ?? 0) << 11 | (c.minute ?? 0) << 5 | (c.second ?? 0) / 2)
        let day = UInt16(max((c.year ?? 1980) - 1980, 0) << 9 | (c.month ?? 1) << 5 | (c.day ?? 1))
        return (time, day)
    }

    static func le16(_ v: UInt16) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
    static func le32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
}

enum CRC32 {
    static let table: [UInt32] = (0..<256).map { i in
        (0..<8).reduce(UInt32(i)) { c, _ in c & 1 == 1 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFFFFFF
    }
}
