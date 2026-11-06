public struct DisplaySize: Hashable, Sendable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public init?(parsing text: String) {
        let parts = text.split { !$0.isNumber }
        guard parts.count == 2,
              let width = Int(parts[0]), let height = Int(parts[1]),
              (1...8192).contains(width), (1...8192).contains(height) else { return nil }
        self.init(width: width, height: height)
    }

    public var label: String { "\(width)\u{00D7}\(height)" }
    public var area: Int { width * height }

    /// Converts between what a rotated display shows and the panel orientation plists use.
    public func oriented(rotationDegrees: Int) -> DisplaySize {
        rotationDegrees % 180 == 0 ? self : DisplaySize(width: height, height: width)
    }

    func hasSameAspect(as other: DisplaySize) -> Bool {
        let mine = Double(width) / Double(height)
        let theirs = Double(other.width) / Double(other.height)
        return abs(mine - theirs) / theirs < 0.015
    }
}
