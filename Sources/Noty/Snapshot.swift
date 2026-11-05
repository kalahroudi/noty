// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import AppKit
import NotyKit

/// `Noty --snapshot <dir>` renders the app's screens to PNG files for the docs, then exits.
/// It uses made-up sample data, never the user's real data. Add a Shot per screen/theme you want in the README.
enum SnapshotMode {
    nonisolated(unsafe) static var dir: String?

    @MainActor static func run() {
        guard let dir else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        NSApp.setActivationPolicy(.accessory)
        Demo.install()
        Task { @MainActor in
            for shot in shots { await render(shot, to: dir) }
            NSApp.terminate(nil)
        }
    }

    struct Shot { let name: String; let dark: Bool; let size: CGSize; let make: @MainActor () -> AnyView }

    @MainActor static var shots: [Shot] {
        func manager(_ p: Pane, dark: Bool = false, agents: Bool = false) -> Shot {
            Shot(name: "manager-\(p.rawValue)\(agents ? "-agents" : "")\(dark ? "-dark" : "")", dark: dark, size: CGSize(width: 1280, height: 860)) {
                Nav.shared.pane = p
                return AnyView(ManagerView(agentsTab: agents))
            }
        }
        func pop(dark: Bool = false) -> Shot {
            Shot(name: "popover\(dark ? "-dark" : "")", dark: dark, size: CGSize(width: 800, height: 600)) { AnyView(PopoverShot()) }
        }
        func capture(dark: Bool = false) -> Shot {
            Shot(name: "capture\(dark ? "-dark" : "")", dark: dark, size: CGSize(width: 520, height: 520)) {
                AnyView(CaptureView(model: CaptureModel(captured: Captured(text: "Set a latency budget per user journey, not per service. Measure p99 at the edge, alert on budget burn, and review the budget every quarter.", app: "Safari", windowTitle: "p99 latency is a product decision", url: "https://example.com/p99"))).padding(40).background(Theme.sidebar))
            }
        }
        func detail() -> Shot {
            Shot(name: "detail", dark: false, size: CGSize(width: 980, height: 760)) { AnyView(ItemDetailView(id: LibraryModel.shared.items[0].id)) }
        }
        func stack(zoomed: Bool = false, dark: Bool = false) -> Shot {
            Shot(name: "stack\(zoomed ? "-zoomed" : "")\(dark ? "-dark" : "")", dark: dark, size: CGSize(width: 720, height: 640)) {
                let m = StackModel(); m.zoomed = zoomed
                return AnyView(StackView(model: m).padding(40).background(Theme.sidebar))
            }
        }
        func agenda(_ tab: AgendaModel.Tab = .today) -> Shot {
            Shot(name: "agenda\(tab == .today ? "" : "-" + tab.rawValue.lowercased())", dark: false, size: CGSize(width: 940, height: 720)) {
                let m = AgendaModel(); m.tab = tab
                return AnyView(AgendaView(model: m).padding(40).background(Theme.sidebar))
            }
        }
        func selection(_ remind: Bool) -> Shot {
            Shot(name: remind ? "selection-remind" : "selection-bar", dark: false, size: CGSize(width: 420, height: remind ? 360 : 90)) {
                let m = SelectionModel(suggestion: ReminderTime.suggest(text: "Record a 30 second demo before Friday"))
                if remind { m.mode = .remind }
                return AnyView(SelectionMenu(model: m).background(Theme.card, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline)).padding(30).background(Theme.pane))
            }
        }
        return [agenda(), agenda(.week), selection(false), selection(true), stack(), stack(zoomed: true), stack(dark: true), detail(), pop(), pop(dark: true), capture(), capture(dark: true), manager(.library), manager(.library, dark: true), manager(.settings), manager(.settings, agents: true), manager(.help)]
    }

    @MainActor static func render(_ shot: Shot, to dir: String) async {
        let host = NSHostingView(rootView: shot.make().frame(width: shot.size.width, height: shot.size.height))
        let win = NSWindow(contentRect: NSRect(origin: .zero, size: shot.size), styleMask: [.borderless], backing: .buffered, defer: false)
        win.appearance = NSAppearance(named: shot.dark ? .darkAqua : .aqua)
        win.contentView = host
        win.setFrameOrigin(NSPoint(x: -4000, y: 0))   // off screen, but still laid out and drawn
        win.orderFront(nil)
        try? await Task.sleep(for: .milliseconds(700))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent(shot.name + ".png")) }
        win.orderOut(nil)
    }
}

/// A menu bar with the popover hanging from the icon, on a soft backdrop. Used only for screenshots.
struct PopoverShot: View {
    var body: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(colors: [Color(red: 0.62, green: 0.71, blue: 0.78), Color(red: 0.29, green: 0.37, blue: 0.49)], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    Text("Finder").bold(); Text("File"); Text("Edit"); Text("View")
                    Spacer()
                    Image(nsImage: StatusIcon.image(.active)).renderingMode(.template).padding(.horizontal, 6).padding(.vertical, 2).background(Color.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
                    Text("Tue 20 Oct  9:41")
                }.font(.system(size: 13)).foregroundStyle(.primary).padding(.horizontal, 14).frame(height: 28).background(.regularMaterial)
                PopoverView(openManager: { _ in })
                    .clipShape(RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black.opacity(0.15)))
                    .shadow(color: .black.opacity(0.35), radius: 24, y: 12).padding(.top, 8).padding(.trailing, 10)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Spacer()
            }
        }
    }
}

