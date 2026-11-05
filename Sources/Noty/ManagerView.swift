// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import NotyKit

/// Panes of the Manager window. Named `Pane`, not `Section`: SwiftUI already has a `Section`.
enum Pane: String, CaseIterable, Identifiable {
    case library, settings, help
    var id: String { rawValue }
    var title: String { switch self { case .library: "Library"; case .settings: "Settings"; case .help: "Help" } }
    var symbol: String { switch self { case .library: "highlighter"; case .settings: "gearshape"; case .help: "questionmark.circle" } }
}

@MainActor @Observable
final class Nav {
    static let shared = Nav()
    var pane: Pane = .library
}

struct NewCategoryRequest: Identifiable { let id = UUID(); let parent: [String] }

/// The Manager window: a fixed sidebar (collapsible to icons) and a main pane that uses the full width.
struct ManagerView: View {
    var agentsTab = false
    let model = AppModel.shared
    let nav = Nav.shared
    @State private var newCategory: NewCategoryRequest?

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(newCategory: $newCategory)
            Divider()
            ZStack {
                Theme.pane
                VStack(spacing: 0) {
                    if let t = model.runningTask { TaskBanner(task: t) }
                    detail
                }
            }
            .overlay(alignment: .bottom) { ToastView() }
        }
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 900, minHeight: 560)
        .sheet(item: $newCategory) { NewCategorySheet(parent: $0.parent) }
        .onAppear { model.setManagerVisible(true) }
    }

    @ViewBuilder private var detail: some View {
        switch nav.pane {
        case .library: LibraryPane()
        case .settings: SettingsPane(initialTab: agentsTab ? .agents : .general)
        case .help: HelpPane()
        }
    }
}

