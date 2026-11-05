// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Turns HTML (browsers, Word, Outlook, Notion, Google Docs…) into Markdown, keeping structure:
/// headings, bold/italic/strike, links, lists, quotes, code blocks, tables and image placeholders.
/// Forgiving on purpose: copied HTML is often fragments with unclosed tags and Office noise.
public enum HTMLMarkdown {
    public static func convert(_ html: String) -> String {
        var c = Converter()
        return c.run(html)
    }

    static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        let named = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ", "ndash": "–", "mdash": "—", "hellip": "…", "lsquo": "‘", "rsquo": "’",
                     "ldquo": "“", "rdquo": "”", "bull": "•", "middot": "·", "copy": "©", "reg": "®", "trade": "™", "rarr": "→", "larr": "←", "times": "×"]
        var out = ""; var i = s.startIndex
        while i < s.endIndex {
            if s[i] == "&", let semi = s[i...].prefix(10).firstIndex(of: ";") {
                let name = String(s[s.index(after: i)..<semi])
                if let r = named[name] { out += r; i = s.index(after: semi); continue }
                if name.hasPrefix("#") {
                    let num = name.dropFirst()
                    let code = num.hasPrefix("x") || num.hasPrefix("X") ? UInt32(num.dropFirst(), radix: 16) : UInt32(num)
                    if let code, let u = Unicode.Scalar(code) { out.unicodeScalars.append(u); i = s.index(after: semi); continue }
                }
            }
            out.append(s[i]); i = s.index(after: i)
        }
        return out
    }

    private struct Tag { var name: String; var closing: Bool; var attrs: [String: String] }

    private struct Converter {
        enum Frame { case cell, quote }
        struct Table { var rows: [[String]] = []; var row: [String] = [] }
        var bufs = [""]
        var frames: [Frame] = []
        var lists: [(ordered: Bool, n: Int)] = []
        var tables: [Table] = []
        var links: [Bool] = []
        var inPre = false, inCode = false
        var skip = 0

        var cur: String { get { bufs[bufs.count - 1] } set { bufs[bufs.count - 1] = newValue } }

        mutating func run(_ html: String) -> String {
            var i = html.startIndex
            while i < html.endIndex {
                if html[i] == "<" {
                    if html[i...].hasPrefix("<!--") {
                        if let e = html.range(of: "-->", range: i..<html.endIndex) { i = e.upperBound } else { break }
                        continue
                    }
                    if let end = tagEnd(html, from: i) {
                        let raw = String(html[html.index(after: i)..<end])
                        i = html.index(after: end)
                        if let t = parseTag(raw) { handle(t) }
                        continue
                    }
                }
                let next = html[html.index(after: i)...].firstIndex(of: "<") ?? html.endIndex
                text(HTMLMarkdown.decodeEntities(String(html[i..<next])))
                i = next
            }
            while bufs.count > 1 { let t = bufs.removeLast(); bufs[bufs.count - 1] += t }
            return cleanup(cur)
        }

        func tagEnd(_ s: String, from: String.Index) -> String.Index? {
            var i = s.index(after: from); var quote: Character?
            while i < s.endIndex {
                let ch = s[i]
                if let q = quote { if ch == q { quote = nil } }
                else if ch == "\"" || ch == "'" { quote = ch }
                else if ch == ">" { return i }
                i = s.index(after: i)
            }
            return nil
        }

        func parseTag(_ raw: String) -> Tag? {
            var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if s.hasPrefix("!") || s.hasPrefix("?") || s.isEmpty { return nil }
            var closing = false
            if s.hasPrefix("/") { closing = true; s.removeFirst() }
            let nameEnd = s.firstIndex { $0.isWhitespace || $0 == "/" } ?? s.endIndex
            let name = s[..<nameEnd].lowercased()
            var attrs: [String: String] = [:]
            if let re = try? NSRegularExpression(pattern: #"([a-zA-Z_:][-a-zA-Z0-9_:.]*)\s*=\s*("([^"]*)"|'([^']*)'|[^\s>]+)"#) {
                let ns = s as NSString
                for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
                    let key = ns.substring(with: m.range(at: 1)).lowercased()
                    let val = [3, 4].compactMap { m.range(at: $0).location != NSNotFound ? ns.substring(with: m.range(at: $0)) : nil }.first ?? ns.substring(with: m.range(at: 2))
                    attrs[key] = HTMLMarkdown.decodeEntities(val)
                }
            }
            return Tag(name: String(name), closing: closing, attrs: attrs)
        }

        mutating func text(_ s: String) {
            if skip > 0 { return }
            if inPre { cur += s; return }
            var t = s.replacingOccurrences(of: #"[\s\u{00A0}]+"#, with: " ", options: .regularExpression)
            let atStart = cur.isEmpty || cur.hasSuffix("\n") || cur.hasSuffix(" ")
            if atStart, t.hasPrefix(" ") { t.removeFirst() }
            cur += t
        }

        mutating func trimTrailingSpaces() { while cur.hasSuffix(" ") { cur.removeLast() } }
        mutating func ensureBlank() { trimTrailingSpaces(); if cur.isEmpty { return }; if !cur.hasSuffix("\n\n") { cur += cur.hasSuffix("\n") ? "\n" : "\n\n" } }
        mutating func ensureNewline() { trimTrailingSpaces(); if !cur.isEmpty, !cur.hasSuffix("\n") { cur += "\n" } }
        mutating func mark(_ open: Bool, _ m: String) {
            if skip > 0 || inPre { return }
            if open { cur += m } else { var k = 0; while cur.hasSuffix(" ") { cur.removeLast(); k += 1 }; cur += m + String(repeating: " ", count: k) }
        }
        mutating func closeCell() {
            guard frames.last == .cell, bufs.count > 1 else { return }
            frames.removeLast()
            let t = bufs.removeLast().replacingOccurrences(of: #"\s*\n\s*"#, with: " ", options: .regularExpression)
                .replacingOccurrences(of: "|", with: "\\|").trimmingCharacters(in: .whitespaces)
            if !tables.isEmpty { tables[tables.count - 1].row.append(t) } else { cur += t }
        }

        mutating func handle(_ t: Tag) {
            let n = t.name
            if ["style", "script", "head", "title", "noscript", "template"].contains(n) { skip = t.closing ? max(0, skip - 1) : skip + 1; return }
            if skip > 0 { return }
            switch n {
            case "h1", "h2", "h3", "h4", "h5", "h6":
                ensureBlank(); if !t.closing { cur += String(repeating: "#", count: Int(String(n.last!))!) + " " } else { ensureBlank() }
            case "p": ensureBlank()
            case "div", "section", "article", "header", "footer", "main", "nav", "aside", "figure", "figcaption", "form", "address", "details", "summary", "center": ensureNewline()
            case "br": if frames.last == .cell { cur += " " } else { trimTrailingSpaces(); cur += "  \n" }
            case "hr": ensureBlank(); cur += "---"; ensureBlank()
            case "b", "strong": mark(!t.closing, "**")
            case "i", "em", "cite", "dfn": mark(!t.closing, "*")
            case "s", "strike", "del": mark(!t.closing, "~~")
            case "code", "kbd", "samp", "tt": if !inPre { inCode.toggle(); mark(!t.closing, "`") }
            case "pre":
                if !t.closing { ensureBlank(); cur += "```\n"; inPre = true }
                else { if !cur.hasSuffix("\n") { cur += "\n" }; cur += "```"; inPre = false; ensureBlank() }
            case "a":
                if !t.closing {
                    let href = t.attrs["href"] ?? ""
                    let ok = !href.isEmpty && !href.hasPrefix("#") && !href.lowercased().hasPrefix("javascript:")
                    links.append(ok); if ok { cur += "[" }
                    pendingHref.append(ok ? href : "")
                } else if let ok = links.popLast() {
                    let href = pendingHref.popLast() ?? ""
                    if ok { var k = 0; while cur.hasSuffix(" ") { cur.removeLast(); k += 1 }; cur += "](\(href.replacingOccurrences(of: " ", with: "%20").replacingOccurrences(of: ")", with: "%29")))" + String(repeating: " ", count: k) }
                }
            case "img":
                guard !t.closing else { return }
                let alt = (t.attrs["alt"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if let src = t.attrs["src"], src.hasPrefix("http") { cur += "![\(alt.isEmpty ? "image" : alt)](\(src))" } else { cur += "*[\(alt.isEmpty ? "image" : alt)]*" }
            case "ul", "ol":
                if !t.closing { if lists.isEmpty { ensureBlank() } else { ensureNewline() }; lists.append((n == "ol", Int(t.attrs["start"] ?? "") ?? 1)) }
                else { if !lists.isEmpty { lists.removeLast() }; if lists.isEmpty { ensureBlank() } else { ensureNewline() } }
            case "li":
                if !t.closing {
                    ensureNewline()
                    let indent = String(repeating: "  ", count: max(0, lists.count - 1))
                    if var l = lists.last { cur += indent + (l.ordered ? "\(l.n). " : "- "); l.n += 1; lists[lists.count - 1] = l } else { cur += "- " }
                } else { ensureNewline() }
            case "blockquote":
                if !t.closing { ensureBlank(); bufs.append(""); frames.append(.quote) }
                else if frames.last == .quote {
                    frames.removeLast()
                    let body = bufs.removeLast().trimmingCharacters(in: .whitespacesAndNewlines)
                    cur += body.split(separator: "\n", omittingEmptySubsequences: false).map { $0.isEmpty ? ">" : "> \($0)" }.joined(separator: "\n"); ensureBlank()
                }
            case "table": if !t.closing { ensureBlank(); tables.append(Table()) } else { closeCell(); finishTable() }
            case "tr": closeCell(); if !tables.isEmpty { if t.closing { let r = tables[tables.count - 1].row; if !r.isEmpty { tables[tables.count - 1].rows.append(r) }; tables[tables.count - 1].row = [] } }
            case "td", "th": closeCell(); if !t.closing { bufs.append(""); frames.append(.cell) }
            default: break
            }
        }

        var pendingHref: [String] = []

        mutating func finishTable() {
            guard let tb = tables.popLast() else { return }
            var rows = tb.rows; if !tb.row.isEmpty { rows.append(tb.row) }
            guard !rows.isEmpty else { return }
            let cols = rows.map(\.count).max() ?? 1
            if cols == 1 { for r in rows { ensureBlank(); cur += r[0] }; ensureBlank(); return }   // layout tables: just the text
            rows = rows.map { $0 + Array(repeating: "", count: cols - $0.count) }
            ensureBlank()
            cur += "| " + rows[0].joined(separator: " | ") + " |\n| " + Array(repeating: "---", count: cols).joined(separator: " | ") + " |"
            for r in rows.dropFirst() { cur += "\n| " + r.joined(separator: " | ") + " |" }
            ensureBlank()
        }

        func cleanup(_ s: String) -> String {
            var t = s.replacingOccurrences(of: "\u{00A0}", with: " ")
            t = t.replacingOccurrences(of: #"\*\*\s*\*\*"#, with: "", options: .regularExpression)
            t = t.replacingOccurrences(of: #"~~\s*~~"#, with: "", options: .regularExpression)
            t = t.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
                var l = String(line)
                if l.hasPrefix("#") { l = l.replacingOccurrences(of: "**", with: "") }
                if l.hasSuffix("  ") && !l.hasSuffix("   ") { return l }
                while l.hasSuffix(" ") { l.removeLast() }
                return l
            }.joined(separator: "\n")
            t = t.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            return t.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
