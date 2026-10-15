import Foundation

/// UUIDv7 identifiers: globally unique and sortable by creation time.
public enum EntityID {
    public static func make(at date: Date) -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        let ms = UInt64(max(0, date.timeIntervalSince1970 * 1000))
        for i in 0..<6 {
            bytes[i] = UInt8((ms >> (8 * UInt64(5 - i))) & 0xFF)
        }
        for i in 6..<16 {
            bytes[i] = UInt8.random(in: 0...255)
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x70 // version 7
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // RFC 4122 variant
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        let parts = [hex.prefix(8), hex.dropFirst(8).prefix(4), hex.dropFirst(12).prefix(4),
                     hex.dropFirst(16).prefix(4), hex.dropFirst(20)]
        return parts.joined(separator: "-")
    }
}
