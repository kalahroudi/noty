// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import NotyKit

struct AgentRequest: Identifiable { let id = UUID(); let items: [Item] }
struct DetailRequest: Identifiable { let id: String }

/// Items of the selected scope on the left, the selected item's details on the right.
struct LibraryPane: View {
    let lib = LibraryModel.shared
    @State private var request: AgentRequest?
    @State private var quickTitle = ""
    @State private var detail: DetailRequest?

    var body: some View {
        if lib.scope == .agent { AgentResultsPane() } else { itemsPane }
    }

    private var itemsPane: some View {
        let items = lib.visibleItems()
        return HStack(spacing: 0) {
            VStack(spacing: 0) {
                PaneHeader(title: lib.query.isEmpty ? lib.scope.title : "Search", subtitle: subtitle(items.count)) {
                    HStack(spacing: 8) {
                        SearchBox(prompt: "Search everything", text: Bindable(lib).query).frame(width: 160)
                        Button { lib.snip(into: nil) } label: { Label("Snip", systemImage: "viewfinder") }.buttonStyle(Pill()).fixedSize()
                            .help("Drag over an area of the screen. It is saved as a new task you can edit.")
                        Button { request = AgentRequest(items: Array(items.prefix(25))) } label: { Label("Ask agent", systemImage: "sparkles") }
                            .buttonStyle(Pill(kind: .primary)).disabled(items.isEmpty).fixedSize()
                    }.fixedSize(horizontal: false, vertical: true)
                }
                if !lib.loaded { SkeletonList(rows: 7).frame(maxHeight: .infinity, alignment: .top).padding(.top, 20) }
                else { list(items) }
            }
            if let it = lib.item(lib.selectedID) {
                Divider()
                InspectorView(item: it, ask: { request = AgentRequest(items: [$0]) }, expand: { detail = DetailRequest(id: it.id) }).id(it.id).frame(width: 360)
            }
        }
        .sheet(item: $request) { AskAgentSheet(items: $0.items) }
        .sheet(item: $detail) { ItemDetailView(id: $0.id) }
        .onChange(of: lib.askAgentFor) { _, id in
            if let id, let it = lib.item(id) { request = AgentRequest(items: [it]); lib.selectedID = id }
            lib.askAgentFor = nil
        }
    }

    private func subtitle(_ n: Int) -> String {
        if lib.conflicts > 0 { return "\(n) item\(n == 1 ? "" : "s") · \(lib.conflicts) sync conflict\(lib.conflicts == 1 ? "" : "s") kept in _history" }
        return "\(n) item\(n == 1 ? "" : "s")"
    }

    @ViewBuilder private func list(_ items: [Item]) -> some View {
        let groups = Dictionary(grouping: items, by: \.pathLabel).sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                if lib.scope != .done, lib.query.isEmpty { quickAdd }
                if items.isEmpty { empty }
                ForEach(groups, id: \.key) { g in
                    if groups.count > 1 || lib.scope != .category(g.value[0].path) {
                        Text(g.key.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.5).foregroundStyle(.secondary).padding(.top, 12).padding(.leading, 10)
                    }
                    ForEach(g.value) { it in ItemRow(item: it, open: { detail = DetailRequest(id: $0) }) }
                }
            }.padding(.horizontal, 14).padding(.vertical, 12)
        }
    }

    private var quickAdd: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus").foregroundStyle(.secondary).font(.system(size: 12)).frame(width: 17)
            TextField("Add to \(lib.scope == .all || lib.scope == .today ? NotyStore.inbox : lib.scope.title)…", text: $quickTitle).textFieldStyle(.plain).onSubmit(addQuick)
        }.padding(10).background(Theme.card, in: RoundedRectangle(cornerRadius: 9)).overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.hairline))
    }

    private func addQuick() {
        let t = quickTitle.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        var path = [NotyStore.inbox]
        if case .category(let p) = lib.scope { path = p }
        if let saved = lib.add(Item(title: t, today: lib.scope == .today, path: path)) { lib.selectedID = saved.id }
        quickTitle = ""
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "highlighter").font(.system(size: 26)).foregroundStyle(.secondary)
            Text(lib.query.isEmpty ? "Nothing here yet" : "No matches").font(.system(size: 14, weight: .semibold))
            Text(lib.query.isEmpty ? "Select text in any app and press \(Prefs.shared.hotkey.label) to add it here." : "Try a different word.")
                .font(.system(size: 12.5)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).padding(.top, 50)
    }
}

