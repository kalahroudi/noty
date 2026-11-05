// SPDX-License-Identifier: Apache-2.0

import AppKit

/// Rich text (RTF/RTFD from Word, Pages, Notes, TextEdit, Mail) to Markdown, keeping headings, bold/italic, links, lists and tables.
/// Pictures inside the text become `![image](attachment:N)` and their data is returned in order.
public enum RichText {
    public struct Output { public var markdown: String; public var images: [Data] }

    public static func markdown(from str: NSAttributedString) -> Output {
        var images: [Data] = []
        let ns = str.string as NSString
        guard ns.length > 0 else { return Output(markdown: "", images: []) }

        // Body size = the most common font size by characters; headings are measured against it.
        var sizes: [CGFloat: Int] = [:]
        str.enumerateAttribute(.font, in: NSRange(location: 0, length: ns.length)) { v, r, _ in if let f = v as? NSFont { sizes[f.pointSize, default: 0] += r.length } }
        let body = sizes.max { $0.value < $1.value }?.key ?? 12

        var paras: [(text: String, list: Bool, tableKey: String?, row: Int, col: Int)] = []
        var loc = 0
        while loc < ns.length {
            let pr = ns.paragraphRange(for: NSRange(location: loc, length: 0)); loc = NSMaxRange(pr)
            let style = str.attribute(.paragraphStyle, at: pr.location, effectiveRange: nil) as? NSParagraphStyle
            var line = ""; var maxSize: CGFloat = 0; var allBold = true; var any = false
            str.enumerateAttributes(in: pr) { attrs, r, _ in
                var s = ns.substring(with: r).replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\u{2028}", with: "  \n")
                if let att = attrs[.attachment] as? NSTextAttachment, s.contains("\u{FFFC}") {
                    var data: Data?
                    if let d = att.fileWrapper?.regularFileContents { data = d } else if let img = att.image { data = img.tiffRepresentation }
                    if let d = data, let rep = NSBitmapImageRep(data: d), let png = rep.representation(using: .png, properties: [:]) {
                        images.append(png); s = s.replacingOccurrences(of: "\u{FFFC}", with: "![image](attachment:\(images.count))")
                    } else { s = s.replacingOccurrences(of: "\u{FFFC}", with: "") }
                }
                let plain = s.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !s.isEmpty else { return }
                var bold = false, italic = false, mono = false
                if let f = attrs[.font] as? NSFont {
                    let t = f.fontDescriptor.symbolicTraits
                    bold = t.contains(.bold); italic = t.contains(.italic); mono = f.isFixedPitch
                    if !plain.isEmpty { maxSize = max(maxSize, f.pointSize); any = true; if !bold { allBold = false } }
                }
                var wrapped = s
                if !plain.isEmpty && !wrapped.contains("](attachment:") {
                    let lead = wrapped.prefix { $0 == " " }, trail = wrapped.reversed().prefix { $0 == " " }
                    var core = plain
                    if mono { core = "`\(core)`" }
                    if bold && italic { core = "***\(core)***" } else if bold { core = "**\(core)**" } else if italic { core = "*\(core)*" }
                    if let st = attrs[.strikethroughStyle] as? Int, st != 0 { core = "~~\(core)~~" }
                    if let link = attrs[.link] { let href = (link as? URL)?.absoluteString ?? "\(link)"; core = "[\(core)](\(href))" }
                    wrapped = String(lead) + core + String(trail)
                }
                line += wrapped
            }
            var list = false
            if let lists = style?.textLists, !lists.isEmpty {
                list = true
                line = line.replacingOccurrences(of: #"^\s*(\t|\s)*([•◦▪‣·\-–]|\d+[\.\)]|[a-zA-Z][\.\)])\s+"#, with: "", options: .regularExpression)
                let ordered = !(lists.last!.markerFormat.rawValue.contains("disc") || lists.last!.markerFormat.rawValue.contains("circle") || lists.last!.markerFormat.rawValue.contains("square") || lists.last!.markerFormat.rawValue.contains("hyphen") || lists.last!.markerFormat.rawValue.contains("diamond") || lists.last!.markerFormat.rawValue.contains("box"))
                line = String(repeating: "  ", count: lists.count - 1) + (ordered ? "1. " : "- ") + line.trimmingCharacters(in: .whitespaces)
            } else if let m = line.range(of: #"^\s*[•◦▪‣·]\s*\t?\s*"#, options: .regularExpression) {
                list = true; line = "- " + line[m.upperBound...].trimmingCharacters(in: .whitespaces)
            } else if let m = line.range(of: #"^\s*\d{1,3}[\.\)]\s*\t\s*"#, options: .regularExpression) {
                list = true; line = "1. " + line[m.upperBound...].trimmingCharacters(in: .whitespaces)
            } else if any {
                let t = line.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty, t.count < 200 {
                    let ratio = maxSize / max(body, 1)
                    let h = ratio >= 1.6 ? 1 : ratio >= 1.3 ? 2 : (ratio >= 1.1 && allBold) ? 3 : 0
                    if h > 0 { line = String(repeating: "#", count: h) + " " + t.replacingOccurrences(of: "**", with: "") }
                }
            }
            var key: String?; var row = 0, col = 0
            if let block = style?.textBlocks.compactMap({ $0 as? NSTextTableBlock }).first {
                key = "\(ObjectIdentifier(block.table).hashValue)"; row = block.startingRow; col = block.startingColumn
            }
            paras.append((line, list, key, row, col))
        }

        // Assemble: lists tight, tables as pipe tables, everything else separated by a blank line.
        var out = ""
        var i = 0
        while i < paras.count {
            let p = paras[i]
            if let key = p.tableKey {
                var cells: [Int: [Int: String]] = [:]; var j = i
                while j < paras.count, paras[j].tableKey == key {
                    let t = paras[j].text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "|", with: "\\|")
                    cells[paras[j].row, default: [:]][paras[j].col, default: ""] += (cells[paras[j].row]?[paras[j].col]?.isEmpty == false ? " " : "") + t
                    j += 1
                }
                let cols = (cells.values.flatMap { $0.keys }.max() ?? 0) + 1
                let rows = cells.keys.sorted().map { r in (0..<cols).map { cells[r]?[$0] ?? "" } }
                if !rows.isEmpty {
                    if cols == 1 { out += rows.map { $0[0] }.joined(separator: "\n\n") + "\n\n" }
                    else {
                        out += "| " + rows[0].joined(separator: " | ") + " |\n| " + Array(repeating: "---", count: cols).joined(separator: " | ") + " |\n"
                        for r in rows.dropFirst() { out += "| " + r.joined(separator: " | ") + " |\n" }
                        out += "\n"
                    }
                }
                i = j; continue
            }
            let t = p.text.trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
            if t.isEmpty { if !out.hasSuffix("\n\n") { out += out.hasSuffix("\n") ? "\n" : "" }; i += 1; continue }
            out += t + (p.list && i + 1 < paras.count && paras[i + 1].list ? "\n" : "\n\n")
            i += 1
        }
        let md = out.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        return Output(markdown: md, images: images)
    }
}
