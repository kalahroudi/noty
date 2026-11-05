// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import AppKit

/// Notes stay Markdown on disk (agents and humans read them), with a few inline tags for what Markdown can't say:
/// `**bold**`, `*italic*`, `~~strike~~`, `<u>underline</u>`, `<span style="color:#RRGGBB">`, `<span style="font-size:Npx">`.
enum NotesMarkdown {
    static let baseSize: CGFloat = 13
    /// Highlighter yellow, the same as the marker line on highlighted text everywhere else in Noty.
    static let highlightColor = NSColor(srgbRed: 0.96, green: 0.77, blue: 0.09, alpha: 0.42)

    // MARK: Markdown → attributed text

    static func attributed(_ md: String, size: CGFloat = baseSize) -> NSAttributedString {
        let out = NSMutableAttributedString()
        var bold = false, italic = false, strike = false, under = false, mark = false
        var colors: [NSColor] = [], sizes: [CGFloat] = []
        var spans: [Character] = []   // which kind each open <span> was: "c" color, "s" size
        let chars = Array(md); var i = 0; var buf = ""
        func flush() {
            guard !buf.isEmpty else { return }
            var traits: NSFontDescriptor.SymbolicTraits = []
            if bold { traits.insert(.bold) }; if italic { traits.insert(.italic) }
            let base = NSFont.systemFont(ofSize: sizes.last ?? size)
            let desc = base.fontDescriptor.withSymbolicTraits(traits)
            var a: [NSAttributedString.Key: Any] = [.font: NSFont(descriptor: desc, size: sizes.last ?? size) ?? base, .foregroundColor: colors.last ?? NSColor.labelColor]
            if strike { a[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if under { a[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            if mark { a[.backgroundColor] = highlightColor }
            out.append(NSAttributedString(string: buf, attributes: a)); buf = ""
        }
        func starts(_ s: String) -> Bool { i + s.count <= chars.count && String(chars[i..<(i + s.count)]) == s }
        while i < chars.count {
            let atLineStart = i == 0 || chars[i - 1] == "\n"
            if chars[i] == "\\", i + 1 < chars.count, "\\*~<".contains(chars[i + 1]) { buf.append(chars[i + 1]); i += 2; continue }
            if starts("**") { flush(); bold.toggle(); i += 2; continue }
            if chars[i] == "*", !(atLineStart && i + 1 < chars.count && chars[i + 1] == " ") { flush(); italic.toggle(); i += 1; continue }
            if starts("~~") { flush(); strike.toggle(); i += 2; continue }
            if starts("<mark>") { flush(); mark = true; i += 6; continue }
            if starts("</mark>") { flush(); mark = false; i += 7; continue }
            if starts("<u>") { flush(); under = true; i += 3; continue }
            if starts("</u>") { flush(); under = false; i += 4; continue }
            if starts("</span>") { flush(); if let k = spans.popLast() { if k == "c" { _ = colors.popLast() } else { _ = sizes.popLast() } }; i += 7; continue }
            if starts("<span style=\""), let close = chars[i...].firstIndex(of: ">") {
                let tag = String(chars[i...close])
                if let m = tag.range(of: #"color:#([0-9A-Fa-f]{6})"#, options: .regularExpression), let v = UInt32(tag[m].dropFirst(7), radix: 16) {
                    flush(); colors.append(Theme.rgb(v)); spans.append("c"); i = close + 1; continue
                }
                if let m = tag.range(of: #"font-size:(\d+)px"#, options: .regularExpression), let v = Double(tag[m].dropFirst(10).dropLast(2)) {
                    flush(); sizes.append(CGFloat(v)); spans.append("s"); i = close + 1; continue
                }
            }
            buf.append(chars[i]); i += 1
        }
        flush()
        return out
    }

    // MARK: Attributed text → Markdown

    static func markdown(_ text: NSAttributedString, size: CGFloat = baseSize) -> String {
        var md = ""
        let full = NSRange(location: 0, length: text.length)
        text.enumerateAttributes(in: full) { attrs, range, _ in
            let s = text.attributedSubstring(from: range).string
            let font = attrs[.font] as? NSFont
            let traits = font?.fontDescriptor.symbolicTraits ?? []
            let isBold = traits.contains(.bold), isItalic = traits.contains(.italic)
            let isMark = attrs[.backgroundColor] != nil
            let isStrike = (attrs[.strikethroughStyle] as? Int ?? 0) != 0, isUnder = (attrs[.underlineStyle] as? Int ?? 0) != 0
            let px = Int((font?.pointSize ?? size).rounded())
            let color = (attrs[.foregroundColor] as? NSColor).flatMap(hex)
            // Wrap each line on its own, with surrounding spaces kept outside the markers so Markdown still reads them.
            let lines = s.components(separatedBy: "\n")
            for (n, line) in lines.enumerated() {
                if n > 0 { md += "\n" }
                let core = line.trimmingCharacters(in: .whitespaces)
                if core.isEmpty { md += line; continue }
                let lead = String(line.prefix { $0 == " " || $0 == "\t" }), trail = String(line.reversed().prefix { $0 == " " || $0 == "\t" }.reversed())
                var t = escape(core)
                if isBold { t = "**\(t)**" }; if isItalic { t = "*\(t)*" }; if isStrike { t = "~~\(t)~~" }; if isUnder { t = "<u>\(t)</u>" }; if isMark { t = "<mark>\(t)</mark>" }
                if px != Int(size) { t = "<span style=\"font-size:\(px)px\">\(t)</span>" }
                if let c = color, c != hex(.labelColor) { t = "<span style=\"color:#\(c)\">\(t)</span>" }
                md += lead + t + trail
            }
        }
        return md
    }

    private static func escape(_ s: String) -> String {
        var o = ""
        for c in s { if "\\*~<".contains(c) { o.append("\\") }; o.append(c) }
        return o
    }

    private static func hex(_ c: NSColor) -> String? {
        guard let r = c.usingColorSpace(.sRGB) else { return nil }
        return String(format: "%02X%02X%02X", Int((r.redComponent * 255).rounded()), Int((r.greenComponent * 255).rounded()), Int((r.blueComponent * 255).rounded()))
    }
}

/// The text view behind the editor. It can reach the toolbar's actions without going through SwiftUI.
final class NotesTextView: NSTextView {
    func toggle(_ trait: NSFontDescriptor.SymbolicTraits) {
        applyToSelection { font in
            let has = font.fontDescriptor.symbolicTraits.contains(trait)
            var t = font.fontDescriptor.symbolicTraits
            if has { t.remove(trait) } else { t.insert(trait) }
            return NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(t), size: font.pointSize) ?? font
        }
    }

    func setSize(_ size: CGFloat) { applyToSelection { NSFont(descriptor: $0.fontDescriptor, size: size) ?? $0 } }

    func toggleAttribute(_ key: NSAttributedString.Key) {
        let r = selectedRange()
        if r.length == 0 {
            var a = typingAttributes
            if (a[key] as? Int ?? 0) != 0 { a.removeValue(forKey: key) } else { a[key] = NSUnderlineStyle.single.rawValue }
            typingAttributes = a; return
        }
        let on = (textStorage?.attribute(key, at: r.location, effectiveRange: nil) as? Int ?? 0) == 0
        guard shouldChangeText(in: r, replacementString: nil) else { return }
        if on { textStorage?.addAttribute(key, value: NSUnderlineStyle.single.rawValue, range: r) } else { textStorage?.removeAttribute(key, range: r) }
        didChangeText()
    }

    /// Marks the selection with the highlighter, or clears it when the whole selection is already marked.
    func setHighlight(_ on: Bool, range: NSRange? = nil) {
        let r = range ?? selectedRange()
        guard r.length > 0, shouldChangeText(in: r, replacementString: nil) else { return }
        if on { textStorage?.addAttribute(.backgroundColor, value: NotesMarkdown.highlightColor, range: r) } else { textStorage?.removeAttribute(.backgroundColor, range: r) }
        didChangeText()
    }

    func isHighlighted(_ r: NSRange) -> Bool {
        guard r.length > 0, let ts = textStorage else { return false }
        var all = true
        ts.enumerateAttribute(.backgroundColor, in: r) { v, _, stop in if v == nil { all = false; stop.pointee = true } }
        return all
    }

    func setColor(_ color: NSColor?) {
        let r = selectedRange(); let c = color ?? NSColor.labelColor
        if r.length == 0 { typingAttributes[.foregroundColor] = c; return }
        guard shouldChangeText(in: r, replacementString: nil) else { return }
        textStorage?.addAttribute(.foregroundColor, value: c, range: r)
        didChangeText()
    }

    private func applyToSelection(_ change: (NSFont) -> NSFont) {
        let r = selectedRange()
        if r.length == 0 {
            typingAttributes[.font] = change(typingAttributes[.font] as? NSFont ?? .systemFont(ofSize: NotesMarkdown.baseSize)); return
        }
        guard shouldChangeText(in: r, replacementString: nil), let ts = textStorage else { return }
        ts.beginEditing()
        ts.enumerateAttribute(.font, in: r) { v, sub, _ in ts.addAttribute(.font, value: change(v as? NSFont ?? .systemFont(ofSize: NotesMarkdown.baseSize)), range: sub) }
        ts.endEditing()
        didChangeText()
    }

    /// Pasting keeps the notes' look: plain text takes the base font, so notes never fill up with foreign styles.
    override func paste(_ sender: Any?) { pasteAsPlainText(sender) }
}

@MainActor @Observable final class NotesEditorHandle { weak var view: NotesTextView? }

struct RichNotesEditor: NSViewRepresentable {
    @Binding var markdown: String
    @Binding var contentHeight: CGFloat
    let handle: NotesEditorHandle
    var itemID: String?

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NotesTextView.scrollableTextView()
        let tv = NotesTextView(frame: .zero, textContainer: (scroll.documentView as? NSTextView)?.textContainer)
        scroll.documentView = tv
        tv.isRichText = true; tv.allowsUndo = true; tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 4, height: 6)
        tv.isVerticallyResizable = true; tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.delegate = context.coordinator
        tv.textStorage?.setAttributedString(NotesMarkdown.attributed(markdown))
        tv.typingAttributes = [.font: NSFont.systemFont(ofSize: NotesMarkdown.baseSize), .foregroundColor: NSColor.labelColor]
        scroll.drawsBackground = false; scroll.hasVerticalScroller = false
        handle.view = tv
        tv.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.measure), name: NSView.frameDidChangeNotification, object: tv)
        context.coordinator.textView = tv
        DispatchQueue.main.async { context.coordinator.measure() }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = scroll.documentView as? NotesTextView, tv.window?.firstResponder !== tv else { return }
        // Only an outside change (an agent edited the file) replaces the text; the user's own typing never loops back.
        if NotesMarkdown.markdown(tv.attributedString()) != markdown { tv.textStorage?.setAttributedString(NotesMarkdown.attributed(markdown)); DispatchQueue.main.async { context.coordinator.measure() } }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichNotesEditor
        weak var textView: NotesTextView?
        init(_ p: RichNotesEditor) { parent = p }
        func textDidChange(_ n: Notification) {
            guard let tv = n.object as? NSTextView else { return }
            parent.markdown = NotesMarkdown.markdown(tv.attributedString())
            measure()
        }
        /// The height the whole text needs at the current width, so the box can grow with it.
        private var pending: DispatchWorkItem?
        /// Selecting words offers Highlight, Remind me, Schedule and Ask AI once the selection has settled.
        func textViewDidChangeSelection(_ n: Notification) {
            guard let tv = n.object as? NotesTextView, let id = parent.itemID else { return }
            pending?.cancel()
            let r = tv.selectedRange()
            if r.length < 2 { SelectionPopover.shared.close(); return }
            let work = DispatchWorkItem { [weak tv] in
                guard let tv, tv.window?.firstResponder === tv, tv.selectedRange() == r else { return }
                SelectionPopover.shared.show(textView: tv, itemID: id)
            }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
        }

