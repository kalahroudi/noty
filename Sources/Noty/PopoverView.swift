// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import NotyKit

/// The menu bar popover: quick add, today's items and unsorted captures, a way into the Manager.
/// Nothing runs while it is closed (AppDelegate drops the views on close).
struct PopoverView: View {
    let model = AppModel.shared
    let lib = LibraryModel.shared
    var openManager: (Pane) -> Void
    @State private var quick = ""

    var body: some View {
        VStack(spacing: 12) {
            header
            if !lib.loaded { SkeletonList(rows: 4).frame(height: 140) } else { content }
            if let task = model.runningTask { TaskStrip(task: task) }
            footer
        }
        .padding(14)
        .frame(width: 360)
        .background(Theme.pane)                                   // an opaque themed background: the popover must follow the app theme
        .overlay(alignment: .bottom) { ToastView() }
        .onDrop(of: [.fileURL], isTargeted: nil) { lib.createTask(fromDrop: $0) }
        .onAppear { model.setPopoverVisible(true) }
        .onDisappear { model.setPopoverVisible(false) }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: AppIcon.image(size: 34)).resizable().frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text("Noty").font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Text(model.status).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
            }.layoutPriority(-1)
            Spacer(minLength: 4)
            Button { AppDelegate.shared.closePopover(); lib.snip(into: nil) } label: { Image(systemName: "viewfinder").font(.system(size: 13)).frame(width: 14, height: 16) }
                .buttonStyle(Pill()).help("Snip: drag over an area of the screen. It is saved as a new task.").accessibilityLabel("Snip a screen area")
            Button { CaptureController.shared.present(Captured()) } label: { Label("Capture", systemImage: "highlighter").font(.system(size: 12)).lineLimit(1).fixedSize() }
                .buttonStyle(Pill()).help("Opens the capture panel. Select text in another app and press \(Prefs.shared.hotkey.label) to capture it.")
        }
    }

    private var content: some View {
        let today = lib.items.filter { $0.today && !$0.done }
        let inbox = lib.items.filter { $0.path.first == NotyStore.inbox && !$0.done && !$0.today }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "plus").foregroundStyle(.secondary).font(.system(size: 12))
                TextField("Quick add to Inbox…", text: $quick).textFieldStyle(.plain).onSubmit {
                    let t = quick.trimmingCharacters(in: .whitespaces)
                    if !t.isEmpty { lib.add(Item(title: t)); quick = "" }
                }
            }.padding(9).background(Theme.card, in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.hairline))
            if today.isEmpty && inbox.isEmpty {
                Text("All clear. Select text anywhere and press \(Prefs.shared.hotkey.label).").font(.system(size: 12.5)).foregroundStyle(.secondary).padding(.vertical, 6)
            }
            group("Today", today)
            group("Inbox", inbox)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func group(_ title: String, _ items: [Item]) -> some View {
        if !items.isEmpty {
            SectionLabel("\(title) · \(items.count)").padding(.top, 4)
            ForEach(items.prefix(5)) { it in
                HStack(spacing: 8) {
                    Button { lib.toggleDone(it.id) } label: { Image(systemName: "square").foregroundStyle(.secondary).frame(width: 22, height: 22).contentShape(Rectangle()) }
                        .buttonStyle(.plain).accessibilityLabel("Mark as done")
                    Button { lib.scope = it.path.first == NotyStore.inbox ? .inbox : .category(it.path); lib.selectedID = it.id; openManager(.library) } label: {
                        HStack { Text(it.title).font(.system(size: 12.5)).lineLimit(1); Spacer(); Text(it.path.last ?? "").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1) }
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }.padding(.horizontal, 4).frame(height: 26)
            }
            if items.count > 5 { Text("+ \(items.count - 5) more").font(.system(size: 11.5)).foregroundStyle(.secondary).padding(.leading, 4) }
        }
    }

    private var footer: some View {
        HStack {
            Button("Open Noty") { openManager(.library) }.buttonStyle(Pill(kind: .primary))
            Spacer()
            Button { openManager(.settings) } label: { Image(systemName: "gearshape").frame(width: 26, height: 26).contentShape(Rectangle()) }.buttonStyle(.plain).foregroundStyle(.secondary).help("Settings").accessibilityLabel("Settings")
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power").frame(width: 26, height: 26).contentShape(Rectangle()) }.buttonStyle(.plain).foregroundStyle(.secondary).help("Quit Noty").accessibilityLabel("Quit")
        }
    }
}
