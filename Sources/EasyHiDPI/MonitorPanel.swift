import CoreGraphics
import Foundation

/// System Settings' private display framework. macOS has no public call that rotates a display, and
/// the IOKit framebuffer probe older tools used does nothing on Apple silicon. If an update renames
/// these selectors, rotation simply becomes unavailable.
@MainActor
enum MonitorPanel {
    private typealias DisplayWithID = @convention(c) (NSObject, Selector, Int32) -> NSObject?
    private typealias BoolGetter = @convention(c) (NSObject, Selector) -> Bool
    private typealias IntSetter = @convention(c) (NSObject, Selector, Int32) -> Void

    private static let displayWithID = NSSelectorFromString("displayWithID:")
    private static let canChangeOrientation = NSSelectorFromString("canChangeOrientation")
    private static let setOrientation = NSSelectorFromString("setOrientation:")

    private static let manager: NSObject? = {
        guard dlopen("/System/Library/PrivateFrameworks/MonitorPanel.framework/MonitorPanel", RTLD_NOW) != nil,
              let type = NSClassFromString("MPDisplayMgr") as? NSObject.Type,
              type.responds(to: NSSelectorFromString("sharedMgr")) else { return nil }
        return type.perform(NSSelectorFromString("sharedMgr"))?.takeUnretainedValue() as? NSObject
    }()

    static func canRotate(_ id: CGDirectDisplayID) -> Bool {
        guard let display = display(id), display.responds(to: setOrientation),
              display.responds(to: canChangeOrientation) else { return false }
        let getter = unsafeBitCast(display.method(for: canChangeOrientation), to: BoolGetter.self)
        return getter(display, canChangeOrientation)
    }

    /// Returns before macOS reports the new rotation: that arrives with the next screen change.
    static func rotate(_ id: CGDirectDisplayID, to degrees: Int) {
        guard canRotate(id), let display = display(id) else { return }
        let setter = unsafeBitCast(display.method(for: setOrientation), to: IntSetter.self)
        setter(display, setOrientation, Int32(degrees))
    }

    private static func display(_ id: CGDirectDisplayID) -> NSObject? {
        guard let manager, manager.responds(to: displayWithID) else { return nil }
        let lookup = unsafeBitCast(manager.method(for: displayWithID), to: DisplayWithID.self)
        return lookup(manager, displayWithID, Int32(bitPattern: id))
    }
}
