// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import AppKit
import NotyKit

private final class AgendaPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// The Agenda: today, tomorrow and the week, with reminders from your items and your calendar, and a short summary on top.
/// A floating panel like the Stack: created when opened, destroyed when closed.
@MainActor
final class AgendaController {
    static let shared = AgendaController()
    private var panel: AgendaPanel?
    private var monitor: Any?
    private var model: AgendaModel?

    func toggle() { panel == nil ? show() : close() }

    func show() {
        guard panel == nil else { panel?.makeKeyAndOrderFront(nil); return }
        Task { await LibraryModel.shared.reloadIfChanged() }
        let m = AgendaModel()
        m.onClose = { [weak self] in self?.close() }
        model = m
        let p = AgendaPanel(contentRect: NSRect(x: 0, y: 0, width: 860, height: 640), styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
        p.isFloatingPanel = true; p.level = .floating; p.hasShadow = true; p.isOpaque = false; p.backgroundColor = .clear
        p.isReleasedWhenClosed = false; p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.appearance = NSApp.effectiveAppearance
        p.contentView = NSHostingView(rootView: AgendaView(model: m))
        let mouse = NSEvent.mouseLocation
        if let vis = (NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main)?.visibleFrame { p.setFrameOrigin(NSPoint(x: vis.midX - 430, y: vis.midY - 320 + 30)) } else { p.center() }
        p.makeKeyAndOrderFront(nil)
        panel = p
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in self?.key(e) ?? e }
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: p, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if self?.model?.keepOpen != true { self?.close() } }
        }
    }

    func close() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let p = panel { NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: p); p.orderOut(nil); p.contentView = nil }
        panel = nil; model = nil
    }

    private func key(_ e: NSEvent) -> NSEvent? {
        guard let m = model, e.window === panel else { return e }
        let code = Int(e.keyCode)
        if m.adding {
            switch code { case 53: m.adding = false; m.newText = ""; return nil; case 36, 76: m.commitAdd(); return nil; default: return e }
        }
        switch code {
        case 53: close(); return nil
        case 123: m.step(-1); return nil
        case 124: m.step(1); return nil
        default: break
        }
        guard !e.modifierFlags.contains(.command), let ch = e.charactersIgnoringModifiers?.lowercased() else { return e }
        switch ch { case "n": m.adding = true; case "q": close(); default: return e }
        return nil
    }
}

@MainActor @Observable
final class AgendaModel {
    enum Tab: String, CaseIterable { case today = "Today", tomorrow = "Tomorrow", week = "Week" }
    var tab: Tab = .today
    var adding = false
    var newText = ""
    var onClose: () -> Void = {}
    var keepOpen: Bool { adding }
    private let lib = LibraryModel.shared

    func step(_ d: Int) {
        let all = Tab.allCases; guard let i = all.firstIndex(of: tab) else { return }
        withAnimation(.snappy(duration: 0.15)) { tab = all[(i + d + all.count) % all.count] }
    }

    /// Typing "Call Sam tomorrow 9" makes a task in the Inbox with a reminder at the time the words ask for.
    func commitAdd() {
        let t = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        adding = false; newText = ""
        guard !t.isEmpty else { return }
        let due = ReminderTime.suggest(text: t, busy: lib.items.flatMap { $0.reminders.filter { !$0.done }.map(\.due) }).pick
        guard let saved = lib.add(Item(title: t, path: [NotyStore.inbox])) else { return }
        Task { await lib.addReminder(to: saved.id, text: t, due: due, kind: .reminder, nudge: true) }
    }

    func open(_ itemID: String) {
        guard let it = lib.item(itemID) else { return }
        lib.scope = it.path.first == NotyStore.inbox ? .inbox : .category(it.path)
        for n in 1..<max(it.path.count, 1) { lib.expanded.insert(it.path.prefix(n).joined(separator: "/")) }
        lib.selectedID = it.id
        onClose()
        AppDelegate.shared.showManager(pane: .library)
    }
}

struct AgendaView: View {
    let model: AgendaModel
    let lib = LibraryModel.shared
    @FocusState private var focus: Bool
    @State private var calendarAsked = false

