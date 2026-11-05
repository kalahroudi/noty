// SPDX-License-Identifier: Apache-2.0

import AppKit

/// The menu bar glyph: a highlighter marker over a line of text. Always a template image so macOS tints it for light and dark bars.
/// State is in the SHAPE: filled marker = captures waiting in the Inbox, outline = all sorted, dashed outline = working.
enum StatusIcon {
    enum State { case active, idle, busy }

    static func image(_ state: State) -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.setFill(); NSColor.black.setStroke()
            // marker body: a rounded slanted bar, tip at the lower left
            let body = NSBezierPath()
            body.move(to: NSPoint(x: 6.2, y: 10.6)); body.line(to: NSPoint(x: 11.6, y: 2.6))
            body.curve(to: NSPoint(x: 14.2, y: 3.6), controlPoint1: NSPoint(x: 12.4, y: 1.9), controlPoint2: NSPoint(x: 13.6, y: 2.6))
            body.line(to: NSPoint(x: 9.2, y: 12.2)); body.close()
            switch state {
            case .active: body.fill()
            case .idle: body.lineWidth = 1.3; body.lineJoinStyle = .round; body.stroke()
            case .busy: body.lineWidth = 1.3; body.lineJoinStyle = .round; body.setLineDash([2.4, 1.6], count: 2, phase: 0); body.stroke()
            }
            // chisel tip
            let tip = NSBezierPath(); tip.move(to: NSPoint(x: 6.2, y: 10.6)); tip.line(to: NSPoint(x: 9.2, y: 12.2)); tip.line(to: NSPoint(x: 5.0, y: 14.0)); tip.close(); tip.fill()
            // the highlight stroke under the tip
            let line = NSBezierPath(roundedRect: NSRect(x: 2.5, y: 14.6, width: 13, height: 1.8), xRadius: 0.9, yRadius: 0.9); line.fill()
            return true
        }
        img.isTemplate = true
        return img
    }
}