struct ItemRow: View {
    let item: Item
    var open: (String) -> Void = { _ in }
    let lib = LibraryModel.shared
    @State private var hover = false

    var body: some View {
        let on = lib.selectedID == item.id
        HStack(alignment: .top, spacing: 10) {
            Button { lib.toggleDone(item.id) } label: {
                Image(systemName: item.done ? "checkmark.square.fill" : "square").font(.system(size: 16))
                    .foregroundStyle(item.done ? Theme.ok : Color.secondary).frame(width: 24, height: 24).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(item.done ? "Mark as not done" : "Mark as done")
            Button { lib.selectedID = item.id } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title).font(.system(size: 13.5, weight: .medium)).strikethrough(item.done).foregroundStyle(item.done ? .secondary : .primary).lineLimit(2)
                    if !item.previewText.isEmpty {
                        Text(item.previewText).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1).padding(.leading, 7)
                            .overlay(alignment: .leading) { Rectangle().fill(Theme.highlight).frame(width: 2.5).clipShape(RoundedRectangle(cornerRadius: 1)) }
                    }
                    HStack(spacing: 6) {
                        KindBadge(kind: item.kind)
                        if item.today { Badge(text: "Today", kind: .warn) }
                        if !item.attachments.isEmpty { Label("\(item.attachments.filter { !$0.hasSuffix(".html") }.count)", systemImage: "paperclip").font(.system(size: 11)).foregroundStyle(.secondary) }
                        if let a = item.sourceApp { SourceLabel(app: a, hasLink: item.sourceURL != nil) }
                        ForEach(item.tags.prefix(3), id: \.self) { Badge(text: "#\($0)", kind: .neutral) }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(on ? Theme.card : (hover ? Theme.fill : .clear), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(on ? Theme.hairline : .clear))
        .contentShape(RoundedRectangle(cornerRadius: 9))
        .onHover { hover = $0 }
        .simultaneousGesture(TapGesture(count: 2).onEnded { open(item.id) })
        .contextMenu { Button { open(item.id) } label: { Label("Open full view", systemImage: "arrow.up.left.and.arrow.down.right") }; Divider(); copyMenu(item); Divider(); Button(item.done ? "Mark as not done" : "Mark as done") { lib.toggleDone(item.id) } }
    }
}

struct InspectorView: View {
    let item: Item
    var ask: (Item) -> Void
    var expand: () -> Void = {}
    let lib = LibraryModel.shared
    @State private var draft: Item
    @State private var tagText: String
    @State private var saveTask: Task<Void, Never>?
    @State private var confirmDelete = false
    @State private var dropTargeted = false

