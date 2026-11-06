import AppKit

/// The app's mark at menu bar size: one coarse pixel, the four fine pixels it becomes, and a stand.
/// A template image, so the system tints it; the coordinates sit on the 2x pixel grid to stay crisp.
enum StatusIcon {
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.withAlphaComponent(0.5).setFill()
            NSBezierPath(roundedRect: NSRect(x: 1, y: 6, width: 7, height: 7), xRadius: 1.5, yRadius: 1.5).fill()

            NSColor.black.setFill()
            for x in [9.0, 13.0] {
                for y in [6.0, 10.0] {
                    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 3, height: 3), xRadius: 0.75, yRadius: 0.75).fill()
                }
            }
            NSBezierPath(roundedRect: NSRect(x: 6, y: 2.5, width: 6, height: 1.5), xRadius: 0.75, yRadius: 0.75).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "EasyHiDPI"
        return image
    }
}
