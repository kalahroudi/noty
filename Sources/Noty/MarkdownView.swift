// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import NotyKit

/// Shows captured Markdown with its structure: headings, bold/italic/links/code, lists, quotes, code blocks, tables and pictures.
/// Small on purpose; it renders what the capture produces, not arbitrary Markdown.
struct MarkdownView: View {
    let text: String
    var imageURL: (Int) -> URL? = { _ in nil }
    var size: CGFloat = 12.5

    private enum Block { case heading(Int, String), paragraph(String), bullet(Int, String, String), quote(String), code(String), table([[String]]), rule, image(Int) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks().enumerated()), id: \.offset) { _, b in view(b) }
        }.frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
    }

    @ViewBuilder private func view(_ b: Block) -> some View {
        switch b {
        case .heading(let l, let t): inline(t).font(.system(size: size + CGFloat(max(0, 4 - l)) * 1.6, weight: .semibold)).padding(.top, 2)
        case .paragraph(let t): inline(t).font(.system(size: size))
        case .bullet(let indent, let marker, let t):
            HStack(alignment: .firstTextBaseline, spacing: 6) { Text(marker).foregroundStyle(.secondary); inline(t) }.font(.system(size: size)).padding(.leading, CGFloat(indent) * 14)
        case .quote(let t): inline(t).font(.system(size: size)).foregroundStyle(.secondary).padding(.leading, 8).overlay(alignment: .leading) { Rectangle().fill(Theme.hairline).frame(width: 2) }
        case .code(let t): Text(t).font(.system(size: size - 1, design: .monospaced)).padding(8).frame(maxWidth: .infinity, alignment: .leading).background(Theme.fill, in: RoundedRectangle(cornerRadius: 6))
        case .rule: Divider()
        case .image(let n):
            if let u = imageURL(n), let img = NSImage(contentsOf: u) { Image(nsImage: img).resizable().scaledToFit().frame(maxHeight: 220, alignment: .leading).clipShape(RoundedRectangle(cornerRadius: 6)).overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.hairline)) }
        case .table(let rows):
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { r, cells in
                        GridRow {
                            ForEach(Array(cells.enumerated()), id: \.offset) { _, c in
                                inline(c).font(.system(size: size - 0.5, weight: r == 0 ? .semibold : .regular)).padding(.horizontal, 8).padding(.vertical, 4)
                                    .frame(minWidth: 60, alignment: .leading).background(r == 0 ? Theme.fill : .clear).overlay(Rectangle().stroke(Theme.hairline, lineWidth: 0.5))
                            }
                        }
                    }
                }
            }
        }
    }

    private func inline(_ s: String) -> Text {
        let o = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let a = try? AttributedString(markdown: s, options: o) { return Text(a) }
        return Text(s)
    }

    private func blocks() -> [Block] {
        var out: [Block] = []; var para: [String] = []; var code: [String]?
        func flush() { if !para.isEmpty { out.append(.paragraph(para.joined(separator: "\n"))); para = [] } }
        let lines = text.components(separatedBy: "\n"); var i = 0
        while i < lines.count {
            let line = lines[i]; let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("```") { if code == nil { flush(); code = [] } else { out.append(.code(code!.joined(separator: "\n"))); code = nil }; i += 1; continue }
            if code != nil { code!.append(line); i += 1; continue }
            if t.isEmpty { flush(); i += 1; continue }
            if t == "---" || t == "***" { flush(); out.append(.rule); i += 1; continue }
            if t.hasPrefix("|"), i + 1 < lines.count, lines[i + 1].contains("---") {
                flush(); var rows: [[String]] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    if !lines[i].contains("| ---") { rows.append(cells(lines[i])) }; i += 1
                }
                out.append(.table(rows)); continue
            }
            if let m = t.range(of: #"^#{1,6}\s+"#, options: .regularExpression) { flush(); out.append(.heading(t[..<m.upperBound].filter { $0 == "#" }.count, String(t[m.upperBound...]))); i += 1; continue }
            if t.hasPrefix(">") { flush(); out.append(.quote(String(t.dropFirst()).trimmingCharacters(in: .whitespaces))); i += 1; continue }
            if let m = line.range(of: #"^\s*([-*+]|\d+\.)\s+"#, options: .regularExpression) {
                flush(); let lead = line[..<m.upperBound]; let indent = lead.prefix { $0 == " " }.count / 2
                let marker = lead.trimmingCharacters(in: .whitespaces)
                out.append(.bullet(indent, marker.first!.isNumber ? marker : "•", String(line[m.upperBound...]))); i += 1; continue
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
        if let c = code { out.append(.code(c.joined(separator: "\n"))) }
        flush(); return out
    }

    private func cells(_ line: String) -> [String] {
        var t = line.trimmingCharacters(in: .whitespaces); if t.hasPrefix("|") { t.removeFirst() }; if t.hasSuffix("|") { t.removeLast() }
        return t.replacingOccurrences(of: "\\|", with: "\u{1}").split(separator: "|", omittingEmptySubsequences: false).map { $0.replacingOccurrences(of: "\u{1}", with: "|").trimmingCharacters(in: .whitespaces) }
    }
}