    init(item: Item, ask: @escaping (Item) -> Void, expand: @escaping () -> Void = {}) {
        self.item = item; self.ask = ask; self.expand = expand
        _draft = State(initialValue: item); _tagText = State(initialValue: item.tags.joined(separator: ", "))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Title", text: $draft.title, axis: .vertical).textFieldStyle(.plain).font(.system(size: 17, weight: .semibold)).lineLimit(1...4)
                    .padding(.bottom, 2)
                HStack(spacing: 6) {
                    MenuField(symbol: draft.kind.symbol, value: draft.kind.label) {
                        ForEach(ItemKind.allCases, id: \.self) { k in Button { draft.kind = k } label: { Label(k.label, systemImage: k.symbol) } }
                    }.frame(maxWidth: 120)
                    ToggleChip(title: "Today", symbol: "sun.max", isOn: $draft.today)
                    Spacer(minLength: 0)
                    ToggleChip(title: "Done", symbol: draft.done ? "checkmark.circle.fill" : "circle", isOn: $draft.done)
                }
                HStack(spacing: 6) {
                    Button { copyText(item.deepLink, "Link copied. Paste it anywhere to open this item in Noty.") } label: { Label("Link", systemImage: "link").lineLimit(1) }.buttonStyle(Pill()).help("Copy a noty:// link to this item")
                    Button { copyText(item.agentReference(store: lib.store), "Copied for your agent. It includes the id the Noty tools understand.") } label: { Label("For agent", systemImage: "sparkles").lineLimit(1) }.buttonStyle(Pill()).help("Copy a ready-to-paste reference for an AI agent")
                    Button { expand() } label: { Label("Open", systemImage: "arrow.up.left.and.arrow.down.right").lineLimit(1) }.buttonStyle(Pill()).help("See everything at full size")
                    Menu {
                        copyMenu(item)
                        Divider()
                        Button(role: .destructive) { confirmDelete = true } label: { Label("Delete item…", systemImage: "trash") }
                    } label: { Image(systemName: "ellipsis").frame(width: 22, height: 22) }.menuStyle(.button).menuIndicator(.hidden).fixedSize()
                }.font(.system(size: 12))

                group("Category") {
                    MenuField(symbol: "folder", value: draft.path.joined(separator: " › ")) {
                        ForEach(lib.allCategoryPaths, id: \.self) { p in Button(p.joined(separator: " › ")) { draft.path = p } }
                    }
                }

                if !quoteText.isEmpty {
                    group("Highlighted") {
                        MarkdownView(text: quoteText)
                            .frame(maxHeight: 190, alignment: .top).clipped()
                            .padding(9).background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(alignment: .bottomTrailing) { Button("Show all") { expand() }.buttonStyle(.plain).font(.system(size: 11, weight: .semibold)).padding(6).background(.regularMaterial, in: Capsule()).padding(6).opacity(quoteText.count > 220 ? 1 : 0) }
                            .overlay(alignment: .leading) { Rectangle().fill(Theme.highlight).frame(width: 3).clipShape(RoundedRectangle(cornerRadius: 2)) }
                    }
                }

                group("Notes") { NotesEditor(markdown: $draft.notes) }

                group("Attachments") { attachments }

                if draft.sourceApp != nil || draft.sourceURL != nil {
                    group("Source") {
                        HStack(spacing: 6) {
                            Image(systemName: draft.sourceURL == nil ? "arrow.up.forward.app" : "link").foregroundStyle(.secondary)
                            if let u = draft.sourceURL, let url = URL(string: u) { Link(draft.sourceTitle ?? u, destination: url).lineLimit(1) }
                            else { Text(draft.sourceTitle ?? draft.sourceApp ?? "").lineLimit(1) }
                            if let a = draft.sourceApp, draft.sourceURL != nil || draft.sourceTitle != nil { Text("· \(a)").foregroundStyle(.secondary) }
                        }.font(.system(size: 12))
                    }
                }

                group("Tags") { TextField("comma, separated", text: $tagText).fieldBox() }

                group("Ask an agent") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                        ForEach(AgentAction.allCases) { a in
                            Button { flush(); AgentSheetPreset.shared.action = a; ask(draft) } label: { Label(a.label, systemImage: a.symbol).font(.system(size: 11.5)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading) }
                                .buttonStyle(Pill())
                        }
                    }
                }
                Color.clear.frame(height: 0)
                    .confirmationDialog("Delete “\(draft.title)”?", isPresented: $confirmDelete) {
                        Button("Move to Trash", role: .destructive) { lib.delete(item.id) }
                    } message: { Text("The file goes to the Trash, so you can still get it back.") }
            }.padding(16)
        }
        .scrollIndicators(.hidden)
        .background(Theme.pane)
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            for p in providers { _ = p.loadObject(ofClass: URL.self) { url, _ in if let url { Task { @MainActor in lib.attach(fileAt: url, to: item.id) } } } }
            return true
        }
        .overlay { if dropTargeted { RoundedRectangle(cornerRadius: 10).stroke(Theme.highlight, style: StrokeStyle(lineWidth: 2, dash: [6])).padding(6).allowsHitTesting(false) } }
        .onChange(of: draft) { _, _ in schedule() }
        .onChange(of: tagText) { _, t in draft.tags = t.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
        .onChange(of: item.done) { _, d in if draft.done != d { draft.done = d } }
        .onChange(of: item.attachments) { _, a in if draft.attachments != a { draft.attachments = a } }
        .onDisappear { flush() }
    }

    private func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) { SectionLabel(title); content() }
    }

    /// Pictures and files that belong to the task: add from disk, snip the screen, paste, or drop files on the pane.
    private var attachments: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button { chooseFiles() } label: { Label("Add file", systemImage: "paperclip").lineLimit(1) }.buttonStyle(Pill()).help("Attach a file or picture")
                Button { lib.snip(into: item.id) } label: { Label("Screenshot", systemImage: "viewfinder").lineLimit(1) }.buttonStyle(Pill()).help("Drag over an area of the screen to attach it")
                Button { pasteImage() } label: { Image(systemName: "doc.on.clipboard").frame(width: 14) }.buttonStyle(Pill()).help("Attach the picture on the clipboard").accessibilityLabel("Paste picture")
            }.font(.system(size: 12))
            if !draft.imageAttachments.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 6)], spacing: 6) {
                    ForEach(draft.imageAttachments, id: \.self) { name in
                        if let img = NSImage(contentsOf: lib.store.attachmentURL(name)) {
                            Button { expand() } label: {
                                Image(nsImage: img).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 110)
                                    .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 7)).overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.hairline))
                            }.buttonStyle(.plain).help("View full size").accessibilityLabel("View image full size")
                            .overlay(alignment: .topTrailing) { removeButton(name) }
                        }
                    }
                }
            }
            ForEach(draft.otherAttachments, id: \.self) { name in
                HStack(spacing: 6) {
                    Button { NSWorkspace.shared.open(lib.store.attachmentURL(name)) } label: {
                        HStack(spacing: 6) { Image(systemName: name.hasSuffix(".pdf") ? "doc.richtext" : "doc"); Text(name).lineLimit(1).truncationMode(.middle); Spacer(); Image(systemName: "arrow.up.right.square").foregroundStyle(.secondary) }.contentShape(Rectangle())
                    }.buttonStyle(.plain).help("Open file")
                    removeButton(name, floating: false)
                }.font(.system(size: 12)).padding(8).background(Theme.card, in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.hairline))
            }
            if draft.attachments.isEmpty { Text("Drop files here, or use the buttons above.").font(.system(size: 11.5)).foregroundStyle(.secondary) }
        }
    }

    private func removeButton(_ name: String, floating: Bool = true) -> some View {
        Button { lib.removeAttachment(name, from: item.id) } label: {
            Image(systemName: "xmark.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.55)).font(.system(size: 15))
        }.buttonStyle(.plain).padding(floating ? 4 : 0).help("Remove").accessibilityLabel("Remove attachment")
    }

    private func chooseFiles() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        panel.prompt = "Attach"
        if panel.runModal() == .OK { panel.urls.forEach { lib.attach(fileAt: $0, to: item.id) } }
    }

    private func pasteImage() {
        if let png = Snip.clipboardImage() { lib.attach(png, ext: "png", to: item.id) }
        else { AppModel.shared.show("There's no picture on the clipboard.", error: true) }
    }

    private func label(_ s: String) -> some View { SectionLabel(s) }

    /// The highlighted text without picture placeholders; the pictures are shown as thumbnails below.
    private var quoteText: String {
        draft.quote.replacingOccurrences(of: #"!\[[^\]]*\]\(attachment:\d+\)"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func schedule() {
        saveTask?.cancel()
        saveTask = Task { try? await Task.sleep(for: .milliseconds(500)); if !Task.isCancelled { flush() } }
    }

    private func flush() {
        saveTask?.cancel()
        if draft != item, lib.item(item.id) != nil { lib.update(draft) }
    }
}

