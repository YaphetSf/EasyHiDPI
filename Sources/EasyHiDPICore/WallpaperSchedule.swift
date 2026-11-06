import Foundation

/// The `apple_desktop` metadata of a dynamic wallpaper: which frame shows when.
public enum WallpaperSchedule: Equatable, Sendable {
    public struct SolarFrame: Equatable, Sendable {
        public let altitude: Double
        public let azimuth: Double
        public let index: Int

        public init(altitude: Double, azimuth: Double, index: Int) {
            self.altitude = altitude
            self.azimuth = azimuth
            self.index = index
        }
    }

    case solar([SolarFrame])
    case appearance(light: Int, dark: Int)

    public init?(tag: String, base64: String) {
        guard let data = Data(base64Encoded: base64),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }
        switch tag {
        case "solar":
            let entries = plist["si"] as? [[String: Any]] ?? []
            let frames = entries.compactMap { entry -> SolarFrame? in
                guard let altitude = entry["a"] as? NSNumber,
                      let azimuth = entry["z"] as? NSNumber,
                      let index = entry["i"] as? NSNumber else { return nil }
                return SolarFrame(altitude: altitude.doubleValue, azimuth: azimuth.doubleValue, index: index.intValue)
            }
            guard !frames.isEmpty else { return nil }
            self = .solar(frames)
        case "apr":
            guard let light = plist["l"] as? NSNumber, let dark = plist["d"] as? NSNumber else { return nil }
            self = .appearance(light: light.intValue, dark: dark.intValue)
        default:
            return nil
        }
    }

    /// Morning and evening frames can share an altitude, so the sun's side of the sky is matched first.
    public func frameIndex(sun: SunPosition, isDark: Bool) -> Int {
        switch self {
        case let .appearance(light, dark):
            return isDark ? dark : light
        case let .solar(frames):
            let isMorning = sun.azimuth < 180
            let sameSide = frames.filter { ($0.azimuth < 180) == isMorning }
            let candidates = sameSide.isEmpty ? frames : sameSide
            let closest = candidates.min { abs($0.altitude - sun.altitude) < abs($1.altitude - sun.altitude) }
            return closest?.index ?? 0
        }
    }
}
