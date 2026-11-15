// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import NotyKit

/// Shows Markdown with its structure: headings, bold/italic/links/code, lists and task lists, quotes, code blocks, tables, rules and pictures.
/// It also reads what gets pasted into notes from agents and terminals: the notes' inline tags (`<u>`, `<mark>`, colour and size spans),
/// simple inline HTML, whole HTML documents (converted first), and terminal drawings (box tables, `⎿` tool output) kept monospaced.
struct MarkdownView: View {
    let text: String
    var imageURL: (Int) -> URL? = { _ in nil }
    var size: CGFloat = 12.5
    var maxImageHeight: CGFloat = 220
    var onImageTap: ((Int) -> Void)?

    private enum Block {
        case heading(Int, String), paragraph(String), bullet(Int, String, String), task(Int, Bool, String), quote(String)
        case code(String, String), terminal(String), table([[String]]), rule, image(Int)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks().enumerated()), id: \.offset) { _, b in view(b) }
        }.frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
    }

    @ViewBuilder private func view(_ b: Block) -> some View {
        switch b {
        case .heading(let l, let t): inline(t).font(.system(size: size + CGFloat(max(0, 4 - l)) * 1.6, weight: .semibold)).padding(.top, 2)
        case .paragraph(let t): inline(t).font(.system(size: size)).fixedSize(horizontal: false, vertical: true)
        case .bullet(let indent, let marker, let t):
            HStack(alignment: .firstTextBaseline, spacing: 6) { Text(marker).foregroundStyle(.secondary); inline(t) }.font(.system(size: size)).padding(.leading, CGFloat(indent) * 14)
        case .task(let indent, let done, let t):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: done ? "checkmark.square.fill" : "square").foregroundStyle(done ? Theme.highlight : .secondary)
                inline(t).strikethrough(done).foregroundStyle(done ? .secondary : .primary)
            }.font(.system(size: size)).padding(.leading, CGFloat(indent) * 14)
        case .quote(let t):
            AnyView(MarkdownView(text: t, imageURL: imageURL, size: size, maxImageHeight: maxImageHeight, onImageTap: onImageTap))
                .foregroundStyle(.secondary).padding(.leading, 10).overlay(alignment: .leading) { Rectangle().fill(Theme.hairline).frame(width: 2) }
        case .code(let lang, let t): codeBlock(t, label: lang)
        case .terminal(let t): codeBlock(t, label: nil, plain: true)
        case .rule: Divider()
        case .image(let n):
            if let u = imageURL(n), let img = NSImage(contentsOf: u) {
                Button { if let onImageTap { onImageTap(n) } else { NSWorkspace.shared.open(u) } } label: {
                    Image(nsImage: img).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: maxImageHeight, alignment: .leading)
                        .clipShape(RoundedRectangle(cornerRadius: 6)).overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.hairline))
                }.buttonStyle(.plain).help("View full size")
            }
        case .table(let rows):
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { r, cells in
                        GridRow {
                            ForEach(Array(cells.enumerated()), id: \.offset) { _, c in
                                inline(c).font(.system(size: size - 0.5, weight: r == 0 ? .semibold : .regular)).padding(.horizontal, 8).padding(.vertical, 4)
                                    .frame(minWidth: 60, maxWidth: 420, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                                    .background(r == 0 ? Theme.fill : .clear).overlay(Rectangle().stroke(Theme.hairline, lineWidth: 0.5))
                            }
                        }
                    }
                }
            }
        }
    }

    /// Code and terminal output: monospaced, never wrapped (columns and box drawings line up), scrolls sideways, with a copy button.
    private func codeBlock(_ t: String, label: String?, plain: Bool = false) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            // Terminal drawings use Menlo: its box-drawing glyphs fill the whole line, so frames and tables join up.
            Text(t).font(plain ? .custom("Menlo", size: size - 1) : .system(size: size - 1, design: .monospaced)).lineSpacing(0).fixedSize().padding(8).padding(.trailing, 22)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(plain ? Theme.fill.opacity(0.6) : Theme.fill, in: RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 4) {
                if let label, !label.isEmpty { Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary) }
                Button { let pb = NSPasteboard.general; pb.clearContents(); pb.setString(t, forType: .string) } label: {
                    Image(systemName: "doc.on.doc").font(.system(size: 10.5)).frame(width: 18, height: 18).contentShape(Rectangle())
                }.buttonStyle(.plain).foregroundStyle(.secondary).help("Copy")
            }.padding(4)
        }
    }

    // MARK: Inline

    private func inline(_ s: String) -> Text {
        let (prepped, tagged) = Self.prepareInline(s)
        let o = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        guard var a = try? AttributedString(markdown: prepped, options: o) else { return Text(Self.stripMarkers(prepped)) }
        if tagged { a = Self.applyTags(a, size: size) }
        return Text(a)
    }

    // Private-use markers standing in for inline tags while the Markdown parser runs.
    private static let uOn: Unicode.Scalar = "\u{E000}", uOff: Unicode.Scalar = "\u{E001}", mOn: Unicode.Scalar = "\u{E002}", mOff: Unicode.Scalar = "\u{E003}"
    private static let color: Unicode.Scalar = "\u{E004}", sizeOn: Unicode.Scalar = "\u{E005}", sizeEnd: Unicode.Scalar = "\u{E006}", spanOff: Unicode.Scalar = "\u{E007}"

    private static let tagPattern = try! NSRegularExpression(pattern:
        #"(`+)[^`]*?\1|(?<!\\)<(/?)(u|ins|mark)>|(?<!\\)<span style="(?:color:#([0-9A-Fa-f]{6})|font-size:(\d+)px)">|(?<!\\)</span>|(?<!\\)<(/?)(b|strong|i|em|s|del|strike|code|kbd)>|(?<!\\)<br\s*/?>"#,
        options: [.caseInsensitive])

    /// Swaps inline tags for markers (outside code spans) and simple HTML formatting for its Markdown, before parsing.
    static func prepareInline(_ s: String) -> (String, Bool) {
        guard s.contains("<") else { return (s, false) }
        let ns = s as NSString; var out = ""; var pos = 0; var tagged = false
        for m in tagPattern.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: pos, length: m.range.location - pos)); pos = NSMaxRange(m.range)
            let whole = ns.substring(with: m.range)
            func g(_ i: Int) -> String? { m.range(at: i).location == NSNotFound ? nil : ns.substring(with: m.range(at: i)) }
            if g(1) != nil { out += whole; continue }   // a code span stays as written
            if let name = g(3)?.lowercased() {
                let closing = g(2) == "/"; tagged = true
                out.unicodeScalars.append(name == "mark" ? (closing ? mOff : mOn) : (closing ? uOff : uOn))
            } else if let hex = g(4) { tagged = true; out.unicodeScalars.append(color); out += hex.uppercased() }
            else if let px = g(5) { tagged = true; out.unicodeScalars.append(sizeOn); out += px; out.unicodeScalars.append(sizeEnd) }
            else if let name = g(7)?.lowercased() {
                switch name { case "b", "strong": out += "**"; case "i", "em": out += "*"; case "s", "del", "strike": out += "~~"; default: out += "`" }
            } else if whole.lowercased().hasPrefix("<br") { out += "\n" }
            else { tagged = true; out.unicodeScalars.append(spanOff) }
        }
        out += ns.substring(from: pos)
        return (out, tagged)
    }

    private static func stripMarkers(_ s: String) -> String { String(String.UnicodeScalarView(s.unicodeScalars.filter { !(0xE000...0xE007).contains($0.value) })) }

    /// Turns the markers back into underline, highlight, colour and size on the parsed text.
    static func applyTags(_ a: AttributedString, size: CGFloat) -> AttributedString {
        var out = AttributedString()
        var under = 0, mark = 0; var colors: [Color] = [], sizes: [CGFloat] = [], spans: [Character] = []
        var hex: String?, px: String?
        for run in a.runs {
            let attrs = run.attributes; var buf = ""
            func emit() {
                guard !buf.isEmpty else { return }
                var piece = AttributedString(buf, attributes: attrs)
                if under > 0 { piece.underlineStyle = .single }
                if mark > 0 { piece.backgroundColor = Color(nsColor: NotesMarkdown.highlightColor) }
                if let c = colors.last { piece.foregroundColor = c }
                if let s = sizes.last { piece.font = .system(size: s * size / NotesMarkdown.baseSize) }
                out += piece; buf = ""
            }
            for sc in a[run.range].unicodeScalars {
                if var h = hex {
                    h.unicodeScalars.append(sc); hex = h
                    if h.count == 6 { emit(); colors.append(Color(nsColor: Theme.rgb(UInt32(h, radix: 16) ?? 0))); spans.append("c"); hex = nil }
                    continue
                }
                if px != nil { if sc == sizeEnd { emit(); sizes.append(CGFloat(Double(px!) ?? Double(NotesMarkdown.baseSize))); spans.append("s"); px = nil } else { px!.unicodeScalars.append(sc) }; continue }
                switch sc {
                case uOn: emit(); under += 1
                case uOff: emit(); under = max(0, under - 1)
                case mOn: emit(); mark += 1
                case mOff: emit(); mark = max(0, mark - 1)
                case color: hex = ""
                case sizeOn: px = ""
                case spanOff: emit(); if let k = spans.popLast() { if k == "c" { _ = colors.popLast() } else { _ = sizes.popLast() } }
                default: buf.unicodeScalars.append(sc)
                }
            }
            emit()
        }
        return out
    }

    // MARK: Blocks

    private func blocks() -> [Block] {
        let src = NotesText.looksLikeHTMLSource(text) ? HTMLMarkdown.convert(text) : NotesText.stripANSI(text)
        var out: [Block] = []; var para: [String] = []
        func flush() { if !para.isEmpty { out.append(.paragraph(para.joined(separator: "\n"))); para = [] } }
        let lines = src.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n"); var i = 0
        while i < lines.count {
            let line = lines[i]; let t = line.trimmingCharacters(in: .whitespaces)
            // Fenced code: ``` or ~~~, closed by the same fence (or the end of the text).
            if let f = t.range(of: #"^(`{3,}|~{3,})"#, options: .regularExpression), line.prefix(while: { $0 == " " }).count < 4 {
                flush(); let fence = String(t[f]); let lang = t[f.upperBound...].trimmingCharacters(in: .whitespaces)
                var body: [String] = []; i += 1
                while i < lines.count {
                    let c = lines[i].trimmingCharacters(in: .whitespaces)
                    if c.hasPrefix(fence), c.allSatisfy({ $0 == fence.first }) { i += 1; break }
                    body.append(lines[i]); i += 1
                }
                out.append(.code(lang.split(separator: " ").first.map(String.init) ?? "", body.joined(separator: "\n"))); continue
            }
            if t.isEmpty { flush(); i += 1; continue }
            // Terminal drawings and tool output: box tables, frames, and an agent's ⎿ gutter with the lines indented under it.
            if NotesText.isTerminalLine(line) {
                flush(); var body: [String] = []
                let gutter = t.hasPrefix("⎿") ? line.prefix(while: { $0 == " " }).count : -1
                while i < lines.count {
                    let l = lines[i]; let lt = l.trimmingCharacters(in: .whitespaces)
                    let under = gutter >= 0 && !lt.isEmpty && l.prefix(while: { $0 == " " }).count > gutter && !lt.hasPrefix("⏺") && !lt.hasPrefix("●")
                    guard NotesText.isTerminalLine(l) || under else { break }
                    body.append(l); i += 1
                }
                out.append(.terminal(Self.dedent(body))); continue
            }
            if t.range(of: #"^([-*_])(\s*\1){2,}$"#, options: .regularExpression) != nil { flush(); out.append(.rule); i += 1; continue }
            if t.contains("|"), i + 1 < lines.count, NotesText.isTableSeparator(lines[i + 1].trimmingCharacters(in: .whitespaces)) {
                flush(); var rows: [[String]] = [cells(lines[i])]; i += 2
                while i < lines.count, lines[i].contains("|"), !lines[i].trimmingCharacters(in: .whitespaces).isEmpty { rows.append(cells(lines[i])); i += 1 }
                let cols = rows.map(\.count).max() ?? 1
                out.append(.table(rows.map { $0 + Array(repeating: "", count: cols - $0.count) })); continue
            }
            if let m = t.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
                flush(); let title = String(t[m.upperBound...]).replacingOccurrences(of: #"\s+#+\s*$"#, with: "", options: .regularExpression)
                out.append(.heading(t[..<m.upperBound].filter { $0 == "#" }.count, title)); i += 1; continue
            }
            if t.hasPrefix(">") {
                flush(); var body: [String] = []
                while i < lines.count {
                    let q = lines[i].trimmingCharacters(in: .whitespaces); guard q.hasPrefix(">") else { break }
                    var r = q.dropFirst(); if r.hasPrefix(" ") { r = r.dropFirst() }; body.append(String(r)); i += 1
                }
                out.append(.quote(body.joined(separator: "\n"))); continue
            }
            if let m = line.range(of: #"^\s*([-*+]|\d+[.)])\s+"#, options: .regularExpression) {
                flush(); let lead = line[..<m.upperBound]; let indent = lead.replacingOccurrences(of: "\t", with: "  ").prefix { $0 == " " }.count / 2
                let marker = lead.trimmingCharacters(in: .whitespaces); var rest = String(line[m.upperBound...])
                if !marker.first!.isNumber, let box = rest.range(of: #"^\[( |x|X)\]\s+"#, options: .regularExpression) {
                    let done = rest[box].lowercased().contains("x"); rest = String(rest[box.upperBound...])
                    out.append(.task(indent, done, rest)); i += 1; continue
                }
                out.append(.bullet(indent, marker.first!.isNumber ? marker : "•", rest)); i += 1; continue
            }
            if let re = try? NSRegularExpression(pattern: #"!\[[^\]]*\]\(attachment:(\d+)\)"#), line.contains("attachment:") {
                flush(); let ns = line as NSString; var pos = 0
                for m in re.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                    let before = ns.substring(with: NSRange(location: pos, length: m.range.location - pos)).trimmingCharacters(in: .whitespaces)
                    if !before.isEmpty { out.append(.paragraph(before)) }
                    out.append(.image(Int(ns.substring(with: m.range(at: 1))) ?? 0)); pos = NSMaxRange(m.range)
                }
                let after = ns.substring(from: pos).trimmingCharacters(in: .whitespaces); if !after.isEmpty { out.append(.paragraph(after)) }
                i += 1; continue
            }
            para.append(line); i += 1
        }
        flush(); return out
    }

    /// Removes the indentation every line shares (a terminal UI's margin), keeping the alignment between them.
    private static func dedent(_ lines: [String]) -> String {
        let n = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.map { $0.prefix { $0 == " " }.count }.min() ?? 0
        return lines.map { String($0.dropFirst(min(n, $0.prefix { $0 == " " }.count))) }.joined(separator: "\n")
    }

    private func cells(_ line: String) -> [String] {
        var t = line.trimmingCharacters(in: .whitespaces); if t.hasPrefix("|") { t.removeFirst() }; if t.hasSuffix("|") && !t.hasSuffix("\\|") { t.removeLast() }
        return t.replacingOccurrences(of: "\\|", with: "\u{1}").split(separator: "|", omittingEmptySubsequences: false).map { $0.replacingOccurrences(of: "\u{1}", with: "|").trimmingCharacters(in: .whitespaces) }
    }
}