/// Copy formats for an item, shared by the inspector and the row's context menu.
@MainActor func copyMenu(_ item: Item) -> some View {
    let store = LibraryModel.shared.store
    return Group {
        Button { copyText(item.deepLink, "Link copied. Paste it anywhere to open this item in Noty.") } label: { Label("Copy link", systemImage: "link") }
        Button { copyText(item.agentReference(store: store), "Copied for your agent. It includes the id the Noty tools understand.") } label: { Label("Copy for agent", systemImage: "sparkles") }
        Button { copyText(item.markdown(store: store), "Markdown copied.") } label: { Label("Copy as Markdown", systemImage: "doc.text") }
        Button {
            let html = item.htmlAttachment.flatMap { try? Data(contentsOf: store.attachmentURL($0)) }
            ClipboardContent.writeFormatted(markdown: item.resolvedQuote(store: nil), html: html, plain: item.plainQuote, to: .general)
            AppModel.shared.show("Copied with formatting. Paste into Word, Mail or Pages.")
        } label: { Label("Copy with formatting", systemImage: "textformat") }
        Divider()
        Button { copyText(item.title, "Title copied.") } label: { Label("Copy title", systemImage: "textformat") }
        if !item.quote.isEmpty { Button { copyText(item.plainQuote, "Highlighted text copied.") } label: { Label("Copy highlighted text", systemImage: "highlighter") } }
        if !item.notes.isEmpty { Button { copyText(item.notes, "Notes copied.") } label: { Label("Copy notes", systemImage: "note.text") } }
    }
}

@MainActor func copyText(_ text: String, _ message: String) { Clipboard.copy(text); AppModel.shared.show(message) }

/// Lets an inspector button pick the agent action the sheet opens with.
@MainActor final class AgentSheetPreset { static let shared = AgentSheetPreset(); var action: AgentAction? }