/// Made-up data that looks like a typical day.
@MainActor enum Demo {
    static func install() {
        let m = AppModel.shared
        m.demo = true
        m.setupState = SetupState(items: [])
        m.status = "3 to sort in Inbox"
        m.loadedOnce = true; m.updatedAt = .now
        let lib = LibraryModel.shared
        func it(_ t: String, _ path: [String], quote: String = "", app: String? = nil, today: Bool = false, done: Bool = false, tags: [String] = [], kind: ItemKind = .task) -> Item {
            Item(title: t, kind: kind, done: done, today: today, tags: tags, quote: quote, sourceApp: app, path: path)
        }
        let research = ["Work", "Q4 Launch", "Research"]
        // a sample screenshot attachment, so the full-size viewer can be shown
        let img = NSImage(size: NSSize(width: 1600, height: 900), flipped: false) { r in
            NSGradient(starting: NSColor(srgbRed: 0.1, green: 0.12, blue: 0.16, alpha: 1), ending: NSColor(srgbRed: 0.05, green: 0.06, blue: 0.09, alpha: 1))?.draw(in: r, angle: 90)
            for i in 0..<22 { ("2026-10-21 12:30:\(10 + i) INFO  GET /v1/models 200  p99=\(240 + i * 7) ms" as NSString).draw(at: NSPoint(x: 40, y: 840 - CGFloat(i) * 36), withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 22, weight: .regular), .foregroundColor: i % 7 == 5 ? NSColor.systemOrange : NSColor(white: 0.85, alpha: 1)]) }
            return true
        }
        let sampleAttachment = NSBitmapImageRep(data: img.tiffRepresentation!)?.representation(using: .png, properties: [:]).flatMap { try? lib.store.saveAttachment($0, itemID: "demo0000", index: 1) }
        lib.items = [
            it("Set a latency budget per user journey", research, quote: "## Latency budgets\nSet a budget **per user journey**, not per service. See the [guide](https://example.com/p99).\n\n- Measure p99 at the edge\n- Alert on budget *burn*\n  - not on raw spikes\n\n| Journey | Budget |\n| --- | --- |\n| Checkout | 400 ms |\n| Search | 250 ms |", app: "Safari", today: true, tags: ["latency"]),
            it("Read RFC 9114 section on stream limits", research, app: "Preview", kind: .reference),
            it("Compare connection pooling libraries", research, app: "Slack", done: true),
            it("Remove serial calls in checkout service", ["Work", "Q4 Launch", "Build"], quote: "…removing serial calls, long before any rewrite is justified.", app: "Xcode"),
            it("Add p99 burn alert to dashboard", ["Work", "Q4 Launch", "Build"], today: true),
            it("Reply to Sam about the onboarding doc", ["Work", "Hiring"], app: "Mail", today: true),
            it("Use WAL mode for concurrent readers", ["Inbox"], quote: "Use WAL mode for concurrent readers", app: "Safari", kind: .idea),
            it("Book dentist", ["Personal"]),
        ]
        let cal = Calendar.current
        func at(_ day: Int, _ h: Int, _ m: Int = 0) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: cal.date(byAdding: .day, value: day, to: cal.startOfDay(for: Date())) ?? Date()) ?? Date() }
        lib.items[0].reminders = [Reminder(text: "collect feedback from the first 50 users", due: at(0, 17), nudge: true), Reminder(text: "Latency budget review", due: at(1, 10), kind: .event)]
        lib.items[4].reminders = [Reminder(text: "Add p99 burn alert to dashboard", due: at(0, 15, 30), nudge: true)]
        lib.items[5].reminders = [Reminder(text: "Reply to Sam about the onboarding doc", due: at(0, 11)), Reminder(text: "Send the hiring panel notes", due: at(2, 9, 30))]
        lib.items[6].reminders = [Reminder(text: "Use WAL mode for concurrent readers", due: at(3, 14))]
        lib.categories = ["Inbox", "Personal", "Work", "Work/Hiring", "Work/Q4 Launch", "Work/Q4 Launch/Build", "Work/Q4 Launch/Research"].map { CategoryNode(path: $0.split(separator: "/").map(String.init)) }
        lib.expanded = ["Work", "Work/Q4 Launch"]
        if let a = sampleAttachment { lib.items[0].attachments = [a]; lib.items[0].quote += "\n\n![image](attachment:1)" }
        lib.scope = .category(["Work", "Q4 Launch"]); lib.selectedID = lib.items[0].id
        lib.loaded = true
    }
}
