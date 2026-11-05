// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import AppKit
import NotyKit

/// Floating panel that appears next to the pointer after the capture shortcut. Created on demand and destroyed on close.
private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class CaptureController {
    static let shared = CaptureController()
    private var panel: KeyPanel?
    private var monitor: Any?
    private var model: CaptureModel?

    /// The shortcut: read the selection, then show the panel.
    func captureSelection() {
        if panel != nil { close(); return }
        Task { @MainActor in
            if !SelectionReader.trusted {
                SelectionReader.requestTrust()
                AppModel.shared.show("Allow Noty under Privacy & Security → Accessibility so it can read your selection, then try again.", error: true)
                AppDelegate.shared.showManager(pane: .settings)
                return
            }
            present(await SelectionReader.read())
        }
    }

    func present(_ captured: Captured) {
        close()
        let lib = LibraryModel.shared
        Task { await lib.reloadIfChanged() }
        let m = CaptureModel(captured: captured)
        m.onClose = { [weak self] in self?.close() }
        m.onOpenAgent = { id in lib.askAgentFor = id; AppDelegate.shared.showManager(pane: .library) }
        model = m

        let p = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 10), styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                         backing: .buffered, defer: false)
        p.isFloatingPanel = true; p.level = .floating; p.hasShadow = true; p.isOpaque = false; p.backgroundColor = .clear
        p.isReleasedWhenClosed = false; p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.appearance = NSApp.effectiveAppearance
        let host = NSHostingView(rootView: CaptureView(model: m))
        host.sizingOptions = [.intrinsicContentSize]
        p.contentView = host
        p.setContentSize(host.fittingSize)
        position(p)
        p.makeKeyAndOrderFront(nil)
        panel = p
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in self?.key(e) ?? e }
        // Click elsewhere closes it, like a menu.
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: p, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.model?.keepOpen == true ? () : self?.close() }
        }
        if !Prefs.shared.askEveryTime, !m.captured.text.isEmpty { m.quickAdd() }
    }

    func close() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let p = panel { NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: p); p.orderOut(nil); p.contentView = nil }
        panel = nil; model = nil
    }

    private func position(_ p: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let vis = screen?.visibleFrame else { return }
        var o = NSPoint(x: mouse.x - 40, y: mouse.y - p.frame.height - 18)
        if o.y < vis.minY + 8 { o.y = mouse.y + 18 }
        o.x = min(max(o.x, vis.minX + 8), vis.maxX - p.frame.width - 8)
        o.y = min(max(o.y, vis.minY + 8), vis.maxY - p.frame.height - 8)
        p.setFrameOrigin(o)
    }

    /// Arrow keys, Return, Esc and ⌘1–4 drive the panel; everything else goes to the text field.
    private func key(_ e: NSEvent) -> NSEvent? {
        guard let m = model, e.window === panel else { return e }
        let cmd = e.modifierFlags.contains(.command)
        switch Int(e.keyCode) {
        case 53: close(); return nil                                   // esc
        case 125: m.move(1); return nil                                // down
        case 126: m.move(-1); return nil                               // up
        case 36, 76: m.add(askAgent: cmd); return nil                  // return, ⌘return
        case 48: m.focusTitle.toggle(); return nil                     // tab
        default: break
        }
        if cmd, let ch = e.charactersIgnoringModifiers, let n = Int(ch), (1...ItemKind.allCases.count).contains(n) { m.kind = ItemKind.allCases[n - 1]; return nil }
        return e
    }
}

@MainActor @Observable
final class CaptureModel {
    var captured: Captured
    var title: String
    var kind: ItemKind = .task
    var today = false
    var query = ""
    var index = 0
    var focusTitle = false
    var addedTo: String?
    var keepOpen: Bool { addedTo != nil }
    var onClose: () -> Void = {}
    var onOpenAgent: (String) -> Void = { _ in }

    init(captured: Captured) {
        self.captured = captured
        title = Item.makeTitle(from: captured.text)
    }

