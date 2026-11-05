// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import NotyKit

/// The whole item at full scale: formatted text, every image at its real size (with zoom), files, notes and source.
struct ItemDetailView: View {
    let id: String
    var startImage: Int?
    @Environment(\.dismiss) private var dismiss
    let lib = LibraryModel.shared
    @State private var zoom: Zoom = .fit
    @State private var title = ""
    @State private var notes = ""
    @State private var loadedEdits = false
    @State private var saveTask: Task<Void, Never>?
    enum Zoom: String, CaseIterable { case fit = "Fit", actual = "100%", double = "200%" }

    var body: some View {
        if let item = lib.item(id) { content(item) } else {
            VStack(spacing: 10) { Text("This item isn't in the library any more.").foregroundStyle(.secondary); Button("Close") { dismiss() }.buttonStyle(Pill()) }.padding(40)
        }
    }

    private func content(_ item: Item) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Title", text: $title, axis: .vertical).textFieldStyle(.plain).font(.system(size: 20, weight: .semibold)).lineLimit(1...3)
                    HStack(spacing: 6) {
                        KindBadge(kind: item.kind)
                        Text(item.pathLabel).font(.system(size: 12)).foregroundStyle(.secondary)
                        if let a = item.sourceApp { SourceLabel(app: a, hasLink: item.sourceURL != nil) }
                    }
                }
                Spacer()
                if !item.imageAttachments.isEmpty { Segmented(options: Zoom.allCases.map { ($0, $0.rawValue) }, selection: $zoom) }
                Menu { copyMenu(item) } label: { Label("Copy", systemImage: "doc.on.doc") }.menuStyle(.button).fixedSize()
                Button("Done") { dismiss() }.buttonStyle(Pill(kind: .primary)).keyboardShortcut(.cancelAction)
            }.padding(.horizontal, 20).padding(.vertical, 14)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !textOnly(item).isEmpty {
                        MarkdownView(text: textOnly(item), size: 14.5)
                            .padding(14).background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(alignment: .leading) { Rectangle().fill(Theme.highlight).frame(width: 3).clipShape(RoundedRectangle(cornerRadius: 2)) }
                    }
                    ForEach(item.imageAttachments, id: \.self) { full($0) }
                    SectionLabel("Notes"); NotesEditor(markdown: $notes, minHeight: 200)
                    if !item.otherAttachments.isEmpty {
                        SectionLabel("Files")
                        ForEach(item.otherAttachments, id: \.self) { name in
                            Button { NSWorkspace.shared.open(lib.store.attachmentURL(name)) } label: { Label(name, systemImage: name.hasSuffix(".pdf") ? "doc.richtext" : "doc").font(.system(size: 13)) }.buttonStyle(Pill())
                        }
                    }
                    if item.sourceApp != nil || item.sourceURL != nil {
                        SectionLabel("Source")
                        HStack(spacing: 6) {
                            if let u = item.sourceURL, let url = URL(string: u) { Link(item.sourceTitle ?? u, destination: url) } else { Text(item.sourceTitle ?? item.sourceApp ?? "") }
                            if let a = item.sourceApp { Text("· \(a)").foregroundStyle(.secondary) }
                        }.font(.system(size: 13))
                    }
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            }.scrollIndicators(.automatic)
        }
        .frame(minWidth: 760, idealWidth: 980, minHeight: 520, idealHeight: 760)
        .background(Theme.pane)
        .onAppear { title = item.title; notes = item.notes; loadedEdits = true }
        .onChange(of: title) { _, _ in scheduleSave() }
        .onChange(of: notes) { _, _ in scheduleSave() }
        .onDisappear { saveNow() }
    }

    /// The quote without picture placeholders: every picture is shown below at the chosen zoom instead.
    private func textOnly(_ item: Item) -> String {
        item.quote.replacingOccurrences(of: #"!\[[^\]]*\]\(attachment:\d+\)"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// An image at the chosen scale: fit to the window, or its real pixel size (2× is for reading small text).
    private func full(_ name: String) -> some View {
        let url = lib.store.attachmentURL(name)
        return Group {
            if let img = NSImage(contentsOf: url) {
                let px = img.representations.first.map { CGSize(width: $0.pixelsWide, height: $0.pixelsHigh) } ?? img.size
                let scale: CGFloat = zoom == .actual ? 0.5 : zoom == .double ? 1 : 0   // pixels at 2× display density, so 100% looks like the original
                if zoom == .fit { Image(nsImage: img).resizable().scaledToFit().frame(maxWidth: .infinity, alignment: .leading).clipShape(RoundedRectangle(cornerRadius: 8)) }
                else { ScrollView([.horizontal, .vertical]) { Image(nsImage: img).resizable().frame(width: px.width * scale, height: px.height * scale) }.frame(maxHeight: 560) }
            }
        }.overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.hairline))
    }

    private func scheduleSave() {
        guard loadedEdits else { return }
        saveTask?.cancel()
        saveTask = Task { try? await Task.sleep(for: .milliseconds(500)); if !Task.isCancelled { saveNow() } }
    }

    private func saveNow() {
        saveTask?.cancel()
        guard loadedEdits, var it = lib.item(id), it.title != title || it.notes != notes else { return }
        it.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? it.title : title; it.notes = notes
        lib.update(it)
    }
}
