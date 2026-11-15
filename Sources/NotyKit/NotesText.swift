// SPDX-License-Identifier: Apache-2.0

import Foundation

/// What notes need to show pasted agent and terminal output well: turning a paste (Markdown, HTML, ANSI-coloured CLI output)
/// into the notes' Markdown, telling when a note has structure worth rendering, and finding code that must stay byte for byte.
public enum NotesText {

    // MARK: Paste → Markdown

    /// The Markdown a paste should become. `plain` is the pasteboard's text, `html` its HTML flavour if any.
    /// Markdown stays Markdown (Claude's copy button, pi, Claude Code), HTML becomes Markdown (Claude desktop, browsers),
    /// raw HTML source is converted too, and CLI output loses its escape codes; output that was coloured by a terminal is kept in a code block.
    public static func pasteMarkdown(plain: String, html: String?) -> String {
        var text = normalizeNewlines(plain)
        let hadANSI = text.contains("\u{1B}")
        text = stripANSI(text)
        if looksLikeHTMLSource(text) {
            let md = HTMLMarkdown.convert(text)
            if !md.isEmpty { return md }
        }
        if let html, !html.isEmpty, !looksLikeMarkdown(text), !looksLikeTerminal(text) {
            if isCodeHTML(html) { return text.isEmpty ? text : fenced(text) }
            let md = HTMLMarkdown.convert(html)
            if !md.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return md }
        }
        if hadANSI, !looksLikeMarkdown(text), text.contains("\n") { return fenced(text) }
        return text
    }

    static func fenced(_ s: String) -> String {
        var t = s; while t.hasSuffix("\n") { t.removeLast() }
        let fence = t.contains("```") ? "~~~~" : "```"
        return fence + "\n" + t + "\n" + fence
    }

    /// CRLF and lone CR (progress bars redrawing a line) become plain lines: only what the terminal finally showed is kept.
    static func normalizeNewlines(_ s: String) -> String {
        let t = s.replacingOccurrences(of: "\r\n", with: "\n")
        guard t.contains("\r") else { return t }
        return t.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            let parts = line.split(separator: "\r", omittingEmptySubsequences: false)
            return String(parts.last(where: { !$0.isEmpty }) ?? "")
        }.joined(separator: "\n")
    }

    /// Removes terminal escape sequences: colours and styles (CSI), titles and hyperlinks (OSC), and lone escapes.
    public static func stripANSI(_ s: String) -> String {
        guard s.contains("\u{1B}") || s.contains("\u{9B}") else { return s }
        var t = s
        t = t.replacingOccurrences(of: "\u{1B}\\][^\u{07}\u{1B}]*(?:\u{07}|\u{1B}\\\\)", with: "", options: .regularExpression)   // OSC … BEL / ST
        t = t.replacingOccurrences(of: "(?:\u{1B}\\[|\u{9B})[0-?]*[ -/]*[@-~]", with: "", options: .regularExpression)            // CSI
        t = t.replacingOccurrences(of: "\u{1B}[@-Z\\\\-_]", with: "", options: .regularExpression)                                 // two-byte escapes
        t = t.replacingOccurrences(of: "\u{1B}", with: "")
        return t
    }

    // MARK: Recognising what a paste is

    private static let blockTags = ["html", "body", "div", "p", "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "li", "table", "pre", "section", "article",
                                    "blockquote", "details", "header", "main", "meta", "span", "strong", "em", "b", "i", "a", "code", "br", "hr", "img"]

    /// Raw HTML source (an agent printed HTML, or the user copied page source), not text that happens to mention a tag.
    /// The notes' own inline tags (`<u>`, `<mark>`, `<span style=…>`) are not HTML source.
    public static func looksLikeHTMLSource(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("<"), t.count > 6 else { return false }
        let lower = t.lowercased()
        if lower.hasPrefix("<!doctype html") || lower.hasPrefix("<html") { return true }
        if lower.hasPrefix("<u>") || lower.hasPrefix("<mark>") || lower.hasPrefix("<span style=\"color:") || lower.hasPrefix("<span style=\"font-size:") { return false }
        guard let m = lower.range(of: #"^<([a-z][a-z0-9]*)[\s>/]"#, options: .regularExpression) else { return false }
        let name = String(lower[m].dropFirst().dropLast())
        guard blockTags.contains(name) else { return false }
        // Mostly markup: a closing tag and at least two tags in all.
        let tags = lower.components(separatedBy: "<").count - 1
        return lower.contains("</") && tags >= 2
    }

    /// HTML that is just a code editor's or terminal's styled copy (VS Code, Xcode, iTerm): the plain text is the faithful version.
    static func isCodeHTML(_ html: String) -> Bool {
        let h = html.lowercased()
        let mono = ["monospace", "menlo", "monaco", "consolas", "sf mono", "courier", "jetbrains mono", "fira code", "white-space: pre", "white-space:pre"].contains { h.contains($0) }
        guard mono else { return false }
        let prose = ["<p", "<h1", "<h2", "<h3", "<li", "<table", "<blockquote"].contains { h.contains($0) }
        return !prose
    }

    /// Text that is already Markdown: one strong sign (fence, heading, table, link) or two weak ones (lists, emphasis, inline code).
    public static func looksLikeMarkdown(_ s: String) -> Bool {
        var strong = 0, weak = 0
        for raw in s.split(separator: "\n", omittingEmptySubsequences: false).prefix(400) {
            let line = String(raw); let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("```") || t.hasPrefix("~~~") { strong += 1 }
            else if t.range(of: #"^#{1,6}\s+\S"#, options: .regularExpression) != nil { strong += 1 }
            else if isTableSeparator(t) { strong += 1 }
            else if t.range(of: #"^([-*+]|\d+[.)])\s+\S"#, options: .regularExpression) != nil { weak += 1 }
            else if t.hasPrefix("> ") { weak += 1 }
            if t.range(of: #"\[[^\]]+\]\([^)\s]+\)"#, options: .regularExpression) != nil { strong += 1 }
            if t.range(of: #"\*\*[^*\s][^*]*\*\*|`[^`\s][^`]*`"#, options: .regularExpression) != nil { weak += 1 }
            if strong > 0 || weak > 1 { return true }
        }
        return false
    }

    /// Text drawn for a terminal: box-drawing tables and frames, or a CLI agent's tool-output gutter.
    public static func looksLikeTerminal(_ s: String) -> Bool {
        let lines = s.split(separator: "\n").map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !lines.isEmpty else { return false }
        let drawn = lines.filter { isTerminalLine($0) }.count
        return drawn * 4 >= lines.count
    }

    /// A line that only lines up in a monospaced font: box drawing (│ ┌ ─ ╭ …) or a tool-output gutter (⎿).
    public static func isTerminalLine(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("⎿") { return true }
        return line.unicodeScalars.contains { (0x2500...0x257F).contains($0.value) || (0x2580...0x259F).contains($0.value) }
    }

    public static func isTableSeparator(_ t: String) -> Bool {
        t.contains("-") && t.range(of: #"^\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?$"#, options: .regularExpression) != nil
    }

    /// True when a note has structure that reads better rendered than as an editable line of text:
    /// headings, lists, quotes, tables, code, links, rules or terminal output. Bold, colour and size alone are not.
    public static func isStructured(_ md: String) -> Bool {
        for raw in md.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw); let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { continue }
            if t.hasPrefix("```") || t.hasPrefix("~~~") || t.hasPrefix(">") || t.hasPrefix("|") { return true }
            if t.range(of: #"^(#{1,6}\s|([-+]|\\?\*|\d+[.)])\s+\S)"#, options: .regularExpression) != nil { return true }
            if t.range(of: #"^([-*_])(\s*\1){2,}$"#, options: .regularExpression) != nil { return true }
            if isTerminalLine(line) { return true }
            if t.range(of: #"\[[^\]]+\]\([^)\s]+\)|`[^`]+`|https?://\S"#, options: .regularExpression) != nil { return true }
        }
        return false
    }

    // MARK: Code that must stay as written

    /// For each Unicode scalar of `s`, whether it is inside code: a fenced block (``` or ~~~, fence lines included)
    /// or an inline `code` span (backticks included). Nothing inside code is formatting or an escape.
    public static func codeMask(_ s: String) -> [Bool] {
        let sc = Array(s.unicodeScalars)
        var mask = [Bool](repeating: false, count: sc.count)
        var i = 0
        var fence: (ch: Unicode.Scalar, n: Int)?
        while i < sc.count {
            var end = i; while end < sc.count, sc[end] != "\n" { end += 1 }   // the line is i..<end
            var j = i, lead = 0; while j < end, sc[j] == " " { j += 1; lead += 1 }
            var run = 0; let ch: Unicode.Scalar? = j < end && (sc[j] == "`" || sc[j] == "~") ? sc[j] : nil
            if let ch { while j + run < end, sc[j + run] == ch { run += 1 } }
            let lineEnd = min(end + 1, sc.count)
            if let f = fence {
                for k in i..<lineEnd { mask[k] = true }
                if lead < 4, ch == f.ch, run >= f.n, sc[(j + run)..<end].allSatisfy({ $0 == " " || $0 == "\t" }) { fence = nil }
                i = lineEnd; continue
            }
            if lead < 4, let ch, run >= 3, !(ch == "`" && sc[(j + run)..<end].contains("`")) {
                fence = (ch, run)
                for k in i..<lineEnd { mask[k] = true }
                i = lineEnd; continue
            }
            // Inline code spans on this line: a run of n backticks closed by the next run of exactly n.
            var k = i
            while k < end {
                guard sc[k] == "`", k == 0 || sc[k - 1] != "\\" else { k += 1; continue }
                var n = 0; while k + n < end, sc[k + n] == "`" { n += 1 }
                var m = k + n, close: Int?
                while m < end {
                    if sc[m] == "`" {
                        var r = 0; while m + r < end, sc[m + r] == "`" { r += 1 }
                        if r == n { close = m + r; break }
                        m += r
                    } else { m += 1 }
                }
                if let close { for q in k..<close { mask[q] = true }; k = close } else { k += n }
            }
            i = lineEnd
        }
        return mask
    }
}
