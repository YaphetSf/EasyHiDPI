public struct EDIDIdentity: Hashable, Sendable {
    public let display: DisplayIdentity
    public let serial: UInt32

    public init(display: DisplayIdentity, serial: UInt32) {
        self.display = display
        self.serial = serial
    }

    public init?(edid bytes: [UInt8]) {
        let header: [UInt8] = [0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00]
        guard bytes.count >= 16, Array(bytes[0..<8]) == header else { return nil }
        let vendor = UInt32(bytes[8]) << 8 | UInt32(bytes[9])
        let product = UInt32(bytes[11]) << 8 | UInt32(bytes[10])
        let serial = UInt32(bytes[15]) << 24 | UInt32(bytes[14]) << 16 | UInt32(bytes[13]) << 8 | UInt32(bytes[12])
        self.init(display: DisplayIdentity(vendor: vendor, product: product), serial: serial)
    }
}

/// Pairs each display with its DDC endpoint. Identical monitors can share a generic serial, so an
/// exact match is tried first and each endpoint is used at most once.
public func matchEndpoints<Display: Hashable, Endpoint>(
    displays: [(id: Display, identity: EDIDIdentity)],
    endpoints: [(identity: EDIDIdentity, endpoint: Endpoint)]
) -> [Display: Endpoint] {
    var remaining = endpoints
    var matched: [Display: Endpoint] = [:]

    func claim(for id: Display, where predicate: (EDIDIdentity) -> Bool) {
        guard matched[id] == nil, let index = remaining.firstIndex(where: { predicate($0.identity) }) else { return }
        matched[id] = remaining.remove(at: index).endpoint
    }

    for display in displays {
        claim(for: display.id) { $0 == display.identity }
    }
    for display in displays {
        claim(for: display.id) { $0.display == display.identity.display }
    }
    return matched
}