        @objc func measure() {
            guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer else { return }
            lm.ensureLayout(for: tc)
            let h = ceil(lm.usedRect(for: tc).height + tv.textContainerInset.height * 2)
            if abs(h - parent.contentHeight) > 0.5 { DispatchQueue.main.async { self.parent.contentHeight = h } }
        }
    }
}

/// Notes with a small formatting bar: bold, italic, underline, strike, size and colour.
struct NotesEditor: View {
    @Binding var markdown: String
    /// The box starts this tall and grows with the text, so long notes are never hidden behind a scroll.
    var minHeight: CGFloat = 110
    /// The item the notes belong to. With it, selecting words offers reminders.
    var itemID: String?
    @State private var contentHeight: CGFloat = 0
    @State private var handle = NotesEditorHandle()
    private static let colors: [(String, UInt32)] = [("Red", 0xD64545), ("Orange", 0xD9822B), ("Green", 0x2E9E5B), ("Blue", 0x2F6FED), ("Purple", 0x8A5CD6)]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                tool("bold", "Bold") { handle.view?.toggle(.bold) }
                tool("italic", "Italic") { handle.view?.toggle(.italic) }
                tool("underline", "Underline") { handle.view?.toggleAttribute(.underlineStyle) }
                tool("strikethrough", "Strikethrough") { handle.view?.toggleAttribute(.strikethroughStyle) }
                tool("highlighter", "Highlight") { if let tv = handle.view { tv.setHighlight(!tv.isHighlighted(tv.selectedRange())) } }
                Divider().frame(height: 14).padding(.horizontal, 3)
                Menu {
                    Button("Small") { handle.view?.setSize(11) }
                    Button("Normal") { handle.view?.setSize(NotesMarkdown.baseSize) }
                    Button("Large") { handle.view?.setSize(17) }
                    Button("Title") { handle.view?.setSize(22) }
                } label: { Image(systemName: "textformat.size").frame(width: 24, height: 22) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Text size")
                Menu {
                    Button("Default") { handle.view?.setColor(nil) }
                    Divider()
                    ForEach(Self.colors, id: \.0) { c in Button(c.0) { handle.view?.setColor(Theme.rgb(c.1)) } }
                } label: { Image(systemName: "paintpalette").frame(width: 24, height: 22) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Text colour")
                Spacer()
            }.padding(.horizontal, 6).padding(.vertical, 4)
            Divider()
            RichNotesEditor(markdown: $markdown, contentHeight: $contentHeight, handle: handle, itemID: itemID).frame(height: max(minHeight, contentHeight)).padding(.horizontal, 4)
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.hairline))
    }

    private func tool(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 12, weight: .medium)).frame(width: 24, height: 22).contentShape(Rectangle()) }
            .buttonStyle(.plain).help(help).accessibilityLabel(help)
    }
}
