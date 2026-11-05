// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import AppKit
import NotyKit

private final class StackPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// The Stack: every open item, one card at a time. Arrow keys move through them, Space zooms into the details.
/// A floating panel like the capture panel: created when opened, destroyed when closed.
@MainActor
final class StackController {
    static let shared = StackController()
    private var panel: StackPanel?
    private var monitor: Any?
    private var model: StackModel?

    func toggle() { panel == nil ? show() : close() }

    func show() {
        guard panel == nil else { panel?.makeKeyAndOrderFront(nil); return }
        let lib = LibraryModel.shared
        Task { await lib.reloadIfChanged() }
        let m = StackModel()
        m.onClose = { [weak self] in self?.close() }
        model = m
        let p = StackPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 560), styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                           backing: .buffered, defer: false)
        p.isFloatingPanel = true; p.level = .floating; p.hasShadow = true; p.isOpaque = false; p.backgroundColor = .clear
        p.isReleasedWhenClosed = false; p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.appearance = NSApp.effectiveAppearance
        p.contentView = NSHostingView(rootView: StackView(model: m))
        let mouse = NSEvent.mouseLocation
        if let vis = (NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main)?.visibleFrame {
            p.setFrameOrigin(NSPoint(x: vis.midX - 320, y: vis.midY - 280 + 30))
        } else { p.center() }
        p.makeKeyAndOrderFront(nil)
        panel = p
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in self?.key(e) ?? e }
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: p, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    func close() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let p = panel { NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: p); p.orderOut(nil); p.contentView = nil }
        panel = nil; model = nil
    }

    /// Arrows, Space, Return, Esc and single letters drive the stack. While a text field is open, only Esc, Return and the up/down arrows are taken.
    private func key(_ e: NSEvent) -> NSEvent? {
        guard let m = model, e.window === panel else { return e }
        let code = Int(e.keyCode)
        if m.mode != .browse {
            switch code {
            case 53: m.cancelInput(); return nil
            case 36, 76: m.commitInput(); return nil
            case 125 where m.mode == .search: m.move(1); return nil
            case 126 where m.mode == .search: m.move(-1); return nil
            default: return e
            }
        }
        switch code {
        case 53: m.zoomed ? m.setZoom(false) : close(); return nil
        case 123, 126: m.move(-1); return nil
        case 124, 125: m.move(1); return nil
        case 49, 36, 76: m.setZoom(!m.zoomed); return nil
        default: break
        }
        guard !e.modifierFlags.contains(.command), let ch = e.charactersIgnoringModifiers?.lowercased() else { return e }
        switch ch {
        case "d": m.toggleDone()
        case "n": m.startAdd()
        case "/", "s": m.startSearch()
        case "t": m.toggleToday()
        case "o": m.openInNoty()
        case "q": close()
        default: return e
        }
        return nil
    }
}

@MainActor @Observable
final class StackModel {
    enum Mode { case browse, search, add }
    var mode: Mode = .browse
    var query = ""
    var newTitle = ""
    var index = 0
    var zoomed = false
    var onClose: () -> Void = {}
    private let lib = LibraryModel.shared

    /// Open items of every kind, today's first, then newest. A search narrows them.
    var items: [Item] {
        let open = lib.items.filter { !$0.done }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let hit = q.isEmpty ? open : open.filter { ($0.title + " " + $0.quote + " " + $0.notes + " " + $0.tags.joined(separator: " ") + " " + $0.pathLabel).lowercased().contains(q) }
        return hit.filter(\.today) + hit.filter { !$0.today }
    }

    var current: Item? { let i = items; return i.indices.contains(index) ? i[index] : nil }

    func move(_ d: Int) {
        let n = items.count
        guard n > 0 else { return }
        withAnimation(.snappy(duration: 0.18)) { index = (index + d + n) % n }
    }

    func setZoom(_ on: Bool) { guard current != nil || !on else { return }; withAnimation(.snappy(duration: 0.18)) { zoomed = on } }

    func clamp() { index = max(0, min(index, items.count - 1)) }

    func toggleDone() {
        guard let it = current else { return }
        lib.toggleDone(it.id); clamp()
        AppModel.shared.show("Done: \(it.title)")
        if items.isEmpty { zoomed = false }
    }

