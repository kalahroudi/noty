// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import AppKit
import NotyKit

@MainActor @Observable
final class SelectionModel {
    enum Mode { case bar, remind, schedule }
    var mode: Mode = .bar
    var nudge = true
    var highlighted = false
    var suggestion: ReminderTime.Suggestion
    var onHighlight: () -> Void = {}
    var onPick: (Date, Reminder.Kind, Bool) -> Void = { _, _, _ in }
    var onAsk: () -> Void = {}
    var onPickDate: (Reminder.Kind) -> Void = { _ in }

    init(suggestion: ReminderTime.Suggestion) { self.suggestion = suggestion }
}

/// The floating bar that appears over selected text, and the time choices behind Remind me and Schedule.
struct SelectionMenu: View {
    let model: SelectionModel

    var body: some View {
        Group {
            switch model.mode {
            case .bar: bar
            case .remind: times(title: "REMIND ME", kind: .reminder)
            case .schedule: times(title: "SCHEDULE", kind: .event)
            }
        }.padding(6)
    }

    private var bar: some View {
        HStack(spacing: 2) {
            barButton("Highlight", active: model.highlighted) { Image(systemName: "highlighter").foregroundStyle(Theme.highlight) } action: { model.onHighlight() }
            barButton("Remind me") { Image(systemName: "bell") } action: { withAnimation(.snappy(duration: 0.15)) { model.mode = .remind } }
            barButton("Schedule") { Image(systemName: "calendar") } action: { withAnimation(.snappy(duration: 0.15)) { model.mode = .schedule } }
            Divider().frame(height: 18).padding(.horizontal, 3)
            barButton("Ask AI") { Image(systemName: "sparkle").foregroundStyle(Theme.onSoft) } action: { model.onAsk() }
        }.fixedSize()
    }

    private func barButton<I: View>(_ title: String, active: Bool = false, @ViewBuilder icon: () -> I, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) { icon().font(.system(size: 12)); Text(title).font(.system(size: 12.5, weight: active ? .semibold : .medium)) }
                .padding(.horizontal, 10).padding(.vertical, 6).background(active ? Theme.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 7)).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func times(title: String, kind: Reminder.Kind) -> some View {
        let s = model.suggestion
        return VStack(alignment: .leading, spacing: 0) {
            SectionLabel(title).padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 4)
            Button { model.onPick(s.pick, kind, model.nudge) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkle").font(.system(size: 11)).foregroundStyle(Theme.onSoft)
                        Text(ReminderTime.label(s.pick)).font(.system(size: 13.5))
                        Spacer(); Text("AI pick").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.onSoft)
                    }
                    Text(s.reason).font(.system(size: 12)).foregroundStyle(.secondary).padding(.leading, 19)
                }.padding(.horizontal, 12).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 8)).contentShape(Rectangle())
            }.buttonStyle(.plain)
            ForEach(s.options, id: \.label) { o in
                Button { model.onPick(o.date, kind, model.nudge) } label: {
                    HStack { Text(o.label).font(.system(size: 13.5)); Spacer(); Text(ReminderTime.label(o.date)).font(.system(size: 12)).foregroundStyle(.secondary) }
                        .padding(.horizontal, 12).padding(.vertical, 7).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            Divider().padding(.vertical, 4)
            Button { model.onPickDate(kind) } label: { Text("Pick a date and time…").font(.system(size: 13.5)).padding(.horizontal, 12).padding(.vertical, 7).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()) }.buttonStyle(.plain)
            if kind == .reminder {
                Divider().padding(.vertical, 4)
                Toggle("Let AI nudge me again if it is still open", isOn: Bindable(model).nudge).toggleStyle(.checkbox).font(.system(size: 12.5)).padding(.horizontal, 12).padding(.vertical, 6)
            }
        }.frame(width: 330)
    }
}

/// A date and time field for "Pick a date and time…".
private struct DatePickPanel: View {
    @State var date: Date
    let kind: Reminder.Kind
    let done: (Date?) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(kind == .event ? "SCHEDULE" : "REMIND ME")
            DatePicker("", selection: $date, in: Date()..., displayedComponents: [.date, .hourAndMinute]).datePickerStyle(.graphical).labelsHidden()
            HStack { Button("Cancel") { done(nil) }.buttonStyle(Pill()); Spacer(); Button(kind == .event ? "Schedule" : "Remind me") { done(date) }.buttonStyle(Pill(kind: .primary)) }
        }.padding(14).frame(width: 290)
    }
}

/// Shows the bar next to the selection in a notes box. One at a time; it closes when the selection goes away.
@MainActor
final class SelectionPopover: NSObject {
    static let shared = SelectionPopover()
    private var popover: NSPopover?
    private var shownFor: (NSRange, String)?

    func show(textView tv: NotesTextView, itemID: String) {
        let range = tv.selectedRange()
        guard range.length >= 2, popover == nil || shownFor?.0 != range else { return }
        close()
        let lib = LibraryModel.shared
        let raw = (tv.string as NSString).substring(with: range)
        let text = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        guard !text.isEmpty else { return }

        let model = SelectionModel(suggestion: ReminderTime.suggest(text: text, busy: busyTimes()))
        model.highlighted = tv.isHighlighted(range)
        model.onHighlight = { [weak self, weak tv] in
            tv?.setSelectedRange(range); tv?.setHighlight(!(tv?.isHighlighted(range) ?? false), range: range); self?.close()
        }
        let pick: (Date, Reminder.Kind, Bool) -> Void = { [weak self, weak tv] date, kind, nudge in
            tv?.setHighlight(true, range: range)
            Task { await lib.addReminder(to: itemID, text: text, due: date, kind: kind, nudge: nudge) }
            self?.close()
        }
        model.onPick = pick
        model.onAsk = { [weak self] in
            AgentSheetPreset.shared.extra = "About this passage from the item: “\(text)”."
            lib.askAgentFor = itemID
            AppDelegate.shared.showManager(pane: .library)
            self?.close()
        }
        model.onPickDate = { [weak self] kind in self?.showDatePicker(kind: kind, suggestion: model.suggestion.pick, nudge: model.nudge, pick: pick) }

        let p = NSPopover()
        p.behavior = .applicationDefined; p.animates = true
        p.contentViewController = NSHostingController(rootView: SelectionMenu(model: model))
        p.contentSize = NSSize(width: 330, height: 10)
        (p.contentViewController as? NSHostingController<SelectionMenu>)?.sizingOptions = .preferredContentSize
        let sel = tv.firstRect(forCharacterRange: range, actualRange: nil)
        guard let win = tv.window else { return }
        let inTV = tv.convert(win.convertFromScreen(sel), from: nil)
        p.show(relativeTo: inTV.isEmpty ? tv.visibleRect : inTV, of: tv, preferredEdge: .minY)
        popover = p; shownFor = (range, text)
    }

    private func showDatePicker(kind: Reminder.Kind, suggestion: Date, nudge: Bool, pick: @escaping (Date, Reminder.Kind, Bool) -> Void) {
        guard let p = popover else { return }
        p.contentViewController = NSHostingController(rootView: DatePickPanel(date: suggestion, kind: kind) { date in
            if let date { pick(date, kind, nudge) } else { self.close() }
        })
    }

    func close() { popover?.close(); popover = nil; shownFor = nil }

    /// Times that already have something on them: other reminders and Calendar events.
    private func busyTimes() -> [Date] {
        LibraryModel.shared.items.filter { !$0.done }.flatMap { $0.reminders.filter { !$0.done }.map(\.due) } + CalendarBridge.shared.busyStarts()
    }
}
