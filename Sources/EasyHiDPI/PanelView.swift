import EasyHiDPICore
import SwiftUI

private enum Metrics {
    static let panelWidth: CGFloat = 340
    static let panelRadius: CGFloat = 18
    static let padding: CGFloat = 14
    static let mapHeight: CGFloat = 116
    static let controlRadius: CGFloat = 8
    static let chipHeight: CGFloat = 28
}

struct PanelView: View {
    let store: DisplayStore
    let onSizeChange: (CGSize) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let message = store.errorMessage {
                ErrorBanner(message: message) { store.errorMessage = nil }
            }
            DisplayMap(store: store)
            if let display = store.selected {
                DisplayControls(store: store, display: display)
                    .id(display.id)
            }
            Footer(store: store)
        }
        .padding(Metrics.padding)
        .frame(width: Metrics.panelWidth)
        .fixedSize(horizontal: false, vertical: true)
        .background(PanelBackground(cornerRadius: Metrics.panelRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.panelRadius)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        }
        .onGeometryChange(for: CGSize.self, of: \.size) { onSizeChange($0) }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Map

/// Converts between global display points and the map's own coordinates.
private struct MapLayout {
    let scale: CGFloat
    let origin: CGPoint

    init?(extent: CGRect, size: CGSize) {
        guard !extent.isNull, extent.width > 0, extent.height > 0, size.width > 0, size.height > 0 else { return nil }
        let scale = min(size.width / extent.width, size.height / extent.height)
        self.scale = scale
        origin = CGPoint(
            x: (size.width - extent.width * scale) / 2 - extent.minX * scale,
            y: (size.height - extent.height * scale) / 2 - extent.minY * scale
        )
    }

    func frame(for bounds: CGRect) -> CGRect {
        CGRect(
            x: bounds.minX * scale + origin.x,
            y: bounds.minY * scale + origin.y,
            width: bounds.width * scale,
            height: bounds.height * scale
        )
    }

    func globalPoint(fromMap point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - origin.x) / scale, y: (point.y - origin.y) / scale)
    }
}

private struct TileDrag {
    let id: CGDirectDisplayID
    let size: CGSize
    /// Where the cursor holds the tile, as a fraction of its size, so it stays under the cursor when the map zooms.
    let grab: CGPoint
    /// Zoomed out and frozen for the whole drag, with room for the tile on every side.
    let layout: MapLayout
    var proposed: CGPoint
    var snapped: CGPoint
}

/// The displays as System Settings arranges them: position and size are live workspace points, so
/// a tile grows when a larger size is chosen and dims with its brightness. Extended displays can
/// be dragged around the main display, which stays fixed at the origin.
private struct DisplayMap: View {
    let store: DisplayStore

    @State private var drag: TileDrag?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let space = "map"
    private static let tileGap: CGFloat = 3
    private static let alignmentReach: CGFloat = 8

