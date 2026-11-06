#!/usr/bin/env swift

// Usage: generate-app-icon.swift [--png <path>]
// Writes Packaging/AppIcon.icns, and a 1024px PNG when asked for one.

import AppKit

let projectRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let outputURL = projectRoot.appendingPathComponent("Packaging/AppIcon.icns")

func srgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

/// A superellipse: the continuous-corner shape macOS icons use, which a plain rounded rect only approximates.
func squircle(in rect: CGRect) -> NSBezierPath {
    let exponent: CGFloat = 5
    let path = NSBezierPath()
    for step in 0..<720 {
        let angle = CGFloat(step) / 720 * 2 * .pi
        let cosine = cos(angle)
        let sine = sin(angle)
        let x = pow(abs(cosine), 2 / exponent) * (cosine < 0 ? -1 : 1) * rect.width / 2 + rect.midX
        let y = pow(abs(sine), 2 / exponent) * (sine < 0 ? -1 : 1) * rect.height / 2 + rect.midY
        if step == 0 {
            path.move(to: CGPoint(x: x, y: y))
        } else {
            path.line(to: CGPoint(x: x, y: y))
        }
    }
    path.close()
    return path
}

func fillTile(_ rect: CGRect, radius: CGFloat, alpha: CGFloat) {
    NSColor.white.withAlphaComponent(alpha).setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

/// One coarse pixel beside the four fine pixels it becomes, standing as a display: HiDPI in one picture.
/// Drawn in a 1024-unit space on Apple's icon grid, an 824-unit tile inset by 100.
func drawIcon(pixels: Int) {
    let scale = CGFloat(pixels) / 1024
    let transform = NSAffineTransform()
    transform.scale(by: scale)
    transform.concat()

    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = squircle(in: tile)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowOffset = NSSize(width: 0, height: -10 * scale)
    shadow.shadowBlurRadius = 28 * scale
    shadow.set()
    srgb(30, 79, 214).setFill()
    tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(starting: srgb(84, 148, 255), ending: srgb(28, 74, 208))!.draw(in: tilePath, angle: -90)

    NSGraphicsContext.saveGraphicsState()
    tilePath.addClip()
    tilePath.lineWidth = 6
    NSColor.white.withAlphaComponent(0.2).setStroke()
    tilePath.stroke()
    NSGraphicsContext.restoreGraphicsState()

    let small: CGFloat = 118
    let gap: CGFloat = 26
    let large = small * 2 + gap
    let screenWidth = large * 2 + gap
    let left = 512 - screenWidth / 2
    let standHeight: CGFloat = 24
    let standGap: CGFloat = 44
    let bottom = 512 - (large + standGap + standHeight) / 2
    let screenBottom = bottom + standHeight + standGap

    fillTile(CGRect(x: left, y: screenBottom, width: large, height: large), radius: 34, alpha: 0.42)

    let fineLeft = left + large + gap
    for column in 0..<2 {
        for row in 0..<2 {
            let origin = CGPoint(
                x: fineLeft + CGFloat(column) * (small + gap),
                y: screenBottom + CGFloat(row) * (small + gap)
            )
            fillTile(CGRect(origin: origin, size: CGSize(width: small, height: small)), radius: 18, alpha: 1)
        }
    }

    fillTile(CGRect(x: 512 - 90, y: bottom, width: 180, height: standHeight), radius: 12, alpha: 1)
}

func render(pixels: Int) -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fatalError("cannot create icon bitmap")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    drawIcon(pixels: pixels)
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("cannot encode icon")
    }
    return png
}

let arguments = CommandLine.arguments
if let flag = arguments.firstIndex(of: "--png"), arguments.indices.contains(flag + 1) {
    try render(pixels: 1024).write(to: URL(fileURLWithPath: arguments[flag + 1]))
}

let fileManager = FileManager.default
let iconset = fileManager.temporaryDirectory.appendingPathComponent("EasyHiDPI-\(UUID().uuidString).iconset")
try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? fileManager.removeItem(at: iconset) }

for points in [16, 32, 128, 256, 512] {
    try render(pixels: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try render(pixels: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", outputURL.path]
try iconutil.run()
iconutil.waitUntilExit()
if iconutil.terminationStatus != 0 {
    exit(iconutil.terminationStatus)
}
