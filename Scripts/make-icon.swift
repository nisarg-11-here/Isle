// Draws the Isle app icon and writes Resources/AppIcon.icns and Resources/icon.png.
// Run: swift Scripts/make-icon.swift
import AppKit

let size: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let green = NSColor(red: 0.19, green: 0.82, blue: 0.35, alpha: 1)
let orange = NSColor(red: 1.0, green: 0.62, blue: 0.04, alpha: 1)

// Apple's grid: an 824 pt body with a 185 pt corner radius, centered.
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let squircle = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
NSGradient(starting: NSColor(red: 0.17, green: 0.17, blue: 0.21, alpha: 1),
           ending: NSColor(red: 0.04, green: 0.04, blue: 0.06, alpha: 1))!.draw(in: squircle, angle: -90)
NSColor.white.withAlphaComponent(0.08).setStroke()
squircle.lineWidth = 4
squircle.stroke()

// The island, near the top.
let island = NSRect(x: 252, y: 680, width: 520, height: 140)
NSColor.black.setFill()
NSBezierPath(roundedRect: island, xRadius: 70, yRadius: 70).fill()
let track = NSBezierPath(ovalIn: NSRect(x: 300, y: 720, width: 60, height: 60))
track.lineWidth = 14
NSColor.white.withAlphaComponent(0.15).setStroke()
track.stroke()
let ring = NSBezierPath()
ring.appendArc(withCenter: NSPoint(x: 330, y: 750), radius: 30, startAngle: 90, endAngle: -160, clockwise: true)
ring.lineWidth = 14
ring.lineCapStyle = .round
green.setStroke()
ring.stroke()
orange.setFill()
NSBezierPath(ovalIn: NSRect(x: 672, y: 728, width: 44, height: 44)).fill()

// Three rows: the first one done.
for (i, y) in [520.0, 400.0, 280.0].enumerated() {
    let circle = NSRect(x: 240, y: y, width: 76, height: 76)
    if i == 0 {
        green.setFill()
        NSBezierPath(ovalIn: circle).fill()
        let check = NSBezierPath()
        check.move(to: NSPoint(x: 258, y: y + 38))
        check.line(to: NSPoint(x: 272, y: y + 22))
        check.line(to: NSPoint(x: 299, y: y + 54))
        check.lineWidth = 12
        check.lineCapStyle = .round
        check.lineJoinStyle = .round
        NSColor.black.setStroke()
        check.stroke()
    } else {
        let outline = NSBezierPath(ovalIn: circle.insetBy(dx: 5, dy: 5))
        outline.lineWidth = 10
        NSColor.white.withAlphaComponent(0.45).setStroke()
        outline.stroke()
    }
    let width: CGFloat = [300, 400, 250][i]
    NSColor.white.withAlphaComponent(i == 0 ? 0.3 : 0.85).setFill()
    NSBezierPath(roundedRect: NSRect(x: 350, y: y + 24, width: width, height: 28), xRadius: 14, yRadius: 14).fill()
}

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let resources = root.appendingPathComponent("Resources")
try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
let png = resources.appendingPathComponent("icon.png")
try rep.representation(using: .png, properties: [:])!.write(to: png)

// Build the .icns with sips and iconutil.
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
func run(_ tool: String, _ args: [String]) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: tool)
    p.arguments = args
    p.standardOutput = FileHandle.nullDevice
    try! p.run()
    p.waitUntilExit()
}
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let px = String(base * scale)
        run("/usr/bin/sips", ["-z", px, px, png.path, "--out", iconset.appendingPathComponent(name).path])
    }
}
run("/usr/bin/iconutil", ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path])
print("wrote Resources/icon.png and Resources/AppIcon.icns")