    var body: some View {
        let entries = lib.agenda(from: Date(), days: 8)
        VStack(spacing: 0) {
            header
            summary(entries)
            ScrollView {
                Group {
                    switch model.tab {
                    case .today: list(day: Date(), entries)
                    case .tomorrow: list(day: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date(), entries)
                    case .week: week(entries)
                    }
                }.padding(.horizontal, 28).padding(.vertical, 14)
            }
            if model.adding { addField.padding(.horizontal, 28).padding(.bottom, 8) }
            footer
        }
        .frame(width: 860, height: 640)
        .background(Theme.pane, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .onChange(of: model.adding) { _, on in focus = on }
        .overlay(alignment: .bottom) { ToastView() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Text("Agenda").font(.system(size: 20, weight: .bold))
            Segmented(options: AgendaModel.Tab.allCases.map { ($0, $0.rawValue) }, selection: Bindable(model).tab)
            Spacer()
            Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide))).font(.system(size: 12.5)).foregroundStyle(.secondary)
            Button { model.adding = true } label: { Image(systemName: "plus").font(.system(size: 12, weight: .semibold)).frame(width: 24, height: 24).contentShape(Rectangle()) }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("New reminder (N)").accessibilityLabel("New reminder")
            Button { model.onClose() } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).frame(width: 24, height: 24).contentShape(Rectangle()) }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Close (Esc)").accessibilityLabel("Close")
        }.padding(.horizontal, 28).padding(.top, 20).padding(.bottom, 12)
    }

    private func summary(_ entries: [AgendaEntry]) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "sparkles").font(.system(size: 15)).foregroundStyle(Theme.onAccent).frame(width: 34, height: 34).background(Theme.accent, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text("Noty is keeping tabs").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.onSoft)
                Text(AgendaSummary.text(entries: entries)).font(.system(size: 14.5)).fixedSize(horizontal: false, vertical: true)
                if !CalendarBridge.shared.authorized && !CalendarBridge.shared.denied && !calendarAsked {
                    Button("Show my calendar here") { calendarAsked = true; Task { _ = await CalendarBridge.shared.request(); lib.items = lib.items } }.buttonStyle(Pill()).padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }.card(padding: 16).padding(.horizontal, 28)
    }

    @ViewBuilder private func list(day: Date, _ all: [AgendaEntry]) -> some View {
        let cal = Calendar.current
        let overdue = cal.isDateInToday(day) ? all.filter { $0.date < cal.startOfDay(for: day) && !$0.done && !$0.fromCalendar } : []
        let todays = all.filter { cal.isDate($0.date, inSameDayAs: day) }
        VStack(alignment: .leading, spacing: 8) {
            if !overdue.isEmpty { SectionLabel("Overdue"); ForEach(overdue) { row($0, overdue: true) } }
            SectionLabel(cal.isDateInToday(day) ? "Today" : "Tomorrow")
            if todays.isEmpty { Text("Nothing scheduled. Press N to add a reminder.").font(.system(size: 13)).foregroundStyle(.secondary).padding(.vertical, 6) }
            ForEach(todays) { row($0) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ e: AgendaEntry, overdue: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(e.date.formatted(.dateTime.hour().minute())).font(.system(size: 13, weight: .semibold)).monospacedDigit().frame(width: 54, alignment: .leading).padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(e.title).font(.system(size: 14.5, weight: .semibold)).strikethrough(e.done).foregroundStyle(e.done ? .secondary : .primary).lineLimit(2)
                if !e.detail.isEmpty { Text(e.detail).font(.system(size: 11.5)).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 8)
            Badge(text: e.kind == .event ? "Event" : (overdue ? "Overdue" : "Reminder"), kind: overdue ? .danger : (e.kind == .event ? .accent : .warn))
            if let id = e.itemID, !e.fromCalendar {
                Button { lib.setReminderDone(e.id, in: id, done: !e.done) } label: { Image(systemName: e.done ? "checkmark.circle.fill" : "circle").foregroundStyle(e.done ? Theme.ok : .secondary).frame(width: 22, height: 22).contentShape(Rectangle()) }
                    .buttonStyle(.plain).accessibilityLabel(e.done ? "Mark not done" : "Mark done")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11).background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(overdue ? Theme.danger.opacity(0.4) : Theme.hairline))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { if let id = e.itemID { model.open(id) } }
    }

    private func week(_ all: [AgendaEntry]) -> some View {
        let cal = Calendar.current
        return HStack(alignment: .top, spacing: 8) {
            ForEach(0..<7, id: \.self) { i in
                let day = cal.date(byAdding: .day, value: i, to: cal.startOfDay(for: Date())) ?? Date()
                let items = all.filter { cal.isDate($0.date, inSameDayAs: day) }
                VStack(alignment: .leading, spacing: 6) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(day.formatted(.dateTime.weekday(.abbreviated)).uppercased()).font(.system(size: 11, weight: .bold)).tracking(0.5).foregroundStyle(.secondary)
                        Text(day.formatted(.dateTime.day())).font(.system(size: 20, weight: .bold))
                    }
                    ForEach(items) { e in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(e.date.formatted(.dateTime.hour().minute())).font(.system(size: 10.5, weight: .bold)).monospacedDigit().foregroundStyle(e.kind == .event ? Theme.link : Theme.onSoft)
                            Text(e.title).font(.system(size: 12)).lineLimit(3).strikethrough(e.done)
                        }.padding(8).frame(maxWidth: .infinity, alignment: .leading).background(Theme.card, in: RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.hairline))
                            .onTapGesture { if let id = e.itemID { model.open(id) } }
                    }
                }.frame(maxWidth: .infinity, alignment: .topLeading).opacity(items.isEmpty && i > 0 ? 0.6 : 1)
            }
        }
    }

    private var addField: some View {
        HStack(spacing: 8) {
            Image(systemName: "bell").foregroundStyle(.secondary)
            TextField("Remind me to… (try “call Sam tomorrow 9”)", text: Bindable(model).newText).textFieldStyle(.plain).focused($focus)
        }.font(.system(size: 14)).padding(11).background(Theme.card, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.highlight, lineWidth: 1.5))
    }

    private var footer: some View {
        HStack(spacing: 14) {
            ForEach([("← →", "day"), ("N", "new reminder"), ("Esc", "close")], id: \.0) { h in
                HStack(spacing: 4) {
                    Text(h.0).font(.system(size: 11, weight: .semibold, design: .rounded)).padding(.horizontal, 5).padding(.vertical, 1.5).background(Theme.fill, in: RoundedRectangle(cornerRadius: 4))
                    Text(h.1).font(.system(size: 11.5))
                }
            }
        }.foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 10)
    }
}
