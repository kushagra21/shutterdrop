// Draws Shutterdrop's app icon from geometric primitives (no fonts, symbols or
// images) and writes assets/AppIcon.icns plus assets/icon-256.png.
//
// Usage: swift scripts/make-icon.swift   (from the repository root)

import AppKit
import CoreGraphics

let canvas: CGFloat = 1024
/// Apple's macOS icon grid: an 824 pt rounded square centred on a 1024 canvas.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tileCorner: CGFloat = 185

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

// Deep teal to indigo: clear of Sony's orange and of Drupal's blue drop.
let backgroundTop = rgb(0x0E9F9A)
let backgroundBottom = rgb(0x312E81)
let bladeTop = rgb(0x0F8C89)
let bladeBottom = rgb(0x3B3A9E)

/// A drop: round bottom centred at `centre`, point at the top.
func dropPath(centre c: CGPoint, radius r: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let tip = CGPoint(x: c.x, y: c.y - 1.75 * r)
    path.move(to: tip)
    path.addCurve(to: CGPoint(x: c.x + r, y: c.y),
                  control1: CGPoint(x: c.x + 0.25 * r, y: c.y - 1.25 * r), control2: CGPoint(x: c.x + r, y: c.y - 0.75 * r))
    path.addArc(center: c, radius: r, startAngle: 0, endAngle: .pi, clockwise: false)
    path.addCurve(to: tip,
                  control1: CGPoint(x: c.x - r, y: c.y - 0.75 * r), control2: CGPoint(x: c.x - 0.25 * r, y: c.y - 1.25 * r))
    path.closeSubpath()
    return path
}

/// A six-blade lens iris: a gradient disc cut by blade seams, with an open hexagonal centre.
func drawIris(_ ctx: CGContext, centre c: CGPoint, radius r: CGFloat, opening: CGFloat, seam: CGColor) {
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    ctx.clip()
    let blades = CGGradient(colorsSpace: nil, colors: [bladeTop, bladeBottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(blades, start: CGPoint(x: c.x, y: c.y - r), end: CGPoint(x: c.x, y: c.y + r), options: [])

    let corners = (0..<6).map { i -> CGPoint in
        let angle = CGFloat(i) * .pi / 3 - .pi / 2
        return CGPoint(x: c.x + opening * cos(angle), y: c.y + opening * sin(angle))
    }
    // Each seam starts at a corner of the opening and runs along the next edge, past the rim.
    ctx.setStrokeColor(seam)
    ctx.setLineWidth(r * 0.06)
    ctx.setLineCap(.round)
    for i in 0..<6 {
        let a = corners[i], b = corners[(i + 1) % 6]
        let length = hypot(b.x - a.x, b.y - a.y)
        ctx.move(to: a)
        ctx.addLine(to: CGPoint(x: a.x + (b.x - a.x) / length * r * 2.2, y: a.y + (b.y - a.y) / length * r * 2.2))
    }
    ctx.strokePath()
    ctx.setFillColor(seam)
    ctx.addLines(between: corners)
    ctx.closePath()
    ctx.fillPath()
    ctx.restoreGState()
}

func drawIcon(_ ctx: CGContext) {
    let tilePath = CGPath(roundedRect: tile, cornerWidth: tileCorner, cornerHeight: tileCorner, transform: nil)

    // Tile with a soft drop shadow, as macOS icons have.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 24, color: rgb(0x000000, 0.3))
    ctx.addPath(tilePath)
    ctx.setFillColor(backgroundBottom)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    let background = CGGradient(colorsSpace: nil, colors: [backgroundTop, backgroundBottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(background, start: CGPoint(x: tile.midX, y: tile.minY), end: CGPoint(x: tile.midX, y: tile.maxY), options: [])
    ctx.restoreGState()

    // The drop, with the iris inside.
    let centre = CGPoint(x: 512, y: 590)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 14), blur: 30, color: rgb(0x000000, 0.28))
    ctx.addPath(dropPath(centre: centre, radius: 235))
    ctx.setFillColor(rgb(0xFFFFFF))
    ctx.fillPath()
    ctx.restoreGState()
    drawIris(ctx, centre: centre, radius: 160, opening: 58, seam: rgb(0xFFFFFF))
}

func png(pixels: Int) -> Data {
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let scale = CGFloat(pixels) / canvas
    ctx.translateBy(x: 0, y: CGFloat(pixels))
    ctx.scaleBy(x: scale, y: -scale)  // draw in a 1024 top-left canvas at any size
    drawIcon(ctx)
    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}

let assets = URL(filePath: FileManager.default.currentDirectoryPath).appending(path: "assets")
let iconset = FileManager.default.temporaryDirectory.appending(path: "AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)

for points in [16, 32, 128, 256, 512] {
    try png(pixels: points).write(to: iconset.appending(path: "icon_\(points)x\(points).png"))
    try png(pixels: points * 2).write(to: iconset.appending(path: "icon_\(points)x\(points)@2x.png"))
}
try png(pixels: 256).write(to: assets.appending(path: "icon-256.png"))

let iconutil = Process()
iconutil.executableURL = URL(filePath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", assets.appending(path: "AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Wrote assets/AppIcon.icns and assets/icon-256.png")
