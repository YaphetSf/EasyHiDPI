import CoreGraphics
import EasyHiDPICore
import Foundation
import ImageIO

struct WallpaperKey: Hashable, Sendable {
    let url: URL
    let frame: Int
}

enum Wallpaper {
    private static let thumbnailPixels = 512

    static func key(for url: URL, at date: Date = Date()) -> WallpaperKey {
        WallpaperKey(url: url, frame: frameIndex(of: url, at: date))
    }

    static func thumbnail(for key: WallpaperKey) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(key.url as CFURL, nil) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailPixels
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, key.frame, options)
    }

    private static func frameIndex(of url: URL, at date: Date) -> Int {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 1,
              let schedule = schedule(of: source) else { return 0 }
        let isDark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        let sun = SunPosition(date: date, location: currentLocation())
        let index = schedule.frameIndex(sun: sun, isDark: isDark)
        return index < CGImageSourceGetCount(source) ? index : 0
    }

    private static func schedule(of source: CGImageSource) -> WallpaperSchedule? {
        guard let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil),
              let tags = CGImageMetadataCopyTags(metadata) as? [CGImageMetadataTag] else { return nil }
        for tag in tags where (CGImageMetadataTagCopyPrefix(tag) as String?) == "apple_desktop" {
            guard let name = CGImageMetadataTagCopyName(tag) as String?,
                  let value = CGImageMetadataTagCopyValue(tag) as? String,
                  let schedule = WallpaperSchedule(tag: name, base64: value) else { continue }
            return schedule
        }
        return nil
    }

    private static func currentLocation() -> GeoCoordinate {
        let zone = TimeZone.current
        if let table = try? String(contentsOfFile: "/usr/share/zoneinfo/zone.tab", encoding: .utf8),
           let location = GeoCoordinate(zoneTab: table, timeZoneIdentifier: zone.identifier) {
            return location
        }
        return GeoCoordinate(latitude: 40, longitude: Double(zone.secondsFromGMT()) / 240)
    }
}
