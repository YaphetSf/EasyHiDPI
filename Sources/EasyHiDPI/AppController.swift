import AppKit
import SwiftUI

@MainActor
final class AppController: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let store = DisplayStore()
    private let panel = StatusPanel()
    private var panelSize = NSSize(width: 340, height: 300)
    private var monitors: [Any] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let button = statusItem.button {
            button.image = StatusIcon.make()
            button.target = self
            button.action = #selector(togglePanel)
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        }

        let hosting = NSHostingView(rootView: PanelView(store: store) { [weak self] size in
            self?.panelResized(to: size)
        })
        hosting.sizingOptions = []
        panel.contentView = hosting

        store.onLeavePanel = { [weak self] in self?.closePanel() }
        store.start()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(spaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }

    @objc private func togglePanel() {
        if panel.isVisible {
            closePanel()
        } else {
            openPanel()
        }
    }

    @objc private func screensChanged() {
        store.screensChanged()
        if panel.isVisible { placePanel() }
    }

    @objc private func spaceChanged() {
        closePanel()
    }

    private func openPanel() {
        store.refresh()
        store.readAllBrightness()
        placePanel()

        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        statusItem.button?.highlight(true)
        installMonitors()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
    }

    private func closePanel() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        statusItem.button?.highlight(false)
        store.isAddingSize = false
        store.isModePickerExpanded = false
        removeMonitors()
    }

    private func panelResized(to size: CGSize) {
        guard size.width > 0, size.height > 0, size != panelSize else { return }
        panelSize = size
        if panel.isVisible { placePanel() }
    }

    private func placePanel() {
        guard let window = statusItem.button?.window, let screen = window.screen else { return }
        let area = screen.visibleFrame
        let centered = window.frame.midX - panelSize.width / 2
        let x = min(max(centered, area.minX + 8), area.maxX - panelSize.width - 8)
        let top = window.frame.minY - 6
        panel.setFrame(NSRect(x: x, y: top - panelSize.height, width: panelSize.width, height: panelSize.height), display: true)
        panel.invalidateShadow()
    }

    private func installMonitors() {
        removeMonitors()
        let outsideClick = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            let location = event.locationInWindow
            MainActor.assumeIsolated { self?.handleOutsideClick(at: location) }
        }
        let escape = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            MainActor.assumeIsolated { self?.handleEscape() }
            return nil
        }
        monitors = [outsideClick, escape].compactMap { $0 }
    }

    /// A click on the icon also reaches this monitor. Closing here would make the icon's own action
    /// reopen the panel, so the icon is left to toggle it. The inset covers the screen's very top edge.
    private func handleOutsideClick(at location: CGPoint) {
        if let icon = statusItem.button?.window?.frame, icon.insetBy(dx: -1, dy: -1).contains(location) { return }
        closePanel()
    }

    private func handleEscape() {
        if store.isAddingSize {
            store.isAddingSize = false
        } else {
            closePanel()
        }
    }

    private func removeMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
    }
}
