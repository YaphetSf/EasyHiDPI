import AppKit
import CoreGraphics
import EasyHiDPICore

struct PhysicalDisplay: Identifiable {
    let id: CGDirectDisplayID
    let name: String
    let identity: DisplayIdentity
    let serial: UInt32
    let rotation: Int
    /// In global display points with the origin at the top left, as System Settings arranges them.
    let bounds: CGRect
    let isMain: Bool
    /// The main display is the fixed reference every other display is arranged around.
    let canMove: Bool
    let catalog: ModeCatalog
    let rawModes: [Int32: CGDisplayMode]
    /// In display orientation, matching what the menu shows.
    let overrideSizes: [DisplaySize]
    let hasOverride: Bool
    let wallpaper: WallpaperKey?

    var edidIdentity: EDIDIdentity { EDIDIdentity(display: identity, serial: serial) }
}

@MainActor
enum SystemDisplays {
    private static let nativeFlag: UInt32 = 0x0200_0000

    static func all() -> [PhysicalDisplay] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(16, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }

        return ids
            .sorted { CGDisplayBounds($0).origin.x < CGDisplayBounds($1).origin.x }
            .compactMap(display)
    }

    static func apply(_ mode: CGDisplayMode, to id: CGDirectDisplayID) -> CGError {
        configure { CGConfigureDisplayWithDisplayMode($0, id, mode, nil) }
    }

    static func move(_ id: CGDirectDisplayID, to origin: CGPoint) -> CGError {
        configure { CGConfigureDisplayOrigin($0, id, Int32(origin.x), Int32(origin.y)) }
    }

    static func makeMain(_ id: CGDirectDisplayID, among displays: [PhysicalDisplay]) -> CGError {
        let origins = Dictionary(uniqueKeysWithValues: displays.map { ($0.id, $0.bounds.origin) })
        let updated = DisplayArrangement.originsMakingMain(id, from: origins)
        return configure { configuration in
            for (display, origin) in updated {
                let result = CGConfigureDisplayOrigin(configuration, display, Int32(origin.x), Int32(origin.y))
                if result != .success { return result }
            }
            return .success
        }
    }

    private static func configure(_ change: (CGDisplayConfigRef) -> CGError) -> CGError {
        var configuration: CGDisplayConfigRef?
        let begun = CGBeginDisplayConfiguration(&configuration)
        guard begun == .success, let configuration else { return begun }
        let changed = change(configuration)
        guard changed == .success else {
            CGCancelDisplayConfiguration(configuration)
            return changed
        }
        return CGCompleteDisplayConfiguration(configuration, .permanently)
    }

    private static func display(_ id: CGDirectDisplayID) -> PhysicalDisplay? {
        guard let current = CGDisplayCopyDisplayMode(id) else { return nil }
        // Without this option the list hides HiDPI modes that share a size with a low-resolution one.
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue!] as CFDictionary
        let modes = (CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode] ?? [])
            .filter { $0.isUsableForDesktopGUI() }

        let identity = DisplayIdentity(vendor: CGDisplayVendorNumber(id), product: CGDisplayModelNumber(id))
        let rotation = Int(CGDisplayRotation(id))
        let overrideFile = try? OverrideInstaller.load(identity)
        let overrideSizes = (overrideFile ?? nil)?.sizes.map { $0.oriented(rotationDegrees: rotation) } ?? []
        return PhysicalDisplay(
            id: id,
            name: name(of: id) ?? identity.label,
            identity: identity,
            serial: CGDisplaySerialNumber(id),
            rotation: rotation,
            bounds: CGDisplayBounds(id),
            isMain: CGDisplayIsMain(id) != 0,
            canMove: CGDisplayIsMain(id) == 0 && CGDisplayIsInMirrorSet(id) == 0,
            catalog: ModeCatalog(modes: modes.map(info), current: info(current), overrideSizes: overrideSizes),
            rawModes: Dictionary(modes.map { ($0.ioDisplayModeID, $0) }, uniquingKeysWith: { first, _ in first }),
            overrideSizes: overrideSizes,
            hasOverride: FileManager.default.fileExists(atPath: OverrideLocation.file(for: identity)),
            wallpaper: screen(of: id)
                .flatMap { NSWorkspace.shared.desktopImageURL(for: $0) }
                .map { Wallpaper.key(for: $0) }
        )
    }

    private static func info(_ mode: CGDisplayMode) -> DisplayModeInfo {
        DisplayModeInfo(
            id: mode.ioDisplayModeID,
            size: DisplaySize(width: mode.width, height: mode.height),
            pixels: DisplaySize(width: mode.pixelWidth, height: mode.pixelHeight),
            refreshRate: mode.refreshRate,
            isNative: mode.ioFlags & nativeFlag != 0
        )
    }

    private static func name(of id: CGDirectDisplayID) -> String? {
        screen(of: id)?.localizedName
    }

    private static func screen(of id: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }
    }
}
