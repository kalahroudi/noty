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
            Shot(name: "manager-\(p.rawValue)\(agents ? "-agents" : "")\(dark ? "-dark" : "")", dark: dark, size: CGSize(width: 1000, height: 700)) {
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
        return [pop(), pop(dark: true), capture(), capture(dark: true), manager(.library), manager(.library, dark: true), manager(.settings), manager(.settings, agents: true), manager(.help)]
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
        lib.items = [
            it("Set a latency budget per user journey", research, quote: "Measure p99 at the edge, alert on budget burn, and review the budget every quarter.", app: "Safari", today: true, tags: ["latency"]),
            it("Read RFC 9114 section on stream limits", research, app: "Preview", kind: .reference),
            it("Compare connection pooling libraries", research, app: "Slack", done: true),
            it("Remove serial calls in checkout service", ["Work", "Q4 Launch", "Build"], quote: "…removing serial calls, long before any rewrite is justified.", app: "Xcode"),
            it("Add p99 burn alert to dashboard", ["Work", "Q4 Launch", "Build"], today: true),
            it("Reply to Sam about the onboarding doc", ["Work", "Hiring"], app: "Mail", today: true),
            it("Use WAL mode for concurrent readers", ["Inbox"], quote: "Use WAL mode for concurrent readers", app: "Safari", kind: .idea),
            it("Book dentist", ["Personal"]),
        ]
        lib.categories = ["Inbox", "Personal", "Work", "Work/Hiring", "Work/Q4 Launch", "Work/Q4 Launch/Build", "Work/Q4 Launch/Research"].map { CategoryNode(path: $0.split(separator: "/").map(String.init)) }
        lib.expanded = ["Work", "Work/Q4 Launch"]
        lib.scope = .category(["Work", "Q4 Launch"]); lib.selectedID = lib.items[0].id
        lib.loaded = true
    }
}