    private var settleAnimation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.25)
    }

    var body: some View {
        GeometryReader { proxy in
            let extent = store.displays.reduce(CGRect.null) { $0.union(store.bounds(of: $1)) }
            if let fitted = MapLayout(extent: extent, size: proxy.size) {
                let layout = drag?.layout ?? fitted

                ForEach(store.displays) { display in
                    let frame = tileFrame(of: display, in: layout)
                    let isDragged = drag?.id == display.id
                    DisplayTile(
                        display: display,
                        activeSize: store.activeSize(of: display),
                        brightness: store.readings[display.id],
                        wallpaper: store.wallpaper(of: display),
                        isSelected: store.isSelected(display),
                        showsLabel: drag == nil
                    ) {
                        store.select(display)
                    }
                    .frame(width: max(frame.width - Self.tileGap, 1), height: max(frame.height - Self.tileGap, 1))
                    .opacity(isDragged ? 0.85 : 1)
                    .shadow(color: .black.opacity(isDragged ? 0.35 : 0), radius: 6, y: 2)
                    .highPriorityGesture(
                        dragGesture(for: display, fitted: fitted, mapSize: proxy.size),
                        including: display.canMove ? .all : .subviews
                    )
                    .grabCursor(display.canMove, isDragging: isDragged)
                    .position(x: frame.midX, y: frame.midY)
                    .zIndex(isDragged ? 1 : 0)
                }

                if let drag {
                    let frame = layout.frame(for: CGRect(origin: drag.snapped, size: drag.size))
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .frame(width: max(frame.width - Self.tileGap, 1), height: max(frame.height - Self.tileGap, 1))
                        .position(x: frame.midX, y: frame.midY)
                        .allowsHitTesting(false)
                }
            }
        }
        .coordinateSpace(.named(Self.space))
        .frame(height: Metrics.mapHeight)
        .animation(settleAnimation, value: store.displays.map { store.bounds(of: $0) })
    }

    private func tileFrame(of display: PhysicalDisplay, in layout: MapLayout) -> CGRect {
        if let drag, drag.id == display.id {
            return layout.frame(for: CGRect(origin: drag.proposed, size: drag.size))
        }
        return layout.frame(for: store.bounds(of: display))
    }

    private func others(than display: PhysicalDisplay) -> [CGRect] {
        store.displays.filter { $0.id != display.id }.map { store.bounds(of: $0) }
    }

    private func dragGesture(for display: PhysicalDisplay, fitted: MapLayout, mapSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if drag?.id != display.id {
                    beginDrag(of: display, at: value.startLocation, fitted: fitted, mapSize: mapSize)
                }
                updateDrag(of: display, cursor: value.location)
            }
            .onEnded { _ in
                guard let finished = drag else { return }
                withAnimation(settleAnimation) {
                    drag = nil
                    store.move(display, to: finished.snapped)
                }
            }
    }

    private func beginDrag(of display: PhysicalDisplay, at start: CGPoint, fitted: MapLayout, mapSize: CGSize) {
        let bounds = store.bounds(of: display)
        let room = others(than: display)
            .reduce(CGRect.null) { $0.union($1) }
            .insetBy(dx: -bounds.width, dy: -bounds.height)
        guard let zoomed = MapLayout(extent: room, size: mapSize) else { return }

        let frame = fitted.frame(for: bounds)
        store.select(display)
        withAnimation(settleAnimation) {
            drag = TileDrag(
                id: display.id,
                size: bounds.size,
                grab: CGPoint(x: (start.x - frame.minX) / frame.width, y: (start.y - frame.minY) / frame.height),
                layout: zoomed,
                proposed: bounds.origin,
                snapped: bounds.origin
            )
        }
    }

    private func updateDrag(of display: PhysicalDisplay, cursor: CGPoint) {
        guard var current = drag else { return }
        let held = current.layout.globalPoint(fromMap: cursor)
        current.proposed = CGPoint(
            x: held.x - current.grab.x * current.size.width,
            y: held.y - current.grab.y * current.size.height
        )
        current.snapped = DisplayArrangement.snappedOrigin(
            of: store.bounds(of: display),
            proposed: current.proposed,
            others: others(than: display),
            alignmentTolerance: Self.alignmentReach / current.layout.scale
        )
        drag = current
    }
}

private extension View {
    @ViewBuilder
    func grabCursor(_ isEnabled: Bool, isDragging: Bool) -> some View {
        if isEnabled, #available(macOS 15.0, *) {
            pointerStyle(isDragging ? .grabActive : .grabIdle)
        } else {
            self
        }
    }
}

private struct DisplayTile: View {
    let display: PhysicalDisplay
    let activeSize: DisplaySize?
    let brightness: DDCReading?
    let wallpaper: CGImage?
    let isSelected: Bool
    let showsLabel: Bool
    let action: () -> Void

    @State private var isHovered = false

    private var lit: Double? {
        brightness.map { Double($0.current) / Double($0.maximum) }
    }

