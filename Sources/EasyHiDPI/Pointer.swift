import AppKit
import CoreGraphics

@MainActor
enum Pointer {
    /// Moves the pointer by a distance in view points, y down, so it stays on what it holds when the
    /// map zooms under it.
    static func move(by offset: CGSize) {
        guard offset != .zero, let primary = NSScreen.screens.first else { return }
        let location = NSEvent.mouseLocation
        CGWarpMouseCursorPosition(CGPoint(
            x: location.x + offset.width,
            y: primary.frame.maxY - location.y + offset.height
        ))
        // Without this the pointer ignores the mouse for a quarter of a second after a warp.
        CGAssociateMouseAndMouseCursorPosition(1)
    }
}
