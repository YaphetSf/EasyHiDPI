public struct DDCReading: Equatable, Sendable {
    public let current: Int
    public let maximum: Int

    public init(current: Int, maximum: Int) {
        self.current = current
        self.maximum = maximum
    }
}

public enum DDC {
    public static let brightnessCode: UInt8 = 0x10
    public static let chipAddress: UInt32 = 0x37
    public static let dataAddress: UInt32 = 0x51
    public static let replyLength = 11

    public static func readRequest(code: UInt8) -> [UInt8] {
        withChecksum([0x82, 0x01, code])
    }

    public static func writeRequest(code: UInt8, value: Int) -> [UInt8] {
        let clamped = UInt16(clamping: value)
        return withChecksum([0x84, 0x03, code, UInt8(clamped >> 8), UInt8(clamped & 0xFF)])
    }

    /// Only a `88 02` header is a reply. A display with nothing to say sends the null header `80 be`,
    /// and the bytes after it are whatever its buffer last held, often an older reply that still checks out.
    public static func parseReply(_ bytes: [UInt8], code: UInt8) -> DDCReading? {
        guard bytes.count >= replyLength,
              bytes[0] == 0x6E, bytes[1] == 0x88, bytes[2] == 0x02,
              bytes[3] == 0x00, bytes[4] == code else { return nil }
        let checksum = bytes[0..<(replyLength - 1)].reduce(UInt8(0x50), ^)
        guard checksum == bytes[replyLength - 1] else { return nil }
        let maximum = Int(bytes[6]) << 8 | Int(bytes[7])
        let current = Int(bytes[8]) << 8 | Int(bytes[9])
        guard maximum > 0 else { return nil }
        return DDCReading(current: current, maximum: maximum)
    }

    private static func withChecksum(_ payload: [UInt8]) -> [UInt8] {
        payload + [payload.reduce(UInt8(0x6E ^ 0x51), ^)]
    }
}
