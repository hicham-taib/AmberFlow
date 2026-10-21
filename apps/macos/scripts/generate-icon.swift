import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else { fatalError("Usage: swift generate-icon.swift <output.iconset>") }
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let sizes: [(String, Int)] = [("icon_16x16.png",16),("icon_16x16@2x.png",32),("icon_32x32.png",32),("icon_32x32@2x.png",64),("icon_128x128.png",128),("icon_128x128@2x.png",256),("icon_256x256.png",256),("icon_256x256@2x.png",512),("icon_512x512.png",512),("icon_512x512@2x.png",1024)]

func icon(_ n: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: n, pixelsHigh: n, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
    let s = CGFloat(n); let b = NSRect(x: 0, y: 0, width: s, height: s)
    NSColor.clear.setFill(); b.fill()
    let plate = NSBezierPath(roundedRect: b.insetBy(dx: s * 0.055, dy: s * 0.055), xRadius: s * 0.24, yRadius: s * 0.24)
    NSColor(deviceRed: 0.12, green: 0.07, blue: 0.05, alpha: 1).setFill(); plate.fill()
    let glow = NSGradient(colors: [NSColor(deviceRed:1,green:0.65,blue:0.12,alpha:1), NSColor(deviceRed:0.95,green:0.24,blue:0.05,alpha:1)])!
    glow.draw(in: b.insetBy(dx: s * 0.13, dy: s * 0.13), angle: 90)
    let ring = NSBezierPath(ovalIn: b.insetBy(dx: s * 0.285, dy: s * 0.285))
    NSColor(deviceRed: 0.12, green: 0.07, blue: 0.05, alpha: 1).setFill(); ring.fill()
    let inner = NSBezierPath(ovalIn: b.insetBy(dx: s * 0.335, dy: s * 0.335))
    NSColor(deviceRed: 1, green: 0.84, blue: 0.43, alpha: 1).setFill(); inner.fill()
    context.flushGraphics(); NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}
for (name, size) in sizes { try icon(size).write(to: output.appending(path: name)) }