    func toggleToday() {
        guard var it = current else { return }
        it.today.toggle(); lib.update(it)
        if let i = items.firstIndex(where: { $0.id == it.id }) { index = i }
    }

    func startAdd() { zoomed = false; newTitle = ""; mode = .add }
    func startSearch() { zoomed = false; mode = .search; index = 0 }

    func commitInput() {
        switch mode {
        case .add:
            let t = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            mode = .browse
            guard !t.isEmpty else { return }
            query = ""
            if let saved = lib.add(Item(title: t, path: [NotyStore.inbox])), let i = items.firstIndex(where: { $0.id == saved.id }) { index = i }
        case .search: mode = .browse; clamp()
        case .browse: break
        }
    }

    func cancelInput() {
        if mode == .search { query = "" }
        mode = .browse; newTitle = ""; clamp()
    }

    func openInNoty() {
        guard let it = current else { return }
        lib.scope = it.path.first == NotyStore.inbox ? .inbox : .category(it.path)
        for n in 1..<max(it.path.count, 1) { lib.expanded.insert(it.path.prefix(n).joined(separator: "/")) }
        lib.selectedID = it.id
        onClose()
        AppDelegate.shared.showManager(pane: .library)
    }
}

struct StackView: View {
    let model: StackModel
    @FocusState private var focus: Bool

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ZStack {
                if model.zoomed, let it = model.current { StackDetail(item: it).transition(.opacity) }
                else { stack }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .frame(width: 640, height: 560)
        .background(Theme.pane, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .onChange(of: model.mode) { _, m in focus = m != .browse }
        .overlay(alignment: .bottom) { ToastView() }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            if model.mode == .search {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search", text: Bindable(model).query).textFieldStyle(.plain).focused($focus)
                }.font(.system(size: 14)).padding(.horizontal, 10).padding(.vertical, 6).background(Theme.card, in: RoundedRectangle(cornerRadius: 8))
            } else {
                Text(model.query.isEmpty ? "Stack" : "Search: \(model.query)").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
            }
            if model.mode != .search {
                let n = model.items.count
                Text(n == 0 ? "" : "\(min(model.index, n - 1) + 1) of \(n)").font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
            }
            iconButton("magnifyingglass", "Search (/)") { model.startSearch() }
            iconButton("plus", "New task (N)") { model.startAdd() }
            iconButton("xmark", "Close (Esc)") { model.onClose() }
        }.padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 8)
    }

    private func iconButton(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).frame(width: 24, height: 24).contentShape(Rectangle()) }
            .buttonStyle(.plain).help(help).accessibilityLabel(help)
    }

    @ViewBuilder private var stack: some View {
        if model.mode == .add {
            VStack(alignment: .leading, spacing: 12) {
                Text("New task").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                TextField("What needs doing?", text: Bindable(model).newTitle, axis: .vertical).textFieldStyle(.plain).font(.system(size: 24, weight: .semibold)).lineLimit(1...4).focused($focus)
                Text("Return adds it to the Inbox · Esc cancels").font(.system(size: 12)).foregroundStyle(.secondary)
            }.padding(28).frame(maxWidth: .infinity, alignment: .leading).card(padding: 0).padding(.horizontal, 34).padding(.vertical, 30)
        } else if let current = model.current {
            let items = model.items
            let i = min(model.index, items.count - 1)
            ZStack {
                ForEach(Array((i..<min(i + 3, items.count)).reversed()), id: \.self) { k in
                    let depth = k - i
                    StackCard(item: items[k], front: depth == 0)
                        .scaleEffect(1 - CGFloat(depth) * 0.045, anchor: .top).offset(y: CGFloat(depth) * 30).opacity(1 - Double(depth) * 0.3)
                        .zIndex(Double(-depth))
                        .onTapGesture { if depth == 0 { model.setZoom(true) } else { model.move(depth) } }
                }
            }.padding(.horizontal, 34).padding(.top, 14).padding(.bottom, 62).id(current.id)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle").font(.system(size: 34)).foregroundStyle(.secondary)
                Text(model.query.isEmpty ? "Nothing open" : "No matches").font(.system(size: 17, weight: .semibold))
                Text(model.query.isEmpty ? "Press N to add a task." : "Esc clears the search.").font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        let hints: [(String, String)] = model.zoomed ? [("← →", "previous / next"), ("D", "done"), ("O", "open in Noty"), ("Space", "back")]
            : [("← →", "navigate"), ("Space", "details"), ("D", "done"), ("N", "new"), ("/", "search"), ("T", "today"), ("Esc", "close")]
        return HStack(spacing: 14) {
            ForEach(hints, id: \.0) { h in
                HStack(spacing: 4) {
                    Text(h.0).font(.system(size: 11, weight: .semibold, design: .rounded)).padding(.horizontal, 5).padding(.vertical, 1.5).background(Theme.fill, in: RoundedRectangle(cornerRadius: 4))
                    Text(h.1).font(.system(size: 11.5))
                }
            }
        }.foregroundStyle(.secondary).lineLimit(1).frame(maxWidth: .infinity).padding(.horizontal, 12).padding(.vertical, 10)
    }
}

