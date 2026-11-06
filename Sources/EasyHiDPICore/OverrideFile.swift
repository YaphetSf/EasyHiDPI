import Foundation

public enum OverrideLocation {
    public static let root = "/Library/Displays/Contents/Resources/Overrides"

    public static func vendorDirectory(for id: DisplayIdentity) -> String {
        "\(root)/DisplayVendorID-\(String(id.vendor, radix: 16))"
    }

    public static func file(for id: DisplayIdentity) -> String {
        "\(vendorDirectory(for: id))/DisplayProductID-\(String(id.product, radix: 16))"
    }
}

public enum OverrideFileError: Error, Equatable {
    case notADictionary
}

/// One display's override plist. Sizes are looks-like sizes in panel orientation; keys this app
/// does not manage are kept untouched so editing never damages a file another tool wrote.
public struct OverrideFile {
    private static let resolutionsKey = "scale-resolutions"
    private static let defaultDensity = 10.0699301

    private var plist: [String: Any]

    public init(id: DisplayIdentity) {
        plist = [
            "DisplayVendorID": Int(id.vendor),
            "DisplayProductID": Int(id.product),
            Self.resolutionsKey: [Data](),
            "target-default-ppmm": Self.defaultDensity
        ]
    }

    public init(plistData: Data) throws {
        guard let plist = try PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else {
            throw OverrideFileError.notADictionary
        }
        self.plist = plist
    }

    public var sizes: [DisplaySize] {
        var seen = Set<DisplaySize>()
        return entries.compactMap(Self.size(of:)).filter { seen.insert($0).inserted }
    }

    public mutating func add(_ size: DisplaySize) {
        guard !sizes.contains(size) else { return }
        let updated = sizes + [size]
        entries = updated
            .sorted { $0.area > $1.area }
            .flatMap { candidate -> [Data] in
                candidate == size
                    ? Self.entries(for: size)
                    : entries.filter { Self.size(of: $0) == candidate }
            }
    }

    public mutating func remove(_ size: DisplaySize) {
        entries = entries.filter { Self.size(of: $0) != size }
    }

    public func encoded() throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }

    private var entries: [Data] {
        get { plist[Self.resolutionsKey] as? [Data] ?? [] }
        set { plist[Self.resolutionsKey] = newValue }
    }

    /// The three forms Apple's own override files use for HiDPI modes. Which form a given macOS
    /// reads is undocumented, and each trial costs a reconnect, so all three are written.
    private static func entries(for size: DisplaySize) -> [Data] {
        let backing = bigEndian(UInt32(size.width * 2)) + bigEndian(UInt32(size.height * 2))
        return [
            backing + [0x00],
            backing + [0x00, 0x00, 0x00, 0x01],
            backing + [0x00, 0x00, 0x00, 0x09, 0x00, 0xA0, 0x00, 0x00]
        ]
    }

    private static func size(of entry: Data) -> DisplaySize? {
        guard entry.count >= 8 else { return nil }
        let bytes = [UInt8](entry)
        let width = bytes[0..<4].reduce(0) { $0 << 8 | Int($1) }
        let height = bytes[4..<8].reduce(0) { $0 << 8 | Int($1) }
        guard width >= 2, height >= 2 else { return nil }
        return DisplaySize(width: width / 2, height: height / 2)
    }

    private static func bigEndian(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }
}
