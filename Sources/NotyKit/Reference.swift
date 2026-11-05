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

public extension Item {
    var deepLink: String { Deeplink.url(item: id) }

    /// Everything an agent needs in one paste: the link, the id to use with the Noty tools, the text, notes, source and image files.
    func agentReference(store: NotyStore? = nil) -> String {
        var l = ["Noty item: \(title)", "Link: \(deepLink)", "Id: \(id)  (read it with the noty MCP tool get_item)", "Category: \(path.joined(separator: "/"))",
                 "Type: \(kind.label)\(done ? ", done" : "")\(today ? ", today" : "")"]
        if !tags.isEmpty { l.append("Tags: " + tags.map { "#\($0)" }.joined(separator: " ")) }
        if !quote.isEmpty { l.append("Highlighted:\n" + quote.split(separator: "\n", omittingEmptySubsequences: false).map { "> \($0)" }.joined(separator: "\n")) }
        if !notes.isEmpty { l.append("Notes:\n\(notes)") }
        var src = [sourceApp, sourceTitle, sourceURL].compactMap { $0 }
        if !src.isEmpty { l.append("Source: " + src.removeFirst() + (src.isEmpty ? "" : " · " + src.joined(separator: " · "))) }
        if !attachments.isEmpty { l.append("Images:\n" + attachments.map { "- " + (store?.attachmentURL($0).path ?? $0) }.joined(separator: "\n")) }
        return l.joined(separator: "\n")
    }

    /// A Markdown note for pasting into documents and chats.
    func markdown(store: NotyStore? = nil) -> String {
        var l = ["## \(title)", ""]
        if !quote.isEmpty { l += quote.split(separator: "\n", omittingEmptySubsequences: false).map { "> \($0)" } + [""] }
        if !notes.isEmpty { l += [notes, ""] }
        for a in attachments { l.append("![](\(store?.attachmentURL(a).path ?? a))") }
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
        l.append("\(items.count) item\(items.count == 1 ? "" : "s"). Read any of them with the noty MCP tool get_item.")
        l += items.map { "- [\($0.done ? "x" : " ")] \($0.title)  (id \($0.id))" }
        return l.joined(separator: "\n")
    }
}