/// One card in the stack: the title large, a short preview, and only the facts that matter.
private struct StackCard: View {
    let item: Item
    let front: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(item.title).font(.system(size: 26, weight: .semibold)).lineLimit(4).fixedSize(horizontal: false, vertical: true)
            let preview = item.plainQuote.isEmpty ? plainNotes : item.plainQuote
            if front, !preview.isEmpty { Text(preview).font(.system(size: 15)).foregroundStyle(.secondary).lineLimit(6) }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                KindBadge(kind: item.kind)
                if item.today { Badge(text: "Today", kind: .warn) }
                Text(item.pathLabel).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                let n = item.attachments.filter { !$0.hasSuffix(".html") }.count
                if n > 0 { Label("\(n)", systemImage: "paperclip").font(.system(size: 12)).foregroundStyle(.secondary) }
            }
        }
        .padding(28).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline))
        .shadow(color: .black.opacity(front ? 0.12 : 0.05), radius: front ? 14 : 4, y: front ? 6 : 2)
    }

    private var plainNotes: String { NotesMarkdown.attributed(item.notes).string.trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// The zoomed view: everything about the item, at a comfortable reading size.
private struct StackDetail: View {
    let item: Item
    let lib = LibraryModel.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(item.title).font(.system(size: 24, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    KindBadge(kind: item.kind)
                    if item.today { Badge(text: "Today", kind: .warn) }
                    Text(item.pathLabel).font(.system(size: 12)).foregroundStyle(.secondary)
                    ForEach(item.tags, id: \.self) { Badge(text: "#\($0)", kind: .neutral) }
                }
                if !quote.isEmpty {
                    MarkdownView(text: quote, size: 14.5).padding(14).background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(alignment: .leading) { Rectangle().fill(Theme.highlight).frame(width: 3).clipShape(RoundedRectangle(cornerRadius: 2)) }
                }
                if !item.notes.isEmpty { notes }
                ForEach(item.imageAttachments, id: \.self) { name in
                    if let img = NSImage(contentsOf: lib.store.attachmentURL(name)) {
                        Image(nsImage: img).resizable().scaledToFit().frame(maxWidth: .infinity, alignment: .leading)
                            .clipShape(RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.hairline))
                    }
                }
                ForEach(item.otherAttachments, id: \.self) { name in
                    Button { NSWorkspace.shared.open(lib.store.attachmentURL(name)) } label: { Label(name, systemImage: name.hasSuffix(".pdf") ? "doc.richtext" : "doc").font(.system(size: 13)) }.buttonStyle(Pill())
                }
                if let u = item.sourceURL, let url = URL(string: u) { Link(item.sourceTitle ?? u, destination: url).font(.system(size: 13)) }
                else if let a = item.sourceApp { Text("From \(a)").font(.system(size: 13)).foregroundStyle(.secondary) }
            }.padding(.horizontal, 34).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
        }.scrollIndicators(.automatic)
    }

    private var quote: String {
        item.quote.replacingOccurrences(of: #"!\[[^\]]*\]\(attachment:\d+\)"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @ViewBuilder private var notes: some View {
        if let a = try? AttributedString(NotesMarkdown.attributed(item.notes, size: 15), including: \.appKit) { Text(a).textSelection(.enabled) }
        else { Text(item.notes).font(.system(size: 15)) }
    }
}
