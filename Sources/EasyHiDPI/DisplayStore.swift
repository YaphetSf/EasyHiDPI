import AppKit
import EasyHiDPICore
import Observation
import ServiceManagement

@MainActor
@Observable
final class DisplayStore {
    private(set) var displays: [PhysicalDisplay] = []
    private(set) var readings: [CGDirectDisplayID: DDCReading] = [:]
    private(set) var brightnessDisplays: Set<CGDirectDisplayID> = []
    private(set) var isLaunchAtLoginEnabled = false
    private var selectedID: CGDirectDisplayID?
    private var switchingTo: [CGDirectDisplayID: DisplayModeInfo] = [:]
    private var movingTo: [CGDirectDisplayID: CGPoint] = [:]
    private var wallpapers: [WallpaperKey: CGImage] = [:]
    @ObservationIgnored private var requestedWallpapers = Set<WallpaperKey>()

    var errorMessage: String?
    var isAddingSize = false
    var isModePickerExpanded = false

    /// Called when an action hands the user over to another app.
    @ObservationIgnored var onLeavePanel: (() -> Void)?
    @ObservationIgnored private let bus = DDCBus()

    let isBundledApp = Bundle.main.bundleIdentifier != nil

    func start() {
        refresh()
        rebindBrightness()
        registerLoginItemOnFirstLaunch()
    }

    func refresh() {
        displays = SystemDisplays.all()
        if !displays.contains(where: { $0.id == selectedID }) {
            selectedID = displays.first(where: \.isMain)?.id ?? displays.first?.id
            isAddingSize = false
        }
        if isBundledApp {
            isLaunchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        }
        loadWallpapers()
    }

    func wallpaper(of display: PhysicalDisplay) -> CGImage? {
        guard let key = display.wallpaper else { return nil }
        // While a new frame decodes, the previous frame of the same file is a better stand-in than nothing.
        return wallpapers[key] ?? wallpapers.first { $0.key.url == key.url }?.value
    }

    private func loadWallpapers() {
        for key in Set(displays.compactMap(\.wallpaper)) where !requestedWallpapers.contains(key) {
            requestedWallpapers.insert(key)
            Task.detached(priority: .utility) { [weak self] in
                guard let image = Wallpaper.thumbnail(for: key) else { return }
                await self?.finishLoadingWallpaper(image, for: key)
            }
        }
    }

    private func finishLoadingWallpaper(_ image: CGImage, for key: WallpaperKey) {
        let wanted = Set(displays.compactMap(\.wallpaper))
        wallpapers = wallpapers.filter { wanted.contains($0.key) }
        wallpapers[key] = image
        requestedWallpapers.formIntersection(wanted.union([key]))
    }

    func screensChanged() {
        refresh()
        rebindBrightness()
    }

    var selected: PhysicalDisplay? {
        displays.first { $0.id == selectedID }
    }

    func select(_ display: PhysicalDisplay) {
        guard display.id != selectedID else { return }
        selectedID = display.id
        isAddingSize = false
    }

    func isSelected(_ display: PhysicalDisplay) -> Bool {
        display.id == selectedID
    }

    // MARK: Mode

    func activeSize(of display: PhysicalDisplay) -> DisplaySize? {
        if let target = switchingTo[display.id], target.isHiDPI { return target.size }
        return display.catalog.rows.first(where: \.isCurrent)?.size
    }

    func activeRate(of display: PhysicalDisplay) -> Double {
        switchingTo[display.id]?.refreshRate ?? display.catalog.current.refreshRate
    }

    func choose(_ row: SizeRow, on display: PhysicalDisplay) {
        guard !row.isCurrent, let target = display.catalog.target(for: row) else { return }
        apply(target, on: display, named: row.size.label)
    }

    func chooseRate(_ rate: Double, on display: PhysicalDisplay) {
        guard let target = display.catalog.target(forRate: rate),
              target.id != display.catalog.current.id else { return }
        apply(target, on: display, named: ModeCatalog.rateLabel(rate))
    }

    /// The highlight moves first: applying a mode blocks while the display reconfigures.
    private func apply(_ target: DisplayModeInfo, on display: PhysicalDisplay, named name: String) {
        guard let mode = display.rawModes[target.id] else { return }
        switchingTo[display.id] = target
        DispatchQueue.main.async { [self] in
            let result = SystemDisplays.apply(mode, to: display.id)
            switchingTo[display.id] = nil
            if result != .success {
                errorMessage = "Could not switch \(display.name) to \(name) (error \(result.rawValue))."
            }
            refresh()
        }
    }