struct AskAgentSheet: View {
    let items: [Item]
    @Environment(\.dismiss) private var dismiss
    @State private var action: AgentAction = AgentSheetPreset.shared.action ?? .review
    @State private var extra = ""
    @State private var copied = false

    private var prompt: String { AgentPrompt.build(action, items: items, extra: extra) }
    private var claude: String? { Shell.find("claude") }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ask an agent").font(.system(size: 16, weight: .semibold))
            Text(items.count == 1 ? "“\(items[0].title)”" : "\(items.count) items in view").font(.system(size: 12.5)).foregroundStyle(.secondary).lineLimit(1)
            Segmented(options: AgentAction.allCases.map { ($0, $0.label) }, selection: $action)
            TextField("Extra instructions (optional)", text: $extra).textFieldStyle(.roundedBorder)
            SectionLabel("Prompt")
            ScrollView { Text(prompt).font(.system(size: 11.5, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(10) }
                .frame(height: 170).background(Theme.card, in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.hairline))
            Text("The agent reads and updates your items through the Noty MCP tools. Files it wants to create show up under Agent results for you to approve. Connect your agents in Settings → Agents.")
                .font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Close") { dismiss() }.buttonStyle(Pill()).keyboardShortcut(.cancelAction)
                Spacer()
                Button(copied ? "Copied" : "Copy prompt") { Clipboard.copy(prompt); copied = true }.buttonStyle(Pill())
                Button { run() } label: { Label("Run in Claude Code", systemImage: "terminal") }.buttonStyle(Pill(kind: .primary)).disabled(claude == nil)
                    .help(claude == nil ? "Claude Code isn't installed. Copy the prompt into any agent instead." : "Opens Terminal in your library folder and starts Claude Code with this prompt")
            }
        }.padding(20).frame(width: 560)
        .onDisappear { AgentSheetPreset.shared.action = nil }
    }

    /// Hands off to the user's own terminal (no embedded terminal): the prompt goes through a file so quoting can never break it.
    private func run() {
        do {
            let file = AppPaths().root.appendingPathComponent("prompt.txt")
            try AppPaths().ensureDirectories()
            try Data(prompt.utf8).write(to: file, options: .atomic)
            let lib = LibraryModel.shared.store.root.path.replacingOccurrences(of: "'", with: "'\\''")
            let cmd = "cd '\(lib)' && claude \"$(cat '\(file.path)')\"".replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            var err: NSDictionary?
            NSAppleScript(source: "tell application \"Terminal\"\nactivate\ndo script \"\(cmd)\"\nend tell")?.executeAndReturnError(&err)
            if let err { throw UserFacingError("Couldn't open Terminal. Allow Noty under Privacy & Security → Automation, or copy the prompt instead. (\(err))") }
            dismiss()
        } catch {
            AppLog.error(error, context: "Run in Claude Code")
            AppModel.shared.show("Couldn't start Claude Code. Copy the prompt and paste it into your agent instead.", error: true)
        }
    }
}

struct AgentResultsPane: View {
    let lib = LibraryModel.shared
    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(title: "Agent results", subtitle: "Files your agents want to write. Nothing is saved until you approve it.")
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if lib.proposals.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "sparkles").font(.system(size: 26)).foregroundStyle(.secondary)
                            Text("No proposals").font(.system(size: 14, weight: .semibold))
                            Text("Ask an agent to turn items into a skill or a Markdown file. Its proposal appears here.").font(.system(size: 12.5)).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity).padding(.top, 50)
                    }
                    ForEach(lib.proposals) { p in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack { Label(p.name, systemImage: "doc.text").font(.system(size: 13.5, weight: .semibold)); Spacer(); if p.completeItems { Badge(text: "finishes \(p.itemIds.count) item\(p.itemIds.count == 1 ? "" : "s")", kind: .accent) } }
                            if !p.note.isEmpty { Text(p.note).font(.system(size: 12.5)).foregroundStyle(.secondary) }
                            ScrollView { Text(p.content).font(.system(size: 11.5, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(10) }
                                .frame(maxHeight: 220).background(Theme.pane, in: RoundedRectangle(cornerRadius: 8))
                            HStack {
                                Button("Approve & write") { lib.approve(p) }.buttonStyle(Pill(kind: .primary))
                                Button("Discard") { lib.discard(p) }.buttonStyle(Pill())
                                Spacer()
                                Text("Saved to \(lib.store.filesDir.lastPathComponent)/\(p.name)").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }.card(padding: 14)
                    }
                }.padding(22).frame(maxWidth: 760, alignment: .leading)
            }
        }
    }
}
