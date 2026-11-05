// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import NotyKit

/// What the manager is showing: a smart list or one category (with everything below it).
enum Scope: Hashable {
    case inbox, today, all, done, agent
    case category([String])

    var title: String {
        switch self {
        case .inbox: "Inbox"; case .today: "Today"; case .all: "All items"; case .done: "Done"; case .agent: "Agent results"
        case .category(let p): p.last ?? ""
        }
    }
    var symbol: String {
        switch self { case .inbox: "tray"; case .today: "sun.max"; case .all: "square.stack"; case .done: "checkmark.circle"; case .agent: "sparkles"; case .category: "folder" }
    }
}

/// The library as the UI sees it. Reads happen off the main actor; the folder is re-read only when it changed, and only while a window or popover is visible.
@MainActor @Observable
final class LibraryModel {
    static let shared = LibraryModel()

    private(set) var store: NotyStore
    var items: [Item] = []
    var categories: [CategoryNode] = []
    var proposals: [Proposal] = []
    var conflicts = 0
    var loaded = false

    var scope: Scope = .inbox
    var selectedID: String?
    var expanded: Set<String> = []
    var query = ""
    /// Set by the capture panel (⌘↩) to open the "ask an agent" sheet for a just-captured item.
    var askAgentFor: String?

    private var signature = ""

    private init() {
        let root = NotyStore.resolveRoot()
        store = NotyStore(root: root)
        try? AppPaths().ensureDirectories()
        do { try store.prepare() } catch { AppLog.error(error, context: "prepare library") }
    }

    // MARK: Loading

    func reloadIfChanged(force: Bool = false) async {
        let s = store
        let sig = await Task.detached { s.signature() }.value
        guard force || sig != signature || !loaded else { return }
        let (lib, props, newSig) = await Task.detached { (s.load(), s.proposals(), s.signature()) }.value
        guard s === store else { return }
        items = lib.items; categories = lib.categories; proposals = props; conflicts = lib.conflicts
        signature = newSig; loaded = true
        NotifyScheduler.sync(items)
        if let id = selectedID, !items.contains(where: { $0.id == id }) { selectedID = nil }
    }

    /// Switches to a different library folder (iCloud Drive or any folder) and copies the current items over, never overwriting.
    func moveLibrary(to url: URL) {
        let old = store.root
        guard url.standardizedFileURL != old.standardizedFileURL else { return }
        do {
            try NotyStore.copyLibrary(from: old, to: url)
            try NotyStore.saveRoot(url)
            store = NotyStore(root: url)
            try store.prepare()
            loaded = false; signature = ""
            Task { await reloadIfChanged(force: true) }
            AppModel.shared.show("Library is now in \(url.lastPathComponent). The old copy was left in place.")
        } catch { report(error, "Move the library") }
    }

    // MARK: Queries

    var inboxCount: Int { items.filter { $0.path.first == NotyStore.inbox && !$0.done }.count }
    var todayCount: Int { items.filter { $0.today && !$0.done }.count }
    var allCategoryPaths: [[String]] { categories.map(\.path) }

    func count(in path: [String]) -> Int { items.filter { !$0.done && $0.path.starts(with: path) }.count }

