import EasyHiDPICore

/// `--list` prints what the panel would show, plus how each display is connected, so the real code
/// path and the reason a display is limited can be checked without opening it.
@MainActor
func printDisplayList() {
    let displays = SystemDisplays.all()
    let bus = DDCBus()
    _ = bus.rebind(displays.map { ($0.id, $0.edidIdentity) })
    let links = matchEndpoints(
        displays: displays.map { (id: $0.id, identity: $0.edidIdentity) },
        endpoints: DisplayLinks.all().compactMap { link in link.identity.map { (identity: $0, endpoint: link) } }
    )

    for display in displays {
        let catalog = display.catalog
        let current = catalog.current
        print("\(display.name) \(display.identity.label) rotation \(display.rotation)")
        print("  origin \(Int(display.bounds.minX)),\(Int(display.bounds.minY))\(display.canMove ? "" : " fixed")")
        print("  current \(current.size.label) pixels \(current.pixels.label) \(ModeCatalog.rateLabel(current.refreshRate))")
        print("  rates \(labels(catalog.rates))")
        if let link = links[display.id] {
            print("  link \(link.label)")
            print("  edid \(link.edidHex)")
        }
        if let reading = bus.readBrightness(display.id) {
            print("  brightness \(reading.current)/\(reading.maximum)")
        } else {
            print("  brightness unavailable")
        }
        for row in catalog.rows {
            let mark = row.isCurrent ? "*" : row.isPending ? "~" : " "
            print("  \(mark) \(row.size.label) \(labels(catalog.rates(for: row)))")
        }
        if display.hasOverride {
            print("  plist \(OverrideLocation.file(for: display.identity))")
        }
        if let wallpaper = display.wallpaper {
            let thumbnail = Wallpaper.thumbnail(for: wallpaper)
            let size = thumbnail.map { "\($0.width)x\($0.height)" } ?? "unreadable"
            print("  wallpaper \(wallpaper.url.lastPathComponent) frame \(wallpaper.frame) \(size)")
        }
    }
}

private func labels(_ rates: [Double]) -> String {
    rates.map(ModeCatalog.rateLabel).joined(separator: " ")
}
