public struct DisplayIdentity: Hashable, Sendable {
    public let vendor: UInt32
    public let product: UInt32

    public init(vendor: UInt32, product: UInt32) {
        self.vendor = vendor
        self.product = product
    }

    public var label: String {
        "\(String(vendor, radix: 16)):\(String(product, radix: 16))"
    }
}
