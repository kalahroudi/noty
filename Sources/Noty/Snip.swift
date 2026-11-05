// SPDX-License-Identifier: Apache-2.0

import AppKit
import NotyKit

/// Screenshots and files for an item: "capture an area" uses the system's own crosshair picker, so it looks and works like ⌘⇧4.
@MainActor
enum Snip {
    /// Lets the user drag an area, then returns it as PNG. Nil when they pressed Esc.
    static func captureArea() async -> Data? {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("noty-snip-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: file) }
        let ok: Bool = await withCheckedContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            p.arguments = ["-i", "-x", "-t", "png", file.path]   // interactive, no shutter sound
            p.terminationHandler = { _ in cont.resume(returning: true) }
            do { try p.run() } catch { cont.resume(returning: false) }
        }
        guard ok, let data = try? Data(contentsOf: file), !data.isEmpty else { return nil }
        return data
    }

    /// Hides Noty's windows while the area is picked, so the user can capture what is behind them, then brings them back.
    static func captureAreaHidingNoty() async -> Data? {
        let windows = NSApp.windows.filter { $0.isVisible && !($0 is NSPanel) }
        windows.forEach { $0.orderOut(nil) }
        try? await Task.sleep(for: .milliseconds(250))
        let data = await captureArea()
        windows.forEach { $0.orderFront(nil) }
        NSApp.activate(ignoringOtherApps: true)
        return data
    }

    /// An image from the clipboard (a screenshot copied with ⌃⌘⇧4, or any copied picture) as PNG.
    static func clipboardImage() -> Data? {
        guard let img = NSImage(pasteboard: .general) else { return nil }
        return png(img)
    }

    static func png(_ img: NSImage) -> Data? {
        guard let tiff = img.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    }
}