    /// Where it can go: the last-used category for this app first, then everything else; typing filters; a new path can be created on the spot.
    var choices: [[String]] {
        let lib = LibraryModel.shared
        var paths = lib.allCategoryPaths
        if let last = Prefs.shared.lastPath(for: captured.app), let i = paths.firstIndex(of: last) { paths.remove(at: i); paths.insert(last, at: 0) }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return paths }
        let hit = paths.filter { $0.joined(separator: " ").lowercased().contains(q.replacingOccurrences(of: "/", with: " ")) }
        let typed = NotyStore.parsePath(query)
        return hit + (paths.contains(typed) || typed.isEmpty ? [] : [typed])
    }

    func isNew(_ path: [String]) -> Bool { !LibraryModel.shared.allCategoryPaths.contains(path) }

    func move(_ d: Int) { let n = choices.count; guard n > 0 else { return }; index = min(max(index + d, 0), n - 1) }

    func quickAdd() {
        let path = Prefs.shared.lastPath(for: captured.app) ?? [NotyStore.inbox]
        commit(path: path, askAgent: false)
    }

    func add(askAgent: Bool) {
        let list = choices
        let path = list.indices.contains(index) ? list[index] : [NotyStore.inbox]
        commit(path: path, askAgent: askAgent)
    }

    private func commit(path: [String], askAgent: Bool) {
        let lib = LibraryModel.shared
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty || !captured.text.isEmpty else { onClose(); return }
        if isNew(path) { lib.createCategory(path) }
        let item = Item(title: t.isEmpty ? Item.makeTitle(from: captured.text) : t, kind: kind, today: today, quote: captured.text,
                        sourceApp: captured.app, sourceTitle: captured.windowTitle, sourceURL: captured.url, path: path)
        guard let saved = lib.add(item) else { onClose(); return }
        Prefs.shared.rememberPath(path, for: captured.app)
        addedTo = path.joined(separator: " › ")
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(askAgent ? 100 : 1100))
            onClose()
            if askAgent { onOpenAgent(saved.id) }
        }
    }
}

struct CaptureView: View {
    @Bindable var model: CaptureModel
    @FocusState private var titleFocused: Bool
    @FocusState private var queryFocused: Bool

    var body: some View {
        Group {
            if let to = model.addedTo { added(to) } else { form }
        }
        .frame(width: 440)
        .background(Theme.pane, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline))
        .onChange(of: model.focusTitle) { _, t in titleFocused = t; queryFocused = !t }
        .onChange(of: model.query) { _, _ in model.index = 0 }
        .onAppear { queryFocused = true }
    }

    private func added(_ to: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.ok).font(.system(size: 18))
            VStack(alignment: .leading, spacing: 1) {
                Text("Added").font(.system(size: 13, weight: .semibold))
                Text(to).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
        }.padding(14)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ADD TO NOTY").font(.system(size: 11, weight: .semibold)).tracking(0.6).foregroundStyle(.secondary)
                Spacer()
                Segmented(options: ItemKind.allCases.map { ($0, $0.label) }, selection: $model.kind)
            }
            if !model.captured.text.isEmpty {
                Text(model.captured.text).font(.system(size: 12.5)).lineLimit(4).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8).background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(alignment: .leading) { Rectangle().fill(Theme.highlight).frame(width: 3).clipShape(RoundedRectangle(cornerRadius: 2)) }
                if let src = model.captured.windowTitle ?? model.captured.app {
                    Label(src, systemImage: model.captured.url == nil ? "macwindow" : "link").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            TextField("Title", text: $model.title).textFieldStyle(.roundedBorder).focused($titleFocused)
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.system(size: 12))
                    TextField("Where? Type to filter, or Work/New category", text: $model.query).textFieldStyle(.plain).focused($queryFocused)
                }.padding(8)
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(model.choices.enumerated()), id: \.offset) { i, path in
                                row(path, selected: i == model.index).id(i).onTapGesture { model.index = i; model.add(askAgent: false) }
                            }
                        }
                    }.frame(height: min(CGFloat(max(model.choices.count, 1)) * 28, 168))
                    .onChange(of: model.index) { _, i in proxy.scrollTo(i) }
                }
            }
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.hairline))
            HStack(spacing: 8) {
                Toggle("Today", isOn: $model.today).toggleStyle(.checkbox).font(.system(size: 12))
                Spacer()
                Text("↑↓ choose  ⇥ title  ⌘1–4 type  ⌘↩ + agent").font(.system(size: 10.5)).foregroundStyle(.secondary)
                Button("Add ↩") { model.add(askAgent: false) }.buttonStyle(Pill(kind: .primary))
            }
        }.padding(14)
    }

    private func row(_ path: [String], selected: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: model.isNew(path) ? "plus.circle" : (path.count == 1 ? "folder" : "folder.fill")).font(.system(size: 11)).frame(width: 16)
            Text(path.joined(separator: " › ")).font(.system(size: 12.5, weight: path.count == 1 ? .semibold : .regular)).lineLimit(1)
            if model.isNew(path) { Badge(text: "new", kind: .accent) }
            Spacer()
        }
        .padding(.horizontal, 8).frame(height: 28)
        .foregroundStyle(selected ? Theme.onAccent : Color.primary)
        .background(selected ? Theme.accent : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
    }
}
