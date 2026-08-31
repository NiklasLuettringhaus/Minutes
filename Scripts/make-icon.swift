#!/usr/bin/env swift
// Generates AppIcon.icns. Without an icon the app is a blank tile in Spotlight
// and effectively unfindable, which is how it got lost the first time.
import AppKit

let teal   = NSColor(red: 0.071, green: 0.647, blue: 0.580, alpha: 1)   // #12A594
let deep   = NSColor(red: 0.043, green: 0.412, blue: 0.373, alpha: 1)

func draw(_ size: Int) -> NSImage {
    let s = CGFloat(size)
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high

    // macOS app-icon convention: rounded square inset from the canvas.
    let inset = s * 0.085
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = rect.width * 0.235
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    NSGradient(starting: teal, ending: deep)!.draw(in: path, angle: -90)

    // Waveform: the same silhouette as the idle menu bar icon, so the tile and
    // the menu bar item read as the same product.
    let bars: [CGFloat] = [0.26, 0.50, 0.80, 1.0, 0.66, 0.94, 0.44, 0.22]
    let usable = rect.width * 0.60
    let barW = usable / CGFloat(bars.count) * 0.42
    let gap  = usable / CGFloat(bars.count)
    let startX = rect.midX - usable / 2 + gap * 0.29
    NSColor.white.setFill()
    for (i, h) in bars.enumerated() {
        let bh = rect.height * 0.46 * h
        let r = NSRect(x: startX + CGFloat(i) * gap, y: rect.midY - bh / 2, width: barW, height: bh)
        NSBezierPath(roundedRect: r, xRadius: barW / 2, yRadius: barW / 2).fill()
    }
    img.unlockFocus()
    return img
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

// The set iconutil expects.
let variants: [(Int, String)] = [
    (16, "icon_16x16"), (32, "icon_16x16@2x"), (32, "icon_32x32"), (64, "icon_32x32@2x"),
    (128, "icon_128x128"), (256, "icon_128x128@2x"), (256, "icon_256x256"),
    (512, "icon_256x256@2x"), (512, "icon_512x512"), (1024, "icon_512x512@2x"),
]
for (px, name) in variants {
    let img = draw(px)
    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { continue }
    try? png.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
}
print("wrote \(variants.count) sizes to \(out)")
