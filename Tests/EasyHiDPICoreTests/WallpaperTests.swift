import EasyHiDPICore
import Foundation
import Testing

private func date(_ text: String) throws -> Date {
    try #require(ISO8601DateFormatter().date(from: text))
}

private let northern = GeoCoordinate(latitude: 51.5, longitude: -0.12)

// Metadata captured from the real macOS wallpapers The Beach.heic and Sonoma.heic.
private let beachSolar = "YnBsaXN0MDDSAQIDCFJhcFJzadIEBQYHUWxRZBAAEAGqCQ8SFhoeICMmKdMKCwwNDgZRYVF6UWkjQCQAAAAAAAAjQFkAAAAAAADTCgsMEBEHI8A5AAAAAAAAI0BRgAAAAAAA0woLDBMUFSPAIgAAAAAAACNAVAAAAAAAABAC0woLDBcYGSMAAAAAAAAAACNAVoAAAAAAABAD0woLDBscHSNAOQAAAAAAACNAW4AAAAAAABAE0woLDBsfHSNAb0AAAAAAANMKCwwNISIjQHBAAAAAAAAQBdMKCwwXJCUjQHDgAAAAAAAQBtMKCwwTJygjQHGAAAAAAAAQB9MKCwwQKgcjQHIgAAAAAAAACAANABAAEwAYABoAHAAeACAAKwAyADQANgA4AEEASgBRAFoAYwBqAHMAfAB+AIUAjgCXAJkAoACpALIAtAC7AMQAywDUANYA3QDmAOgA7wD4APoBAQAAAAAAAAIBAAAAAAAAACsAAAAAAAAAAAAAAAAAAAEK"
private let sonomaAppearance = "YnBsaXN0MDDSAQIDBFFsUWQQABABCA0PERMAAAAAAAABAQAAAAAAAAAFAAAAAAAAAAAAAAAAAAAAFQ=="

struct WallpaperScheduleTests {
    @Test func parsesRealSolarMetadata() throws {
        let schedule = try #require(WallpaperSchedule(tag: "solar", base64: beachSolar))
        guard case let .solar(frames) = schedule else {
            Issue.record("expected a solar schedule")
            return
        }
        #expect(frames.count == 10)
        #expect(frames.first == WallpaperSchedule.SolarFrame(altitude: 10, azimuth: 100, index: 0))
        #expect(frames.last == WallpaperSchedule.SolarFrame(altitude: -25, azimuth: 290, index: 1))
    }

    @Test func parsesRealAppearanceMetadata() {
        #expect(WallpaperSchedule(tag: "apr", base64: sonomaAppearance) == .appearance(light: 0, dark: 1))
    }

    @Test func rejectsUnknownTagsAndBadData() {
        #expect(WallpaperSchedule(tag: "other", base64: sonomaAppearance) == nil)
        #expect(WallpaperSchedule(tag: "solar", base64: "not base64") == nil)
        #expect(WallpaperSchedule(tag: "solar", base64: sonomaAppearance) == nil)
    }

    @Test(arguments: [
        ("2026-11-04T00:00:00Z", 1),
        ("2026-11-04T07:05:00Z", 3),
        ("2026-11-04T09:00:00Z", 0),
        ("2026-11-04T12:00:00Z", 4),
        ("2026-11-04T14:30:00Z", 5),
        ("2026-11-04T16:37:00Z", 6),
        ("2026-11-04T17:15:00Z", 7)
    ])
    func solarFramesFollowTheDay(time: String, expected: Int) throws {
        let schedule = try #require(WallpaperSchedule(tag: "solar", base64: beachSolar))
        let sun = SunPosition(date: try date(time), location: northern)
        #expect(schedule.frameIndex(sun: sun, isDark: false) == expected)
    }

    @Test func solarFrameIgnoresAppearance() throws {
        let schedule = try #require(WallpaperSchedule(tag: "solar", base64: beachSolar))
        let sun = SunPosition(altitude: 25, azimuth: 180)
        #expect(schedule.frameIndex(sun: sun, isDark: true) == schedule.frameIndex(sun: sun, isDark: false))
    }

    @Test func appearanceFrameFollowsDarkMode() throws {
        let schedule = try #require(WallpaperSchedule(tag: "apr", base64: sonomaAppearance))
        let sun = SunPosition(altitude: 0, azimuth: 0)
        #expect(schedule.frameIndex(sun: sun, isDark: false) == 0)
        #expect(schedule.frameIndex(sun: sun, isDark: true) == 1)
    }
}

struct SunPositionTests {
    @Test func northernSunsetInNovember() throws {
        let sun = SunPosition(date: try date("2026-11-04T16:35:00Z"), location: northern)
        #expect(abs(sun.altitude) < 2)
        #expect((238...254).contains(sun.azimuth))
    }

    // At solar noon altitude is 90 - |latitude - declination|, with declination +23.44 in June.
    @Test func northernMidsummerNoon() throws {
        let sun = SunPosition(date: try date("2026-06-21T12:02:00Z"), location: northern)
        #expect(abs(sun.altitude - 61.9) < 0.5)
        #expect(abs(sun.azimuth - 180) < 5)
    }

    // In the southern summer the high sun can sit on either side of the zenith; altitude is what matters.
    @Test func sydneyDecemberNoon() throws {
        let sydney = GeoCoordinate(latitude: -33.87, longitude: 151.2)
        let sun = SunPosition(date: try date("2026-12-21T01:59:00Z"), location: sydney)
        #expect(abs(sun.altitude - 79.6) < 0.7)
    }

    @Test func midnightSunIsBelowTheHorizon() throws {
        #expect(SunPosition(date: try date("2026-11-04T00:00:00Z"), location: northern).altitude < -40)
    }
}

// Lines copied from the real /usr/share/zoneinfo/zone.tab.
private let zoneTab = """
# tzdb timezone descriptions
AU\t-3352+15113\tAustralia/Sydney\tNew South Wales (most areas)
CA\t+4734-05243\tAmerica/St_Johns\tNewfoundland, Labrador (SE)
GB\t+513030-0000731\tEurope/London
JP\t+353916+1394441\tAsia/Tokyo
US\t+404251-0740023\tAmerica/New_York\tEastern (most areas)
"""

struct GeoCoordinateTests {
    @Test(arguments: [
        ("Europe/London", 51.508, -0.125),
        ("Asia/Tokyo", 35.654, 139.745),
        ("Australia/Sydney", -33.867, 151.217),
        ("America/St_Johns", 47.567, -52.717),
        ("America/New_York", 40.714, -74.006)
    ])
    func readsZoneTabCoordinates(identifier: String, latitude: Double, longitude: Double) throws {
        let location = try #require(GeoCoordinate(zoneTab: zoneTab, timeZoneIdentifier: identifier))
        #expect(abs(location.latitude - latitude) < 0.01)
        #expect(abs(location.longitude - longitude) < 0.01)
    }

    @Test func unknownZoneIsNil() {
        #expect(GeoCoordinate(zoneTab: zoneTab, timeZoneIdentifier: "Etc/UTC") == nil)
    }
}
