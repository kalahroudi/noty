// SPDX-License-Identifier: Apache-2.0

import AppKit

/// The app icon, drawn in code so the build needs no image tools and stays crisp at every size.
/// A sheet of text with one line highlighted in marker yellow, and the highlighter that did it.
enum AppIcon {
    /// - padded: leave the transparent margin macOS expects around Dock icons (824 of 1024).
    static func image(size: CGFloat, padded: Bool = false) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
            let s = size / 1024
            let inset: CGFloat = padded ? 100 : 0
            let tile = NSRect(x: inset * s, y: inset * s, width: (1024 - 2 * inset) * s, height: (1024 - 2 * inset) * s)
            let u = tile.width / 1024   // all artwork below is authored on a 1024 grid and scaled into the tile
            func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: tile.minX + x * u, y: tile.minY + y * u) }
            func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect { NSRect(x: tile.minX + x * u, y: tile.minY + y * u, width: w * u, height: h * u) }
            func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
                NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: a)
            }

            // Tile: deep slate-indigo
            let shape = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.2246, yRadius: tile.width * 0.2246)
            NSGradient(starting: color(0x3B4A6B), ending: color(0x141B2D))?.draw(in: shape, angle: -60)
            NSGraphicsContext.saveGraphicsState(); shape.addClip()

            // Paper, slightly turned, with a soft shadow
            NSGraphicsContext.saveGraphicsState()
            let rot = NSAffineTransform(); rot.translateX(by: tile.midX, yBy: tile.midY); rot.rotate(byDegrees: -6); rot.translateX(by: -tile.midX, yBy: -tile.midY); rot.concat()
            let paper = NSBezierPath(roundedRect: r(212, 170, 600, 700), xRadius: 54 * u, yRadius: 54 * u)
            let sh = NSShadow(); sh.shadowColor = NSColor.black.withAlphaComponent(0.4); sh.shadowBlurRadius = 40 * u; sh.shadowOffset = NSSize(width: 0, height: -18 * u)
            NSGraphicsContext.saveGraphicsState(); sh.set(); color(0xFAF8F2).setFill(); paper.fill(); NSGraphicsContext.restoreGraphicsState()

            // Text lines (line 3 gets the highlight)
            let lines: [(CGFloat, CGFloat)] = [(300, 440), (400, 360), (500, 430), (600, 300), (700, 390)]
            for (i, l) in lines.enumerated() {
                let y = CGFloat(i) * 100 + 300
                if i == 2 {
                    let mark = NSBezierPath(roundedRect: r(262, y - 40, 500, 92), xRadius: 14 * u, yRadius: 14 * u)
                    color(0xF5C518).setFill(); mark.fill()
                }
                let bar = NSBezierPath(roundedRect: r(296, y - 14 + (i == 2 ? 6 : 0), l.1 + (i == 2 ? 40 : 0), 30), xRadius: 15 * u, yRadius: 15 * u)
                color(i == 2 ? 0x2A2200 : 0x8A93A6).setFill(); bar.fill()
                _ = l.0
            }
            NSGraphicsContext.restoreGraphicsState()

            // Highlighter pen across the lower right
            NSGraphicsContext.saveGraphicsState()
            let pen = NSAffineTransform(); pen.translateX(by: tile.minX + 700 * u, yBy: tile.minY + 700 * u); pen.rotate(byDegrees: 40); pen.concat()
            let psh = NSShadow(); psh.shadowColor = NSColor.black.withAlphaComponent(0.45); psh.shadowBlurRadius = 30 * u; psh.shadowOffset = NSSize(width: 0, height: -14 * u)
            func pr(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect { NSRect(x: x * u, y: y * u, width: w * u, height: h * u) }
            NSGraphicsContext.saveGraphicsState(); psh.set()
            let body = NSBezierPath(roundedRect: pr(-80, -40, 160, 400), xRadius: 34 * u, yRadius: 34 * u)
            color(0xF5C518).setFill(); body.fill()
            NSGraphicsContext.restoreGraphicsState()
            let grip = NSBezierPath(roundedRect: pr(-80, 150, 160, 210), xRadius: 34 * u, yRadius: 34 * u)
            color(0x1E2538).setFill(); grip.fill()
            let band = NSBezierPath(rect: pr(-80, 130, 160, 28)); color(0xE0AE00).setFill(); band.fill()
            // chisel tip pointing up-left toward the paper
            let tip = NSBezierPath()
            tip.move(to: NSPoint(x: -64 * u, y: -40 * u)); tip.line(to: NSPoint(x: 64 * u, y: -40 * u)); tip.line(to: NSPoint(x: 38 * u, y: -118 * u)); tip.line(to: NSPoint(x: -38 * u, y: -118 * u)); tip.close()
            color(0x3A3F55).setFill(); tip.fill()
            let tipEdge = NSBezierPath(roundedRect: pr(-38, -134, 76, 28), xRadius: 8 * u, yRadius: 8 * u); color(0xF5C518).setFill(); tipEdge.fill()
            NSGraphicsContext.restoreGraphicsState()

            NSGraphicsContext.restoreGraphicsState()
            return true
        }
    }

    /// Writes an .iconset folder for `iconutil -c icns`.
    static func writeIconset(to dir: String) throws {
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let sizes: [(String, CGFloat)] = [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                                          ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)]
        for (name, px) in sizes {
            guard let tiff = image(size: px, padded: true).tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { continue }
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("icon_\(name).png"))
        }
    }
}