    private var label: String {
        (activeSize ?? display.catalog.current.size).label
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 5)
        Button(action: action) {
            ZStack(alignment: .top) {
                if let wallpaper {
                    Color.clear
                        .overlay {
                            Image(decorative: wallpaper, scale: 1)
                                .resizable()
                                .interpolation(.medium)
                                .scaledToFill()
                        }
                        .clipped()
                    Color.black.opacity((1 - (lit ?? 1)) * 0.65)
                    Color.white.opacity(isHovered ? 0.08 : 0)
                } else {
                    shape.fill(Color.primary.opacity(0.07 + 0.24 * (lit ?? 0.5) + (isHovered ? 0.04 : 0)))
                }
                if display.isMain {
                    Rectangle()
                        .fill(wallpaper == nil ? Color.primary.opacity(0.45) : Color.white.opacity(0.7))
                        .frame(height: 3)
                }
                if showsLabel {
                    Text(label)
                        .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(wallpaper == nil ? Color.primary : Color.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background {
                            if wallpaper != nil {
                                RoundedRectangle(cornerRadius: 3).fill(Color.black.opacity(0.42))
                            }
                        }
                        .padding(.horizontal, 2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .clipShape(shape)
            .overlay {
                if isSelected {
                    shape.strokeBorder(Color.accentColor, lineWidth: 1.5)
                } else if wallpaper != nil {
                    shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(display.name)
        .accessibilityLabel("\(display.name), \(label)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Controls

private struct DisplayControls: View {
    let store: DisplayStore
    let display: PhysicalDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(display.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                if display.isMain {
                    Text("Main")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if display.canMove {
                    Button("Set as Main") { store.makeMain(display) }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                if display.hasOverride {
                    OverrideMenu(store: store, display: display)
                }
            }
            if store.brightnessDisplays.contains(display.id) {
                BrightnessBar(reading: store.readings[display.id]) { value in
                    store.setBrightness(value, of: display.id)
                }
            }
            ModePicker(store: store, display: display)
        }
    }
}

private struct ModePicker: View {
    let store: DisplayStore
    let display: PhysicalDisplay

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var sizeLabel: String {
        (store.activeSize(of: display) ?? display.catalog.current.size).label
    }

    private var rateLabel: String? {
        let rate = store.activeRate(of: display)
        return rate > 0 ? ModeCatalog.rateLabel(rate) : nil
    }

    var body: some View {
        VStack(spacing: 6) {
            Button(action: toggle) {
                HStack(spacing: 8) {
                    Text(sizeLabel)
                        .font(.system(size: 12))
                        .monospacedDigit()
                    Spacer(minLength: 0)
                    if let rateLabel {
                        Text(rateLabel)
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(store.isModePickerExpanded ? 180 : 0))
                }
                .padding(.horizontal, 10)
                .frame(height: Metrics.chipHeight)
                .background {
                    RoundedRectangle(cornerRadius: Metrics.controlRadius)
                        .fill(Color.primary.opacity(isHovered ? 0.13 : 0.07))
                }
                .contentShape(RoundedRectangle(cornerRadius: Metrics.controlRadius))
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .accessibilityLabel("Mode")
            .accessibilityValue([sizeLabel, rateLabel].compactMap { $0 }.joined(separator: ", "))
            .accessibilityHint(store.isModePickerExpanded ? "Collapse" : "Expand")

            if store.isModePickerExpanded {
                VStack(spacing: 6) {
                    SizeGrid(store: store, display: display)
                    if display.catalog.rates.count > 1 {
                        Divider()
                        RateGrid(store: store, display: display)
                    }
                }
                .transition(.opacity)
            }
        }
    }

    private func toggle() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) {
            store.isModePickerExpanded.toggle()
            if !store.isModePickerExpanded { store.isAddingSize = false }
        }
    }
}

private struct OverrideMenu: View {
    let store: DisplayStore
    let display: PhysicalDisplay

    var body: some View {
        Menu {
            Button("Show Plist in Finder") { store.showPlist(of: display) }
            Menu("Remove") {
                ForEach(display.overrideSizes, id: \.self) { size in
                    Button(size.label) { store.removeSize(size, from: display) }
                }
                if !display.overrideSizes.isEmpty { Divider() }
                Button("Whole Override") { store.removeOverride(of: display) }
            }
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 22, height: 16)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Override")
    }
}

private struct BrightnessBar: View {
    let reading: DDCReading?
    let onChange: (Int) -> Void

    private var fraction: Double {
        guard let reading else { return 0 }
        return min(max(Double(reading.current) / Double(reading.maximum), 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.primary.opacity(0.07))
                Rectangle()
                    .fill(Color.primary.opacity(0.26))
                    .frame(width: proxy.size.width * fraction)
                HStack {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 10))
                    Spacer()
                    Text(reading.map { "\($0.current)" } ?? "")
                        .font(.system(size: 11))
                        .monospacedDigit()
                }
                .padding(.horizontal, 9)
                .foregroundStyle(.primary)
            }
            .clipShape(RoundedRectangle(cornerRadius: Metrics.controlRadius))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { value in
                    guard let reading, proxy.size.width > 0 else { return }
                    let position = min(max(value.location.x / proxy.size.width, 0), 1)
                    onChange(Int((position * Double(reading.maximum)).rounded()))
                }
            )
        }
        .frame(height: 26)
        .opacity(reading == nil ? 0.4 : 1)
        .allowsHitTesting(reading != nil)
        .accessibilityElement()
        .accessibilityLabel("Brightness")
        .accessibilityValue(reading.map { "\($0.current)" } ?? "")
        .accessibilityAdjustableAction { direction in
            guard let reading else { return }
            let step = max(reading.maximum / 10, 1)
            switch direction {
            case .increment: onChange(min(reading.current + step, reading.maximum))
            case .decrement: onChange(max(reading.current - step, 0))
            @unknown default: break
            }
        }
    }
}

private struct SizeGrid: View {
    let store: DisplayStore
    let display: PhysicalDisplay

    @Namespace private var selection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    var body: some View {
        let active = store.activeSize(of: display)
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(display.catalog.rows, id: \.size) { row in
                ModeChip(label: row.size.label, isPending: row.isPending, isActive: row.size == active, selection: selection) {
                    store.choose(row, on: display)
                }
            }
            AddSizeChip(store: store, display: display)
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: active)
    }
}

private struct RateGrid: View {
    let store: DisplayStore
    let display: PhysicalDisplay

    @Namespace private var selection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

    var body: some View {
        let active = store.activeRate(of: display)
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(display.catalog.rates, id: \.self) { rate in
                ModeChip(label: ModeCatalog.rateLabel(rate), isActive: ModeCatalog.sameRate(rate, active), selection: selection) {
                    store.chooseRate(rate, on: display)
                }
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: active)
    }
}

private struct ModeChip: View {
    let label: String
    var isPending = false
    let isActive: Bool
    let selection: Namespace.ID
    let action: () -> Void

    @State private var isHovered = false

    private var foreground: Color {
        if isActive { return .white }
        return isPending ? Color.secondary.opacity(0.7) : .primary
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.controlRadius)
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity, minHeight: Metrics.chipHeight)
                .background {
                    if isActive {
                        shape.fill(Color.accentColor)
                            .matchedGeometryEffect(id: "active", in: selection)
                    } else if isPending {
                        shape.strokeBorder(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    } else {
                        shape.fill(Color.primary.opacity(isHovered ? 0.13 : 0.07))
                    }
                }
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(isPending)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

private struct AddSizeChip: View {
    let store: DisplayStore
    let display: PhysicalDisplay

    @State private var text = ""
    @State private var isInvalid = false
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.controlRadius)
        if store.isAddingSize {
            TextField(display.catalog.current.size.label, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .focused($isFocused)
                .frame(maxWidth: .infinity, minHeight: Metrics.chipHeight)
                .background(shape.fill(Color.primary.opacity(0.07)))
                .overlay {
                    shape.strokeBorder(isInvalid ? Color.red : Color.accentColor, lineWidth: 1)
                }
                .onChange(of: text) { isInvalid = false }
                .onSubmit(submit)
                .onAppear {
                    text = ""
                    isInvalid = false
                    isFocused = true
                }
        } else {
            Button {
                store.isAddingSize = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: Metrics.chipHeight)
                    .background(shape.fill(Color.primary.opacity(isHovered ? 0.13 : 0.04)))
                    .contentShape(shape)
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .accessibilityLabel("Add Size")
        }
    }

    private func submit() {
        guard let size = DisplaySize(parsing: text) else {
            isInvalid = true
            return
        }
        store.isAddingSize = false
        store.addSize(size, to: display)
    }
}

// MARK: - Footer and errors

private struct Footer: View {
    let store: DisplayStore

    var body: some View {
        HStack(spacing: 12) {
            if store.isBundledApp {
                Toggle("Launch at Login", isOn: Binding(
                    get: { store.isLaunchAtLoginEnabled },
                    set: { store.setLaunchAtLogin($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
            }
            Spacer(minLength: 0)
            if store.hasOverridesFolder {
                Button("Overrides Folder") { store.openOverridesFolder() }
                    .buttonStyle(.plain)
            }
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }
}

private struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        Button(action: dismiss) {
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.red)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
