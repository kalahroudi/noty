// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Links and copy formats so an item or category can be pasted into an agent's chat and found again.
public enum Deeplink: Equatable, Sendable {
    case item(String)
    case category([String])

    public static func url(item id: String) -> String { "noty://item/\(id)" }
    public static func url(category path: [String]) -> String {
        "noty://category/" + path.map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? $0 }.joined(separator: "/")
    }

    public static func parse(_ url: URL) -> Deeplink? {
        guard url.scheme == "noty", let host = url.host else { return nil }
        let parts = url.path.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
        switch host {
        case "item": return parts.first.map { .item($0) }
        case "category": return parts.isEmpty ? nil : .category(parts)
        default: return nil
        }
    }

    /// Accepts a bare id, a prefix, or a full noty://item/… link (what a user pastes into an agent).
    public static func itemID(from text: String) -> String {
        if let u = URL(string: text), case .item(let id)? = parse(u) { return id }
        return text
    }
}

public enum MarkdownText {
    /// Markdown without its markers, for one-line previews and plain-text copies.
    public static func stripped(_ md: String) -> String {
        var t = md
        t = t.replacingOccurrences(of: #"!\[[^\]]*\]\([^)]*\)"#, with: "[image]", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: #"(?m)^\s*(#{1,6}\s+|>\s?|[-*+]\s+|```.*$)"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"(\*\*\*|\*\*|\*|~~|`)"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"(?m)^\|?\s*-{3,}.*$\n?"#, with: "", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public extension Item {
    var imageAttachments: [String] { attachments.filter { $0.lowercased().hasSuffix(".png") } }
    var htmlAttachment: String? { attachments.first { $0.lowercased().hasSuffix(".html") } }
    var otherAttachments: [String] { attachments.filter { !$0.lowercased().hasSuffix(".png") && !$0.lowercased().hasSuffix(".html") } }
    /// The highlighted text without Markdown syntax.
    var plainQuote: String { MarkdownText.stripped(quote) }
    /// First line of the highlighted text, for the list.
    var previewText: String { plainQuote.split(whereSeparator: \.isNewline).first.map(String.init) ?? "" }

    /// The quote with `![image](attachment:N)` placeholders turned into real file paths, for agents and exports.
    func resolvedQuote(store: NotyStore?) -> String {
        guard quote.contains("attachment:"), let store, let re = try? NSRegularExpression(pattern: #"attachment:(\d+)"#) else { return quote }
        let ns = quote as NSString; var out = quote
        for m in re.matches(in: quote, range: NSRange(location: 0, length: ns.length)).reversed() {
            let n = Int(ns.substring(with: m.range(at: 1))) ?? 0
            if imageAttachments.indices.contains(n - 1) { out = (out as NSString).replacingCharacters(in: m.range, with: store.attachmentURL(imageAttachments[n - 1]).path) }
        }
        return out
    }

    var deepLink: String { Deeplink.url(item: id) }

    /// Everything an agent needs in one paste: the link, the id to use with the Noty tools, the text, notes, source and image files.
    func agentReference(store: NotyStore? = nil) -> String {
        var l = ["Noty item: \(title)", "Link: \(deepLink)", "Id: \(id)  (the title is only a summary: read it with the noty MCP tool get_item for notes and attached screenshots or files)", "Category: \(path.joined(separator: "/"))",
                 "Type: \(kind.label)\(done ? ", done" : "")\(today ? ", today" : "")"]
        if !tags.isEmpty { l.append("Tags: " + tags.map { "#\($0)" }.joined(separator: " ")) }
        let q = resolvedQuote(store: store)
        if !q.isEmpty { l.append("Highlighted (Markdown):\n" + q.split(separator: "\n", omittingEmptySubsequences: false).map { "> \($0)" }.joined(separator: "\n")) }
        if !notes.isEmpty { l.append("Notes:\n\(notes)") }
        var src = [sourceApp, sourceTitle, sourceURL].compactMap { $0 }
        if !src.isEmpty { l.append("Source: " + src.removeFirst() + (src.isEmpty ? "" : " · " + src.joined(separator: " · "))) }
        if !attachments.isEmpty { l.append("Attached files:\n" + attachments.map { "- " + (store?.attachmentURL($0).path ?? $0) }.joined(separator: "\n")) }
        return l.joined(separator: "\n")
    }

    /// A Markdown note for pasting into documents and chats.
    func markdown(store: NotyStore? = nil) -> String {
        var l = ["## \(title)", ""]
        let q = resolvedQuote(store: store)
        if !q.isEmpty { l += q.split(separator: "\n", omittingEmptySubsequences: false).map { "> \($0)" } + [""] }
        if !notes.isEmpty { l += [notes, ""] }
        if !quote.contains("attachment:") { for a in imageAttachments { l.append("![](\(store?.attachmentURL(a).path ?? a))") } }
        for a in otherAttachments { l.append("[\(a)](\(store?.attachmentURL(a).path ?? a))") }
        let meta = [pathLabel.replacingOccurrences(of: " › ", with: "/"), sourceURL ?? sourceTitle ?? sourceApp].compactMap { $0 }
        l.append("_\(meta.joined(separator: " · "))_")
        return l.joined(separator: "\n")
    }
}

public enum ListReference {
    /// A category (or a smart list) as a short checklist with ids, for pasting into an agent.
    public static func text(title: String, link: String?, items: [Item]) -> String {
        var l = ["Noty list: \(title)"]
        if let link { l.append("Link: \(link)") }
        l.append("\(items.count) item\(items.count == 1 ? "" : "s"). The titles are only summaries: items often carry notes, highlighted text, screenshots or files with the real details. Before working on an item, read it with the noty MCP tool get_item (it returns the notes and the file paths of attachments, which you can open), and look at any screenshots.")
        l += items.map { it in
            var has: [String] = []
            if !it.quote.isEmpty { has.append("highlighted text") }
            if !it.notes.isEmpty { has.append("notes") }
            let pics = it.imageAttachments.count, files = it.otherAttachments.count
            if pics > 0 { has.append("\(pics) screenshot\(pics == 1 ? "" : "s")/image\(pics == 1 ? "" : "s")") }
            if files > 0 { has.append("\(files) file\(files == 1 ? "" : "s")") }
            return "- [\(it.done ? "x" : " ")] \(it.title)  (id \(it.id))" + (has.isEmpty ? "" : "  [has: \(has.joined(separator: ", "))]")
        }
        return l.joined(separator: "\n")
    }
}