struct Sidebar: View {
    let nav = Nav.shared
    let prefs = Prefs.shared
    let lib = LibraryModel.shared
    @Binding var newCategory: NewCategoryRequest?
    var collapsed: Bool { prefs.sidebarCollapsed }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Spacer()
                Button { withAnimation(.easeInOut(duration: 0.18)) { prefs.sidebarCollapsed.toggle() } } label: {
                    Image(systemName: "sidebar.left").foregroundStyle(.secondary)
                }.buttonStyle(.plain).help(collapsed ? "Expand sidebar" : "Collapse to icons").accessibilityLabel(collapsed ? "Expand sidebar" : "Collapse sidebar")
            }.padding(.top, 14).padding(.bottom, 12).padding(.horizontal, collapsed ? 0 : 6)

            row(.inbox, count: lib.inboxCount)
            row(.today, count: lib.todayCount)
            row(.all, count: nil)
            row(.agent, count: lib.proposals.count)
            row(.done, count: nil)

            if !collapsed {
                HStack {
                    SectionLabel("Workspaces")
                    Spacer()
                    Button { newCategory = NewCategoryRequest(parent: []) } label: { Image(systemName: "plus").font(.system(size: 11, weight: .semibold)).frame(width: 22, height: 22).contentShape(Rectangle()) }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help("New workspace").accessibilityLabel("New workspace")
                }.padding(.top, 14).padding(.leading, 8)
                ScrollView { VStack(spacing: 1) { ForEach(visibleCategories) { treeRow($0) } } }
            }
            Spacer(minLength: 8)
            ForEach([Pane.settings, .help]) { paneItem($0) }
            if !collapsed {
                Text("App memory \(AppMemory.footprint)").font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.top, 8)
            }
        }
        .padding(.horizontal, 10).padding(.bottom, 12)
        .padding(.top, 20)   // room for the traffic lights
        .frame(width: collapsed ? 62 : 232)
        .background(Theme.sidebar)
    }

    private var visibleCategories: [CategoryNode] {
        lib.categories.filter { c in
            c.path != [NotyStore.inbox] && (1..<max(c.path.count, 1)).allSatisfy { lib.expanded.contains(c.path.prefix($0).joined(separator: "/")) }
        }
    }

    private func hasChildren(_ c: CategoryNode) -> Bool { lib.categories.contains { $0.path.count == c.path.count + 1 && $0.path.starts(with: c.path) } }

    private func rowLabel(symbol: String, title: String, count: Int?, on: Bool, indent: CGFloat = 0) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol).font(.system(size: 13)).frame(width: 20)
            if !collapsed {
                Text(title).font(.system(size: 13, weight: on ? .semibold : .regular)).lineLimit(1)
                Spacer(minLength: 4)
                if let count, count > 0 { Text("\(count)").font(.system(size: 11.5)).monospacedDigit().foregroundStyle(.secondary) }
            }
        }
        .padding(.leading, 10 + indent).padding(.trailing, 10).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: collapsed ? .center : .leading)
        .foregroundStyle(Color.primary.opacity(on ? 1 : 0.85))
        .background(on ? Theme.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 7))
        .contentShape(RoundedRectangle(cornerRadius: 7))   // whole row (incl. padding and empty space) is clickable
    }

    private func row(_ s: Scope, count: Int?) -> some View {
        let on = nav.pane == .library && lib.scope == s
        return Button { nav.pane = .library; lib.scope = s; lib.selectedID = nil } label: { rowLabel(symbol: s.symbol, title: s.title, count: count, on: on) }
            .buttonStyle(.plain).help(s.title).accessibilityLabel(s.title)
    }

    private func treeRow(_ c: CategoryNode) -> some View {
        let on = nav.pane == .library && lib.scope == .category(c.path)
        let key = c.id
        let open = lib.expanded.contains(key)
        return HStack(spacing: 0) {
            Button { if open { lib.expanded.remove(key) } else { lib.expanded.insert(key) } } label: {
                Image(systemName: hasChildren(c) ? (open ? "chevron.down" : "chevron.right") : "circle.fill")
                    .font(.system(size: hasChildren(c) ? 9 : 4, weight: .bold)).foregroundStyle(.secondary).frame(width: 18, height: 26).contentShape(Rectangle())
            }.buttonStyle(.plain).padding(.leading, CGFloat(c.depth) * 14 + 4).accessibilityLabel(open ? "Collapse" : "Expand")
            Button { nav.pane = .library; lib.scope = .category(c.path); lib.selectedID = nil; if hasChildren(c) { lib.expanded.insert(key) } } label: {
                HStack(spacing: 6) {
                    Text(c.name).font(.system(size: 13, weight: c.depth == 0 || on ? .semibold : .regular)).lineLimit(1)
                    Spacer(minLength: 4)
                    let n = lib.count(in: c.path)
                    if n > 0 { Text("\(n)").font(.system(size: 11.5)).monospacedDigit().foregroundStyle(.secondary) }
                }
                .padding(.horizontal, 6).padding(.vertical, 5).frame(maxWidth: .infinity, alignment: .leading)
                .background(on ? Theme.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 7)).contentShape(RoundedRectangle(cornerRadius: 7))
            }.buttonStyle(.plain)
        }
        .contextMenu {
            Button("New category inside “\(c.name)”") { newCategory = NewCategoryRequest(parent: c.path) }
            Button("Delete “\(c.name)”", role: .destructive) { lib.deleteCategory(c.path) }
        }
    }

    private func paneItem(_ p: Pane) -> some View {
        let on = nav.pane == p
        return Button { nav.pane = p } label: {
            HStack(spacing: 9) {
                Image(systemName: p.symbol).font(.system(size: 14)).frame(width: 20)
                if !collapsed {
                    Text(p.title).font(.system(size: 13, weight: on ? .semibold : .regular)).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 4)
                    if p == .settings, Updater.shared.available != nil { Circle().fill(Theme.highlight).frame(width: 7, height: 7) }
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: collapsed ? .center : .leading)
            .foregroundStyle(Color.primary.opacity(on ? 1 : 0.85))
            .background(on ? Theme.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain).help(p.title).accessibilityLabel(p.title)
    }
}

struct NewCategorySheet: View {
    let parent: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(parent.isEmpty ? "New workspace" : "New category in \(parent.joined(separator: " › "))").font(.system(size: 15, weight: .semibold))
            TextField("Name", text: $name).textFieldStyle(.roundedBorder).onSubmit(create)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(Pill()).keyboardShortcut(.cancelAction)
                Button("Create") { create() }.buttonStyle(Pill(kind: .primary)).keyboardShortcut(.defaultAction).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }.padding(20).frame(width: 340)
    }
    private func create() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        LibraryModel.shared.createCategory(parent + [n]); dismiss()
    }
}
