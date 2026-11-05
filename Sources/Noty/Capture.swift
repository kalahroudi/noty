// SPDX-License-Identifier: Apache-2.0

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import NotyKit

/// What was highlighted, and where it came from.
struct Captured {
    var text = ""
    var app: String?
    var windowTitle: String?
    var url: String?
    /// Images found in the selection, as PNG data.
    var images: [Data] = []
}

/// The global shortcut (Carbon RegisterEventHotKey: needs no permission and costs nothing while idle).
@MainActor
final class Hotkey {
    static let shared = Hotkey()
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var onPress: (() -> Void)?

    func register(_ choice: HotkeyChoice) {
        if let ref { UnregisterEventHotKey(ref); self.ref = nil }
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { Hotkey.shared.onPress?() } }
                return noErr
            }, 1, &spec, nil, &handler)
        }
        let id = EventHotKeyID(signature: OSType(0x4E4F5459), id: 1)   // 'NOTY'
        let status = RegisterEventHotKey(choice.keyCode, choice.modifiers, id, GetApplicationEventTarget(), 0, &ref)
        if status != noErr { AppLog.info("Could not register shortcut \(choice.label): \(status)") }
    }
}

/// Reads the current selection from whatever app is in front: first through Accessibility, then by sending ⌘C and restoring the clipboard.
enum SelectionReader {
    static var trusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @MainActor static func read() async -> Captured {
        var c = Captured()
        let front = NSWorkspace.shared.frontmostApplication
        if let front, front.bundleIdentifier != Bundle.main.bundleIdentifier {
            c.app = front.localizedName
            if trusted { fillSource(&c, pid: front.processIdentifier) }
        }
        guard trusted else { return c }
        // ⌘C always runs too: the Accessibility text has no images, and the clipboard has the rich version (text + pictures).
        let copied = await copyFallback()
        c.images = copied.images
        let ax = axSelectedText() ?? ""
        let axClean = ax.replacingOccurrences(of: "\u{FFFC}", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        c.text = copied.text.isEmpty ? axClean : copied.text
        return c
    }

    private static func axSelectedText() -> String? {
        let sys = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(sys, kAXFocusedUIElementAttribute as CFString, &focused) == .success, let el = focused else { return nil }
        var sel: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el as! AXUIElement, kAXSelectedTextAttribute as CFString, &sel) == .success else { return nil }
        return (sel as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func fillSource(_ c: inout Captured, pid: pid_t) {
        let app = AXUIElementCreateApplication(pid)
        var w: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &w) == .success, let win = w else { return }
        let window = win as! AXUIElement
        var t: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &t) == .success, let s = t as? String, !s.isEmpty { c.windowTitle = s }
        var u: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXDocumentAttribute as CFString, &u) == .success, let s = u as? String, s.hasPrefix("http") || s.hasPrefix("file") { c.url = s }
    }

    /// Sends ⌘C, reads text and pictures from the clipboard, then puts the old clipboard back.
    @MainActor private static func copyFallback() async -> (text: String, images: [Data]) {
        let pb = NSPasteboard.general
        let saved: [[(NSPasteboard.PasteboardType, Data)]] = (pb.pasteboardItems ?? []).map { item in item.types.compactMap { t in item.data(forType: t).map { (t, $0) } } }
        // The shortcut's own keys (⌥⌘ or ⌃⌥) are usually still held. Wait for them to come up, or the app would see ⌥⌘C instead of ⌘C.
        for _ in 0..<30 where !NSEvent.modifierFlags.intersection([.option, .control, .shift]).isEmpty { try? await Task.sleep(for: .milliseconds(30)) }
        let before = pb.changeCount
        let src = CGEventSource(stateID: .privateState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: down)
            e?.flags = .maskCommand; e?.post(tap: .cghidEventTap)
        }
        var changed = false
        for _ in 0..<12 {
            try? await Task.sleep(for: .milliseconds(25))
            if pb.changeCount != before { changed = true; break }
        }
        guard changed else { return ("", []) }
        let result = extract(from: pb)
        pb.clearContents()
        for item in saved {
            let n = NSPasteboardItem()
            for (t, d) in item { n.setData(d, forType: t) }
            pb.writeObjects([n])
        }
        return result
    }

    static func extract(from pb: NSPasteboard) -> (text: String, images: [Data]) {
        let r = ClipboardContent.extract(from: pb)
        AppLog.info("Capture clipboard: \(r.images.count) image(s), \(r.text.count) chars, types \(r.types.prefix(14).joined(separator: ", "))")
        return (r.text, r.images)
    }
}

/// "Add to Noty" in the right-click Services menu of any app. Works without the Accessibility permission.
final class ServicesProvider: NSObject {
    @objc func addToNoty(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let got = SelectionReader.extract(from: pboard)
        guard !got.text.isEmpty || !got.images.isEmpty else { return }
        DispatchQueue.main.async { MainActor.assumeIsolated { CaptureController.shared.present(Captured(text: got.text, app: NSWorkspace.shared.frontmostApplication?.localizedName, images: got.images)) } }
    }
}
