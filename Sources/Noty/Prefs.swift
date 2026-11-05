// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ServiceManagement
import AppKit

enum ThemeChoice: String, CaseIterable { case system, light, dark
    var label: String { rawValue.capitalized }
}
/// Global capture shortcut choices. Carbon key codes: N=45, J=38, K=40.
enum HotkeyChoice: String, CaseIterable {
    case optCmdN, ctrlOptN, optCmdJ
    var label: String { switch self { case .optCmdN: "⌥⌘N"; case .ctrlOptN: "⌃⌥N"; case .optCmdJ: "⌥⌘J" } }
    var keyCode: UInt32 { switch self { case .optCmdN, .ctrlOptN: 45; case .optCmdJ: 38 } }
    /// Carbon modifier mask: cmdKey 0x100, optionKey 0x800, controlKey 0x1000.
    var modifiers: UInt32 { switch self { case .optCmdN, .optCmdJ: 0x100 | 0x800; case .ctrlOptN: 0x1000 | 0x800 } }
}
enum UpdateChannel: String, CaseIterable { case releases, main
    var label: String { self == .releases ? "Releases" : "Main branch" }
}

/// User preferences, stored in UserDefaults. Add a property here, a `register(defaults:)` entry, and a row in SettingsPane:
/// a preference that has no row in Settings does not exist.
@MainActor @Observable
final class Prefs {
    static let shared = Prefs()
    private let d = UserDefaults.standard

    var theme: ThemeChoice { didSet { d.set(theme.rawValue, forKey: "theme"); applyTheme() } }
    var showDockIcon: Bool { didSet { d.set(showDockIcon, forKey: "showDockIcon"); applyDockIcon() } }
    var notify: Bool { didSet { d.set(notify, forKey: "notify") } }
    var refreshSeconds: Int { didSet { d.set(refreshSeconds, forKey: "refreshSeconds") } }
    var updateChannel: UpdateChannel { didSet { d.set(updateChannel.rawValue, forKey: "updateChannel") } }
    var autoCheckUpdates: Bool { didSet { d.set(autoCheckUpdates, forKey: "autoCheckUpdates") } }
    var sidebarCollapsed: Bool { didSet { d.set(sidebarCollapsed, forKey: "sidebarCollapsed") } }
    var hotkey: HotkeyChoice { didSet { d.set(hotkey.rawValue, forKey: "hotkey"); Hotkey.shared.register(hotkey) } }
    /// Off: a capture goes straight to the category last used for that app, with no questions.
    var askEveryTime: Bool { didSet { d.set(askEveryTime, forKey: "askEveryTime") } }

    /// Last category used per source app ("Safari" → "Work/Q4 Launch"), so the capture panel opens on the right one.
    func lastPath(for app: String?) -> [String]? {
        let m = d.dictionary(forKey: "lastPaths") as? [String: String] ?? [:]
        return (m[app ?? ""] ?? m["*"]).map { $0.split(separator: "/").map(String.init) }
    }
    func rememberPath(_ path: [String], for app: String?) {
        var m = d.dictionary(forKey: "lastPaths") as? [String: String] ?? [:]
        let v = path.joined(separator: "/")
        m["*"] = v; if let app { m[app] = v }
        d.set(m, forKey: "lastPaths")
    }

    /// Launch at login is on by default; the user can turn it off. Backed by SMAppService (Login Items).
    private(set) var launchAtLogin: Bool = false
    private(set) var launchAtLoginError: String?

    private init() {
        d.register(defaults: ["notify": true, "refreshSeconds": 5, "showDockIcon": true, "autoCheckUpdates": true, "askEveryTime": true, "hotkey": "optCmdN"])
        theme = ThemeChoice(rawValue: d.string(forKey: "theme") ?? "") ?? .system
        showDockIcon = d.bool(forKey: "showDockIcon")
        notify = d.bool(forKey: "notify")
        refreshSeconds = d.integer(forKey: "refreshSeconds")
        sidebarCollapsed = d.bool(forKey: "sidebarCollapsed")
        hotkey = HotkeyChoice(rawValue: d.string(forKey: "hotkey") ?? "") ?? .optCmdN
        askEveryTime = d.bool(forKey: "askEveryTime")
        autoCheckUpdates = d.bool(forKey: "autoCheckUpdates")
        updateChannel = UpdateChannel(rawValue: d.string(forKey: "updateChannel") ?? "") ?? .releases
        // First run: opt in to launch at login. After that the user's choice always wins.
        if !d.bool(forKey: "launchAtLoginDefaulted") {
            d.set(true, forKey: "launchAtLoginDefaulted")
            setLaunchAtLogin(true)
        }
        refreshLaunchAtLogin()
    }

    func refreshLaunchAtLogin() { launchAtLogin = SMAppService.mainApp.status == .enabled }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = "Could not change Login Items: \(error.localizedDescription)"
        }
        refreshLaunchAtLogin()
    }

    /// Applies to every window AND the popover (which needs the explicit nudge in AppDelegate.applyAppearance).
    func applyTheme() {
        NSApp?.appearance = switch theme { case .system: nil; case .light: NSAppearance(named: .aqua); case .dark: NSAppearance(named: .darkAqua) }
        (NSApp?.delegate as? AppDelegate)?.applyAppearance()
    }

    /// Dock icon on = regular app (Dock, Cmd-Tab). Off = menu bar only.
    func applyDockIcon() {
        NSApp?.setActivationPolicy(showDockIcon ? .regular : .accessory)
    }
}
