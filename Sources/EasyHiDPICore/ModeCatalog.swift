public struct DisplayModeInfo: Hashable, Sendable {
    public let id: Int32
    public let size: DisplaySize
    public let pixels: DisplaySize
    public let refreshRate: Double
    public let isNative: Bool

    public init(id: Int32, size: DisplaySize, pixels: DisplaySize, refreshRate: Double, isNative: Bool) {
        self.id = id
        self.size = size
        self.pixels = pixels
        self.refreshRate = refreshRate
        self.isNative = isNative
    }

    public var isHiDPI: Bool { pixels.width > size.width }
}

public struct SizeRow: Hashable, Sendable {
    public let size: DisplaySize
    public let isCurrent: Bool
    /// Written to the override but not offered by the system until the display reconnects.
    public let isPending: Bool
}

/// The HiDPI sizes a display offers. Native and low-resolution modes stay out of the menu by design.
public struct ModeCatalog: Sendable {
    public let current: DisplayModeInfo
    public let rows: [SizeRow]
    private let modes: [DisplayModeInfo]

    public init(modes: [DisplayModeInfo], current: DisplayModeInfo, overrideSizes: [DisplaySize]) {
        self.modes = modes
        self.current = current

        let native = Self.nativePixels(modes: modes, current: current)
        var sizes = Set(modes.filter {
            $0.isHiDPI
                && $0.size.hasSameAspect(as: native)
                && $0.size.width * 2 >= native.width
                && $0.size.height * 2 >= native.height
        }.map(\.size))
        let offered = Set(modes.filter(\.isHiDPI).map(\.size))
        sizes.formUnion(overrideSizes.filter(offered.contains))
        if current.isHiDPI { sizes.insert(current.size) }

        // The system may never offer an override entry at the panel's native size; it must not stay grey forever.
        let nativeSizes = Set(modes.filter { !$0.isHiDPI && $0.isNative }.map(\.size))
        let pending = Set(overrideSizes).subtracting(offered).subtracting(nativeSizes)

        self.rows = sizes.union(pending)
            .map { size in
                SizeRow(
                    size: size,
                    isCurrent: current.isHiDPI && current.size == size,
                    isPending: pending.contains(size)
                )
            }
            .sorted {
                if $0.size.area != $1.size.area { return $0.size.area > $1.size.area }
                return $0.size.width > $1.size.width
            }
    }

    /// What the mode in use can switch between without changing size, fastest first.
    public var rates: [Double] {
        Self.distinctRates(of: modesLikeCurrent + [current])
    }

    public func rates(for row: SizeRow) -> [Double] {
        Self.distinctRates(of: modes.filter { $0.isHiDPI && $0.size == row.size })
    }

    /// Keeps the current refresh rate when the target size has it, otherwise takes the fastest.
    public func target(for row: SizeRow) -> DisplayModeInfo? {
        let sameSize = modes.filter { $0.isHiDPI && $0.size == row.size }
        guard let fastest = sameSize.map(\.refreshRate).max() else { return nil }
        let hasCurrentRate = sameSize.contains { Self.sameRate($0.refreshRate, current.refreshRate) }
        let rate = hasCurrentRate ? current.refreshRate : fastest
        return matchingCurrentPosition(in: sameSize.filter { Self.sameRate($0.refreshRate, rate) })
    }

    public func target(forRate rate: Double) -> DisplayModeInfo? {
        matchingCurrentPosition(in: modesLikeCurrent.filter { Self.sameRate($0.refreshRate, rate) })
    }

    public static func sameRate(_ first: Double, _ second: Double) -> Bool {
        abs(first - second) < 0.5
    }

    public static func rateLabel(_ rate: Double) -> String {
        "\(Int(rate.rounded()))Hz"
    }

    private var modesLikeCurrent: [DisplayModeInfo] {
        modes.filter { $0.size == current.size && $0.pixels == current.pixels }
    }

    /// Some sizes list several modes with identical visible properties, so the target takes the
    /// same position among them as the current mode holds among its own.
    private func matchingCurrentPosition(in candidates: [DisplayModeInfo]) -> DisplayModeInfo? {
        guard !candidates.isEmpty else { return nil }
        let currentGroup = modesLikeCurrent
            .filter { Self.sameRate($0.refreshRate, current.refreshRate) }
            .sorted { $0.id < $1.id }
        let position = currentGroup.firstIndex { $0.id == current.id } ?? 0
        return candidates.sorted { $0.id < $1.id }[min(position, candidates.count - 1)]
    }

    /// 59.94 and 60 read the same, so they count as one rate. Some panels report 0 for an unknown rate.
    private static func distinctRates(of modes: [DisplayModeInfo]) -> [Double] {
        modes.map(\.refreshRate).filter { $0 > 0 }.sorted(by: >).reduce(into: []) { rates, rate in
            if !rates.contains(where: { sameRate($0, rate) }) { rates.append(rate) }
        }
    }

    private static func nativePixels(modes: [DisplayModeInfo], current: DisplayModeInfo) -> DisplaySize {
        let flagged = modes.filter(\.isNative).map(\.pixels)
        let lowResolution = modes.filter { !$0.isHiDPI }.map(\.pixels)
        let candidates = flagged.isEmpty ? lowResolution : flagged
        return candidates.max { $0.area < $1.area } ?? current.pixels
    }
}