    func visibleItems() -> [Item] {
        var r: [Item]
        switch scope {
        case .inbox: r = items.filter { $0.path.first == NotyStore.inbox && !$0.done }
        case .today: r = items.filter { $0.today && !$0.done }
        case .all: r = items.filter { !$0.done }
        case .done: r = items.filter(\.done)
        case .agent: r = []
        case .category(let p): r = items.filter { $0.path.starts(with: p) && !$0.done }
        }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            r = items.filter { ($0.title + " " + $0.quote + " " + $0.notes + " " + $0.tags.joined(separator: " ") + " " + $0.pathLabel).lowercased().contains(q) }
        }
        return r
    }

    func item(_ id: String?) -> Item? { id.flatMap { id in items.first { $0.id == id } } }

    // MARK: Changes (each one saves the file first, then updates what is on screen)

    @discardableResult
    func add(_ item: Item) -> Item? {
        guard let saved = run("Add the item", { try store.save(item) }) else { return nil }
        items.insert(saved, at: 0)
        ensureCategoryKnown(saved.path)
        return saved
    }

    func update(_ item: Item) {
        let before = items.first { $0.id == item.id }
        let wasDone = before?.done
        guard let saved = run("Save the item", { try store.save(item) }) else { return }
        // A finished item leaves the list being viewed (every scope but Done), so its details must not stay open on the right.
        if let wasDone, wasDone != saved.done, selectedID == saved.id { selectedID = nil }
        if let i = items.firstIndex(where: { $0.id == saved.id }) { items[i] = saved }
        ensureCategoryKnown(saved.path)
        if before?.reminders != saved.reminders || before?.done != saved.done { NotifyScheduler.sync(items) }
    }

    // MARK: Reminders

    /// Adds a reminder (or a Calendar event) made from highlighted words. Asks for notification access the first time.
    @discardableResult
    func addReminder(to id: String, text: String, due: Date, kind: Reminder.Kind, nudge: Bool) async -> Bool {
        guard var it = item(id) else { return false }
        var r = Reminder(text: text, due: due, kind: kind, nudge: nudge)
        if kind == .event {
            guard await CalendarBridge.shared.request() else {
                AppModel.shared.show("Allow Noty to use your calendar in System Settings → Privacy & Security → Calendars.", error: true); return false
            }
            do { r.eventID = try CalendarBridge.shared.add(title: text, start: due, notes: "From Noty: \(it.title)\n\(it.deepLink)") }
            catch { report(error, "Add the calendar event"); return false }
        } else if !(await NotifyScheduler.authorize()) {
            AppModel.shared.show("Reminder saved, but notifications are off. Allow Noty in System Settings → Notifications to be alerted.", error: true)
        }
        it.reminders.append(r); update(it)
        AppModel.shared.show("\(kind == .event ? "Scheduled" : "Reminder set") for \(ReminderTime.label(due)).")
        return true
    }

    func setReminderDone(_ reminderID: String, in id: String, done: Bool) {
        guard var it = item(id), let i = it.reminders.firstIndex(where: { $0.id == reminderID }) else { return }
        it.reminders[i].done = done; update(it)
    }

    func removeReminder(_ reminderID: String, from id: String) {
        guard var it = item(id) else { return }
        it.reminders.removeAll { $0.id == reminderID }; update(it)
    }

    /// Reminders from every open item, plus Calendar events when the user has allowed them, from `start` for `days` days.
    func agenda(from start: Date, days: Int) -> [AgendaEntry] {
        let cal = Calendar.current
        let from = cal.startOfDay(for: start), to = cal.date(byAdding: .day, value: days, to: from) ?? start
        var out: [AgendaEntry] = []
        for it in items where !it.done {
            for r in it.reminders where r.due < to && (r.due >= from || (!r.done && from <= cal.startOfDay(for: Date()))) {
                out.append(AgendaEntry(id: r.id, date: r.due, title: r.text, detail: it.pathLabel, kind: r.kind, itemID: it.id, done: r.done))
            }
        }
        let known = Set(items.flatMap { $0.reminders.compactMap(\.eventID) })
        for e in CalendarBridge.shared.events(from: from, to: to) where !known.contains(e.eventIdentifier ?? "") {
            out.append(AgendaEntry(id: "cal-" + (e.eventIdentifier ?? UUID().uuidString), date: e.startDate, title: e.title ?? "Event", detail: e.calendar?.title ?? "Calendar", kind: .event, fromCalendar: true))
        }
        return out.sorted { $0.date < $1.date }
    }

    func toggleDone(_ id: String) { if var it = item(id) { it.done.toggle(); update(it) } }

    /// Stores a picture or file with the item. Images become PNG so they show up as pictures; anything else is copied as it is.
    @discardableResult
    func attach(_ data: Data, ext: String, to id: String) -> Bool {
        guard var it = item(id) else { return false }
        var n = it.attachments.count + 1
        while it.attachments.contains(where: { $0.hasPrefix("\(id.prefix(8).lowercased())-\(n).") }) { n += 1 }
        guard let name = run("Attach the file", { try store.saveAttachment(data, itemID: id, index: n, ext: ext) }) else { return false }
        it.attachments.append(name); update(it)
        return true
    }

    func attach(fileAt url: URL, to id: String) {
        let ext = url.pathExtension.lowercased()
        guard let data = try? Data(contentsOf: url) else { AppModel.shared.show("Couldn't read \(url.lastPathComponent).", error: true); return }
        if ["png", "jpg", "jpeg", "heic", "gif", "tiff", "bmp"].contains(ext), let img = NSImage(data: data), let png = Snip.png(img) { attach(png, ext: "png", to: id) }
        else { attach(data, ext: ext, to: id) }
    }

    /// Files dropped on the list or the menu bar popover become one new task with every file attached.
    func createTask(fromDrop providers: [NSItemProvider]) -> Bool {
        let found = providers.filter { $0.canLoadObject(ofClass: URL.self) }
        guard !found.isEmpty else { return false }
        Task { @MainActor in
            var urls: [URL] = []
            for p in found {
                let url: URL? = await withCheckedContinuation { c in _ = p.loadObject(ofClass: URL.self) { u, _ in c.resume(returning: u) } }
                if let url, url.isFileURL { urls.append(url) }
            }
            guard let first = urls.first else { return }
            var path = [NotyStore.inbox]
            if case .category(let p) = scope { path = p }
            let title = urls.count == 1 ? first.lastPathComponent : "\(first.lastPathComponent) and \(urls.count - 1) more"
            guard let task = add(Item(title: title, today: scope == .today, path: path)) else { return }
            for u in urls { attach(fileAt: u, to: task.id) }
            selectedID = task.id
            AppModel.shared.show(urls.count == 1 ? "Task created from \(first.lastPathComponent)." : "Task created with \(urls.count) files.")
        }
        return true
    }

    func removeAttachment(_ name: String, from id: String) {
        guard var it = item(id) else { return }
        it.attachments.removeAll { $0 == name }
        update(it)
        try? FileManager.default.trashItem(at: store.attachmentURL(name), resultingItemURL: nil)
    }

    /// Picks an area of the screen and attaches it to the item, or to a new task in the current category when there is no item.
    func snip(into id: String?) {
        Task { @MainActor in
            guard let data = await Snip.captureAreaHidingNoty() else { return }
            var target = id
            if target == nil {
                var path = [NotyStore.inbox]
                if case .category(let p) = scope { path = p }
                target = add(Item(title: "Screenshot \(Date().formatted(date: .abbreviated, time: .shortened))", path: path))?.id
            }
            if let t = target, attach(data, ext: "png", to: t) { selectedID = t; AppModel.shared.show("Screenshot added.") }
        }
    }

    func move(_ id: String, to path: [String]) { if var it = item(id) { it.path = path; update(it) } }

    func delete(_ id: String) {
        guard let it = item(id), run("Delete the item", { try store.delete(it) }) != nil else { return }
        items.removeAll { $0.id == id }
        if selectedID == id { selectedID = nil }
    }

    func createCategory(_ path: [String]) {
        guard run("Create the category", { try store.createCategory(path) }) != nil else { return }
        ensureCategoryKnown(path.map(NotyStore.cleanName))
        for i in 1..<max(path.count, 1) { expanded.insert(path.prefix(i).joined(separator: "/")) }
    }

    func renameCategory(_ path: [String], to name: String) {
        guard run("Rename the category", { try store.renameCategory(path, to: name) }) != nil else { return }
        let new = Array(path.dropLast()) + [NotyStore.cleanName(name)]
        func swap(_ p: [String]) -> [String] { p.starts(with: path) ? new + p.dropFirst(path.count) : p }
        expanded = Set(expanded.map { e in
            let parts = e.split(separator: "/").map(String.init); return swap(parts).joined(separator: "/") })
        if case .category(let p) = scope { scope = .category(swap(p)) }
        Task { await reloadIfChanged(force: true) }
    }

    func deleteCategory(_ path: [String]) {
        guard run("Delete the category", { try store.deleteCategory(path) }) != nil else { return }
        categories.removeAll { $0.path.starts(with: path) }
        if case .category(let p) = scope, p.starts(with: path) { scope = .inbox }
    }

    func approve(_ p: Proposal) {
        guard let url = run("Write the file", { try store.approve(p) }) else { return }
        proposals.removeAll { $0.id == p.id }
        Task { await reloadIfChanged(force: true) }
        AppModel.shared.show("Wrote \(url.lastPathComponent)")
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func discard(_ p: Proposal) { store.discardProposal(p.id); proposals.removeAll { $0.id == p.id } }

    private func ensureCategoryKnown(_ path: [String]) {
        for n in 1...max(path.count, 1) where n <= path.count {
            let c = CategoryNode(path: Array(path.prefix(n)))
            if !categories.contains(c) { categories.append(c) }
        }
        categories.sort { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    private func run<T>(_ action: String, _ work: () throws -> T) -> T? {
        do { return try work() } catch { report(error, action); return nil }
    }

    private func report(_ error: Error, _ action: String) {
        AppLog.error(error, context: action)
        AppModel.shared.show(UserError.message(for: error, action: action), error: true)
    }
}