    // MARK: Arrangement

    func bounds(of display: PhysicalDisplay) -> CGRect {
        guard let origin = movingTo[display.id] else { return display.bounds }
        return CGRect(origin: origin, size: display.bounds.size)
    }

    /// The tile settles first; applying the arrangement makes the displays blink.
    func move(_ display: PhysicalDisplay, to origin: CGPoint) {
        guard display.canMove, origin != display.bounds.origin else { return }
        movingTo[display.id] = origin
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [self] in
            let result = SystemDisplays.move(display.id, to: origin)
            movingTo[display.id] = nil
            if result != .success {
                errorMessage = "Could not move \(display.name) (error \(result.rawValue))."
            }
            refresh()
        }
    }

    func makeMain(_ display: PhysicalDisplay) {
        guard display.canMove else { return }
        let all = displays
        DispatchQueue.main.async { [self] in
            let result = SystemDisplays.makeMain(display.id, among: all)
            if result != .success {
                errorMessage = "Could not make \(display.name) the main display (error \(result.rawValue))."
            }
            refresh()
        }
    }

    // MARK: Brightness

    func readAllBrightness() {
        for id in brightnessDisplays {
            bus.readBrightness(id) { [weak self] reading in
                self?.readings[id] = reading
            }
        }
    }

    func setBrightness(_ value: Int, of id: CGDirectDisplayID) {
        if let reading = readings[id] {
            readings[id] = DDCReading(current: value, maximum: reading.maximum)
        }
        bus.setBrightness(id, to: value)
    }

    private func rebindBrightness() {
        let targets = displays.map { (id: $0.id, identity: $0.edidIdentity) }
        bus.rebind(targets) { [weak self] bound in
            self?.brightnessDisplays = bound
            self?.readAllBrightness()
        }
    }

    // MARK: Overrides

    func addSize(_ size: DisplaySize, to display: PhysicalDisplay) {
        do {
            var file: OverrideFile
            if let existing = try OverrideInstaller.load(display.identity) {
                file = existing
            } else {
                file = OverrideFile(id: display.identity)
                // A new override should not cost the display the mode it is using right now.
                let current = display.catalog.current
                if current.isHiDPI { file.add(current.size.oriented(rotationDegrees: display.rotation)) }
            }
            file.add(size.oriented(rotationDegrees: display.rotation))
            install(file, for: display)
        } catch {
            errorMessage = "Could not read the override for \(display.name): \(error.localizedDescription)"
        }
    }

    func removeSize(_ size: DisplaySize, from display: PhysicalDisplay) {
        do {
            guard var file = try OverrideInstaller.load(display.identity) else { return }
            file.remove(size.oriented(rotationDegrees: display.rotation))
            if file.sizes.isEmpty {
                removeOverride(of: display)
            } else {
                install(file, for: display)
            }
        } catch {
            errorMessage = "Could not read the override for \(display.name): \(error.localizedDescription)"
        }
    }

    func removeOverride(of display: PhysicalDisplay) {
        OverrideInstaller.remove(for: display.identity) { [weak self] result in
            self?.finish(result)
        }
    }

    func showPlist(of display: PhysicalDisplay) {
        let url = URL(fileURLWithPath: OverrideLocation.file(for: display.identity))
        NSWorkspace.shared.activateFileViewerSelecting([url])
        onLeavePanel?()
    }

    var hasOverridesFolder: Bool {
        FileManager.default.fileExists(atPath: OverrideLocation.root)
    }

    func openOverridesFolder() {
        NSWorkspace.shared.open(URL(fileURLWithPath: OverrideLocation.root))
        onLeavePanel?()
    }

    private func install(_ file: OverrideFile, for display: PhysicalDisplay) {
        OverrideInstaller.install(file, for: display.identity) { [weak self] result in
            self?.finish(result)
        }
    }

    private func finish(_ result: OverrideInstallerResult) {
        if case let .failure(message) = result {
            errorMessage = message
        }
        refresh()
    }

    // MARK: Login item

    func setLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if !enabled {
                try service.unregister()
            } else if service.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
                onLeavePanel?()
            } else {
                try service.register()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }

    /// Runs once so that turning the option off later sticks.
    private func registerLoginItemOnFirstLaunch() {
        let key = "didRegisterLoginItem"
        guard isBundledApp, !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        try? SMAppService.mainApp.register()
        refresh()
    }
}
