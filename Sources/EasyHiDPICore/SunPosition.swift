import Foundation

public struct GeoCoordinate: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Finds a time zone's principal city in the system's zone.tab, which needs no location
    /// permission and is close enough to pick a wallpaper frame.
    public init?(zoneTab: String, timeZoneIdentifier: String) {
        for line in zoneTab.split(separator: "\n") where !line.hasPrefix("#") {
            let columns = line.split(separator: "\t")
            guard columns.count >= 3, columns[2] == timeZoneIdentifier else { continue }
            guard let parsed = Self.parseISO6709(String(columns[1])) else { return nil }
            self = parsed
            return
        }
        return nil
    }

    private static func parseISO6709(_ text: String) -> GeoCoordinate? {
        guard let split = text.dropFirst().firstIndex(where: { $0 == "+" || $0 == "-" }) else { return nil }
        guard let latitude = parseAngle(text[..<split], degreeDigits: 2),
              let longitude = parseAngle(text[split...], degreeDigits: 3) else { return nil }
        return GeoCoordinate(latitude: latitude, longitude: longitude)
    }

    private static func parseAngle(_ text: Substring, degreeDigits: Int) -> Double? {
        guard let sign = text.first, sign == "+" || sign == "-" else { return nil }
        let digits = text.dropFirst()
        guard digits.count == degreeDigits + 2 || digits.count == degreeDigits + 4,
              let degrees = Double(digits.prefix(degreeDigits)),
              let minutes = Double(digits.dropFirst(degreeDigits).prefix(2)) else { return nil }
        let seconds = Double(digits.dropFirst(degreeDigits + 2)) ?? 0
        let magnitude = degrees + minutes / 60 + seconds / 3600
        return sign == "-" ? -magnitude : magnitude
    }
}

/// Degrees: altitude above the horizon, azimuth clockwise from north.
public struct SunPosition: Equatable, Sendable {
    public let altitude: Double
    public let azimuth: Double

    public init(altitude: Double, azimuth: Double) {
        self.altitude = altitude
        self.azimuth = azimuth
    }

    /// Low-precision almanac formula, accurate to well under a degree.
    public init(date: Date, location: GeoCoordinate) {
        let radians = Double.pi / 180
        let days = date.timeIntervalSince1970 / 86400 + 2_440_587.5 - 2_451_545.0

        let meanLongitude = 280.460 + 0.9856474 * days
        let meanAnomaly = (357.528 + 0.9856003 * days) * radians
        let eclipticLongitude = (meanLongitude + 1.915 * sin(meanAnomaly) + 0.020 * sin(2 * meanAnomaly)) * radians
        let obliquity = (23.439 - 0.0000004 * days) * radians

        let rightAscension = atan2(cos(obliquity) * sin(eclipticLongitude), cos(eclipticLongitude))
        let declination = asin(sin(obliquity) * sin(eclipticLongitude))

        let siderealDegrees = 280.46061837 + 360.98564736629 * days
        let hourAngle = (siderealDegrees + location.longitude) * radians - rightAscension
        let latitude = location.latitude * radians

        let altitude = asin(sin(latitude) * sin(declination) + cos(latitude) * cos(declination) * cos(hourAngle))
        let azimuth = atan2(
            -sin(hourAngle) * cos(declination),
            cos(latitude) * sin(declination) - sin(latitude) * cos(declination) * cos(hourAngle)
        )

        self.altitude = altitude / radians
        let degrees = (azimuth / radians).truncatingRemainder(dividingBy: 360)
        self.azimuth = degrees < 0 ? degrees + 360 : degrees
    }
}
