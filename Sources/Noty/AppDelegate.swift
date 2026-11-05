// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import AppKit
import NotyKit

/// Owns the menu bar item (with its popover arrow), the Dock presence, and the Manager window.
/// The popover's views and the window are created on demand and destroyed on close, so a closed UI holds no view memory.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSPopoverDelegate {
    static var shared: AppDelegate { NSApp.delegate as! AppDelegate }
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var managerWindow: NSWindow?
    private let model = AppModel.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        if SnapshotMode.dir != nil { SnapshotMode.run(); return }
        Prefs.shared.applyTheme()
        Prefs.shared.applyDockIcon()
        NSApp.applicationIconImage = AppIcon.image(size: 512, padded: true)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = StatusIcon.image(.idle)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem.button?.setAccessibilityLabel("Noty")

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        model.onStatusChange = { [weak self] state in self?.statusItem.button?.image = StatusIcon.image(state) }

        Hotkey.shared.onPress = { CaptureController.shared.captureSelection() }
        Hotkey.shared.register(Prefs.shared.hotkey)
        Hotkey.shared.handlers[Hotkey.stackID] = { StackController.shared.toggle() }
        Prefs.shared.registerStackHotkey()
        NSApp.servicesProvider = ServicesProvider()
        NSUpdateDynamicServices()
        Task { await model.refresh() }
        Updater.shared.confirmLaunch()                                   // tells a pending swap script "the new version started"
        Task { Updater.shared.autoCheckIfDue(enabled: Prefs.shared.autoCheckUpdates) }
        if model.needsSetup { showManager() }                            // first run: show the guided setup, not an empty window
    }

    /// The popover does not follow NSApp.appearance on its own (it takes the menu bar's look), so set it explicitly.
    func applyAppearance() {
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        popover.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    }

    @objc func openSettings() { showManager(pane: .settings) }

    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let m = NSMenu()
            m.addItem(withTitle: "Open Noty", action: #selector(openManager), keyEquivalent: "").target = self
            m.addItem(withTitle: "Capture selection  \(Prefs.shared.hotkey.label)", action: #selector(captureSelection), keyEquivalent: "").target = self
            m.addItem(withTitle: "Open Stack  \(Prefs.shared.stackHotkey.label)", action: #selector(openStack), keyEquivalent: "").target = self
            m.addItem(withTitle: "Capture screen area", action: #selector(snipScreen), keyEquivalent: "").target = self
            m.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
            m.addItem(.separator())
            m.addItem(withTitle: "Quit Noty", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            statusItem.menu = m; statusItem.button?.performClick(nil); statusItem.menu = nil   // menu only for this click
        } else { togglePopover() }
    }
    func closePopover() { popover.performClose(nil) }
    @objc private func openManager() { showManager() }

    private func togglePopover() {
        if popover.isShown { popover.performClose(nil); return }
        guard let button = statusItem.button else { return }
        applyAppearance()
        let host = NSHostingController(rootView: PopoverView(openManager: { [weak self] p in self?.showManager(pane: p) }))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    func popoverDidClose(_ notification: Notification) {
        popover.contentViewController = nil   // release the popover's views while hidden
    }

    func showManager(pane: Pane? = nil) {
        if let pane { Nav.shared.pane = pane }
        Task { await LibraryModel.shared.reloadIfChanged() }
        popover.performClose(nil)
        if managerWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 860),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 900, height: 560)
            w.setFrameAutosaveName("NotyManager2")
            w.delegate = self
            w.contentView = NSHostingView(rootView: ManagerView())
            if !w.setFrameUsingName("NotyManager2") { w.center() }
            managerWindow = w
        }
        managerWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        model.setManagerVisible(true)
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === managerWindow else { return }
        model.setManagerVisible(false)
        managerWindow?.contentView = nil   // frees the SwiftUI tree
        managerWindow = nil
    }

    // Clicking the Dock icon opens the Manager.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showManager(); return true
    }

    // The app lives in the menu bar: closing the last window must not quit it.
    /// noty://item/<id> and noty://category/<path> open the manager on that item or category.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let link = Deeplink.parse(url) else { continue }
            showManager(pane: .library)
            Task { @MainActor in
                let lib = LibraryModel.shared
                await lib.reloadIfChanged(force: true)
                switch link {
                case .item(let raw):
                    guard let it = lib.items.first(where: { $0.id == raw || ($0.id.hasPrefix(raw) && raw.count >= 6) }) else {
                        AppModel.shared.show("That item isn't in this library any more.", error: true); return }
                    lib.scope = it.done ? .done : (it.path.first == NotyStore.inbox ? .inbox : .category(it.path))
                    for n in 1..<max(it.path.count, 1) { lib.expanded.insert(it.path.prefix(n).joined(separator: "/")) }
                    lib.selectedID = it.id
                case .category(let p):
                    guard lib.categories.contains(CategoryNode(path: p)) else { AppModel.shared.show("That category doesn't exist here.", error: true); return }
                    lib.scope = .category(p); lib.selectedID = nil
                    for n in 1..<max(p.count, 1) { lib.expanded.insert(p.prefix(n).joined(separator: "/")) }
                }
            }
        }
    }

    @objc func openStack() { StackController.shared.toggle() }

    @objc func snipScreen() { LibraryModel.shared.snip(into: nil) }

    @objc func captureSelection() { CaptureController.shared.captureSelection() }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
