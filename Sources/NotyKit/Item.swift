// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum ItemKind: String, CaseIterable, Sendable {
    case task, note, reference, idea
    public var label: String { rawValue.capitalized }
    public var symbol: String {
        switch self { case .task: "checkmark.circle"; case .note: "note.text"; case .reference: "link"; case .idea: "lightbulb" }
    }
}

/// One captured thing. On disk it is a Markdown file inside its category folder (see `NotyStore`).
public struct Item: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var kind: ItemKind
    public var done: Bool
    public var today: Bool
    public var tags: [String]
    public var quote: String            // the text that was highlighted
    public var notes: String            // anything the user or an agent added
    public var sourceApp: String?
    public var sourceTitle: String?
    public var sourceURL: String?
    public var created: Date
    /// Image file names (PNG) kept in the library's `_attachments` folder.
    public var attachments: [String]
    /// Workspace first, then categories: ["Work", "Q4 Launch", "Research"]. Mirrors the folders.
    public var path: [String]
    /// Where the file lives right now. Nil until saved.
    public var file: URL?

    public init(id: String = UUID().uuidString, title: String, kind: ItemKind = .task, done: Bool = false, today: Bool = false,
                tags: [String] = [], quote: String = "", notes: String = "", sourceApp: String? = nil, sourceTitle: String? = nil,
                sourceURL: String? = nil, created: Date = Date(), attachments: [String] = [], path: [String] = [NotyStore.inbox], file: URL? = nil) {
        self.id = id; self.title = title; self.kind = kind; self.done = done; self.today = today; self.tags = tags
        self.quote = quote; self.notes = notes; self.sourceApp = sourceApp; self.sourceTitle = sourceTitle; self.sourceURL = sourceURL
        self.created = created; self.attachments = attachments; self.path = path; self.file = file
    }

    /// A short title taken from the first line of a highlighted passage.
    public static func makeTitle(from text: String) -> String {
        var line = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
        if let m = line.range(of: #"^(\d{1,3}[\.\)]|[•◦▪‣·\-–*])\s+"#, options: .regularExpression) { line.removeSubrange(m) }
        if line.count <= 80 { return line }
        let cut = line.prefix(80)
        if let space = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: space) > 40 { return String(cut[..<space]) + "…" }
        return String(cut) + "…"
    }

    public var pathLabel: String { path.joined(separator: " › ") }
}

/// A folder in the library. Empty categories exist too, so the tree can be prepared before anything is captured.
public struct CategoryNode: Identifiable, Equatable, Sendable {
    public var path: [String]
    public var id: String { path.joined(separator: "/") }
    public var name: String { path.last ?? "" }
    public var depth: Int { path.count - 1 }
    public init(path: [String]) { self.path = path }
}

/// Markdown file format. The header is `key: <json value>` lines between `---` fences, so files stay readable and editable by hand.
public enum ItemFile {
    public static func encode(_ item: Item) -> String {
        func j(_ v: Any) -> String {
            guard let d = try? JSONSerialization.data(withJSONObject: v, options: [.fragmentsAllowed, .withoutEscapingSlashes]) else { return "null" }
            return String(decoding: d, as: UTF8.self)
        }
        var h = ["---", "id: \(j(item.id))", "title: \(j(item.title))", "kind: \(j(item.kind.rawValue))", "done: \(item.done)", "today: \(item.today)",
                 "tags: \(j(item.tags))", "created: \(j(iso.string(from: item.created)))"]
        if !item.attachments.isEmpty { h.append("attachments: \(j(item.attachments))") }
        if let v = item.sourceApp { h.append("source_app: \(j(v))") }
        if let v = item.sourceTitle { h.append("source_title: \(j(v))") }
        if let v = item.sourceURL { h.append("source_url: \(j(v))") }
        h.append("---")
        var body = ""
        if !item.quote.isEmpty {
            body += item.quote.split(separator: "\n", omittingEmptySubsequences: false).map { $0.isEmpty ? ">" : "> \($0)" }.joined(separator: "\n") + "\n"
        }
        if !item.notes.isEmpty { body += (body.isEmpty ? "" : "\n") + item.notes + "\n" }
        return h.joined(separator: "\n") + "\n\n" + body
    }

    /// Returns nil when the text has no valid header or no id (a stray .md file the user dropped in the folder).
    public static func decode(_ text: String) -> Item? {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        guard lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") else { return nil }
        var f: [String: Any] = [:]
        for line in lines[1..<end] {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let raw = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if let v = try? JSONSerialization.jsonObject(with: Data(raw.utf8), options: [.fragmentsAllowed]) { f[key] = v }
            else { f[key] = raw }   // tolerate hand-written `title: Plain text`
        }
        guard let id = f["id"] as? String, !id.isEmpty else { return nil }
        var quote: [String] = []
        var rest = Array(lines[(end + 1)...])
        while let first = rest.first, first.isEmpty { rest.removeFirst() }
        while let first = rest.first, first.hasPrefix(">") {
            quote.append(String(first.dropFirst().hasPrefix(" ") ? first.dropFirst(2) : first.dropFirst())); rest.removeFirst()
        }
        let notes = rest.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return Item(id: id, title: f["title"] as? String ?? "Untitled", kind: ItemKind(rawValue: f["kind"] as? String ?? "") ?? .task,
                    done: f["done"] as? Bool ?? false, today: f["today"] as? Bool ?? false, tags: f["tags"] as? [String] ?? [],
                    quote: quote.joined(separator: "\n"), notes: notes, sourceApp: f["source_app"] as? String,
                    sourceTitle: f["source_title"] as? String, sourceURL: f["source_url"] as? String,
                    created: (f["created"] as? String).flatMap { iso.date(from: $0) } ?? Date(), attachments: f["attachments"] as? [String] ?? [])
    }

    nonisolated(unsafe) private static let iso: ISO8601DateFormatter = ISO8601DateFormatter()
}
