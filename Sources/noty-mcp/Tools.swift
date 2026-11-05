// SPDX-License-Identifier: Apache-2.0

import Foundation
import NotyKit

typealias Args = [String: Any]

struct Tool {
    let name: String
    let description: String
    let properties: [String: Any]
    let required: [String]
    var readOnly = false
    var destructive = false
    let handler: @Sendable (Args) async throws -> String

    var definition: [String: Any] {
        ["name": name, "description": description,
         "inputSchema": ["type": "object", "properties": properties, "required": required] as [String: Any],
         "annotations": ["readOnlyHint": readOnly, "destructiveHint": destructive] as [String: Any]]
    }
}

struct ToolError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private func prop(_ type: String, _ desc: String, enumValues: [String]? = nil) -> [String: Any] {
    var p: [String: Any] = ["type": type, "description": desc]
    if let e = enumValues { p["enum"] = e }
    return p
}
private func strings(_ desc: String) -> [String: Any] { ["type": "array", "items": ["type": "string"], "description": desc] }

private func text(_ v: Any) throws -> String {
    String(decoding: try JSONSerialization.data(withJSONObject: v, options: [.sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
}

private func requireString(_ a: Args, _ key: String) throws -> String {
    guard let v = a[key] as? String, !v.isEmpty else { throw ToolError(message: "Missing required argument: \(key)") }
    return v
}

private func store() throws -> NotyStore {
    let s = NotyStore(root: NotyStore.resolveRoot())
    do { try s.prepare() } catch { throw ToolError(message: "Noty's library folder could not be opened. Open the Noty app once and check Settings → Sync.") }
    return s
}

private func find(_ s: NotyStore, _ id: String) throws -> Item {
    guard let it = s.load().items.first(where: { $0.id == id || $0.id.hasPrefix(id) && id.count >= 6 }) else { throw ToolError(message: "No item with id \(id). Use list_items or search to find ids.") }
    return it
}

private func dict(_ it: Item, full: Bool = true) -> [String: Any] {
    var d: [String: Any] = ["id": it.id, "title": it.title, "kind": it.kind.rawValue, "done": it.done, "today": it.today,
                            "path": it.pathLabel.replacingOccurrences(of: " › ", with: "/"), "tags": it.tags]
    if full {
        d["quote"] = it.quote; d["notes"] = it.notes
        var src: [String: Any] = [:]
        if let v = it.sourceApp { src["app"] = v }; if let v = it.sourceTitle { src["title"] = v }; if let v = it.sourceURL { src["url"] = v }
        if !src.isEmpty { d["source"] = src }
        d["created"] = ISO8601DateFormatter().string(from: it.created)
    } else if !it.quote.isEmpty { d["quote"] = String(it.quote.prefix(160)) }
    return d
}

private func kind(_ a: Args) throws -> ItemKind? {
    guard let k = a["kind"] as? String else { return nil }
    guard let kind = ItemKind(rawValue: k) else { throw ToolError(message: "kind must be one of: task, note, reference, idea.") }
    return kind
}

private let itemFields: [String: Any] = [
    "title": prop("string", "Short title."),
    "path": prop("string", "Category path such as \"Work/Q4 Launch/Research\". The first part is the workspace. Created if missing. Default: Inbox."),
    "kind": prop("string", "task, note, reference or idea.", enumValues: ItemKind.allCases.map(\.rawValue)),
    "quote": prop("string", "The captured source text."),
    "notes": prop("string", "Notes."),
    "tags": strings("Tags without the # sign."),
    "today": prop("boolean", "Show in Today."),
]

// Tool design: verb_noun names, read-only first, compact JSON. Changes to files go through propose_file (the user approves in the app).
// Deleting needs confirm_title equal to the item's title. Nothing here ever deletes categories.
let allTools: [Tool] = {
    var t: [Tool] = []

    t.append(Tool(name: "get_status", description: "Noty's version, library location and item counts.", properties: [:], required: [], readOnly: true) { _ in
        let s = try store(); let lib = s.load()
        return try text(["version": BuildInfo.current.version, "library": s.root.path, "items": lib.items.count, "open": lib.items.filter { !$0.done }.count,
                         "inbox": lib.items.filter { $0.path.first == NotyStore.inbox && !$0.done }.count, "pending_proposals": s.proposals().count])
    })

    t.append(Tool(name: "list_workspaces", description: "The tree of workspaces and categories with the number of open items in each (including sub-categories).", properties: [:], required: [], readOnly: true) { _ in
        let lib = try store().load()
        return try text(lib.categories.map { c in ["path": c.path.joined(separator: "/"), "open_items": lib.items.filter { !$0.done && $0.path.starts(with: c.path) }.count] as [String: Any] })
    })

    t.append(Tool(name: "list_items", description: "List items, newest first. Filter by category (includes sub-categories), status or text. Returns summaries; use get_item for the full text.",
                  properties: ["path": prop("string", "Category path to list, e.g. \"Work/Q4 Launch\". Omit for everything."),
                               "status": prop("string", "open (default), done or all.", enumValues: ["open", "done", "all"]),
                               "today": prop("boolean", "Only items marked Today."),
                               "query": prop("string", "Words that must appear in the title, quote, notes, tags or path."),
                               "limit": prop("integer", "Maximum items, default 50, max 200.")], required: [], readOnly: true) { a in
        let lib = try store().load()
        let status = a["status"] as? String ?? "open"
        let prefix = (a["path"] as? String).map(NotyStore.parsePath) ?? []
        let q = (a["query"] as? String ?? "").lowercased()
        let limit = min(max(a["limit"] as? Int ?? 50, 1), 200)
        let hits = lib.items.filter { it in
            (status == "all" || (status == "done") == it.done) && it.path.starts(with: prefix) && (a["today"] as? Bool != true || it.today)
                && (q.isEmpty || (it.title + " " + it.quote + " " + it.notes + " " + it.tags.joined(separator: " ") + " " + it.pathLabel).lowercased().contains(q))
        }
        return try text(["total": hits.count, "items": hits.prefix(limit).map { dict($0, full: false) }] as [String: Any])
    })

    t.append(Tool(name: "get_item", description: "Everything about one item: highlighted text, notes, source app/title/URL, tags and category.",
                  properties: ["id": prop("string", "Item id (a prefix of at least 6 characters also works).")], required: ["id"], readOnly: true) { a in
        try text(dict(try find(try store(), try requireString(a, "id"))))
    })

    t.append(Tool(name: "search", description: "Search all items by words in title, highlighted text, notes, tags or category.",
                  properties: ["query": prop("string", "Search words."), "limit": prop("integer", "Maximum items, default 20.")], required: ["query"], readOnly: true) { a in
        let q = try requireString(a, "query").lowercased()
        let lib = try store().load()
        let words = q.split(separator: " ").map(String.init)
        let hits = lib.items.filter { it in let hay = (it.title + " " + it.quote + " " + it.notes + " " + it.tags.joined(separator: " ") + " " + it.pathLabel).lowercased(); return words.allSatisfy(hay.contains) }
        return try text(["total": hits.count, "items": hits.prefix(min(max(a["limit"] as? Int ?? 20, 1), 100)).map { dict($0, full: false) }] as [String: Any])
    })

    t.append(Tool(name: "add_item", description: "Add an item (a task, note, reference or idea). Creates the category if it does not exist.",
                  properties: itemFields.merging(["source_app": prop("string", "App the text came from."), "source_title": prop("string", "Page or document title."), "source_url": prop("string", "Link to the source.")]) { a, _ in a },
                  required: ["title"]) { a in
        let s = try store()
        let path = (a["path"] as? String).map(NotyStore.parsePath) ?? [NotyStore.inbox]
        let item = Item(title: try requireString(a, "title"), kind: try kind(a) ?? .task, today: a["today"] as? Bool ?? false, tags: a["tags"] as? [String] ?? [],
                        quote: a["quote"] as? String ?? "", notes: a["notes"] as? String ?? "", sourceApp: a["source_app"] as? String,
                        sourceTitle: a["source_title"] as? String, sourceURL: a["source_url"] as? String, path: path.isEmpty ? [NotyStore.inbox] : path)
        return try text(dict(try s.save(item), full: false))
    })

    t.append(Tool(name: "update_item", description: "Change an item's title, kind, tags, Today flag or notes. Use append_notes to add to the existing notes instead of replacing them.",
                  properties: itemFields.filter { $0.key != "path" && $0.key != "quote" }.merging(["id": prop("string", "Item id."), "append_notes": prop("string", "Text added after the existing notes.")]) { a, _ in a },
                  required: ["id"]) { a in
        let s = try store(); var it = try find(s, try requireString(a, "id"))
        if let v = a["title"] as? String, !v.isEmpty { it.title = v }
        if let v = try kind(a) { it.kind = v }
        if let v = a["tags"] as? [String] { it.tags = v }
        if let v = a["today"] as? Bool { it.today = v }
        if let v = a["notes"] as? String { it.notes = v }
        if let v = a["append_notes"] as? String, !v.isEmpty { it.notes += (it.notes.isEmpty ? "" : "\n\n") + v }
        return try text(dict(try s.save(it), full: false))
    })

    t.append(Tool(name: "move_item", description: "Move an item to another category (created if missing).",
                  properties: ["id": prop("string", "Item id."), "path": prop("string", "Destination, e.g. \"Work/Q4 Launch/Build\".")], required: ["id", "path"]) { a in
        let s = try store(); var it = try find(s, try requireString(a, "id"))
        let p = NotyStore.parsePath(try requireString(a, "path")); guard !p.isEmpty else { throw ToolError(message: "path is empty.") }
        it.path = p
        return try text(dict(try s.save(it), full: false))
    })

    t.append(Tool(name: "complete_item", description: "Mark an item done (or not done with done=false).",
                  properties: ["id": prop("string", "Item id."), "done": prop("boolean", "Default true.")], required: ["id"]) { a in
        let s = try store(); var it = try find(s, try requireString(a, "id"))
        it.done = a["done"] as? Bool ?? true
        return try text(dict(try s.save(it), full: false))
    })

    t.append(Tool(name: "create_category", description: "Create a workspace or category, e.g. \"Work/Q4 Launch/Research\".", properties: ["path": prop("string", "Category path.")], required: ["path"]) { a in
        let p = NotyStore.parsePath(try requireString(a, "path"))
        try store().createCategory(p)
        return "Created \(p.joined(separator: "/"))."
    })

    t.append(Tool(name: "propose_file", description: "Propose writing a Markdown file (a skill, a summary, a plan). Nothing is written until the user approves it in Noty under Agent results. For a skill use name \"skills/<skill-name>/SKILL.md\". Optionally finish the source items when approved.",
                  properties: ["name": prop("string", "Relative file name, e.g. skills/latency-budgets/SKILL.md or notes/q4-research.md. No leading slash, no .."),
                               "content": prop("string", "Full file contents."), "note": prop("string", "One line telling the user what this is."),
                               "item_ids": strings("Ids of the items this was made from."), "complete_items": prop("boolean", "Mark item_ids done when the user approves.")],
                  required: ["name", "content"]) { a in
        let s = try store()
        let p = Proposal(name: try requireString(a, "name"), content: try requireString(a, "content"), note: a["note"] as? String ?? "",
                         itemIds: a["item_ids"] as? [String] ?? [], completeItems: a["complete_items"] as? Bool ?? false)
        do { try s.addProposal(p) } catch let e as UserFacingError { throw ToolError(message: e.message) }
        return "Proposal saved. The user can approve it in Noty → Agent results. Nothing has been written yet."
    })

    t.append(Tool(name: "delete_item", description: "DESTRUCTIVE. Moves an item to the Trash. `confirm_title` must equal the item's exact title. Ask the user before calling; prefer complete_item.",
                  properties: ["id": prop("string", "Item id."), "confirm_title": prop("string", "Repeat the item's title to confirm.")], required: ["id", "confirm_title"], destructive: true) { a in
        let s = try store(); let it = try find(s, try requireString(a, "id"))
        guard try requireString(a, "confirm_title") == it.title else { throw ToolError(message: "confirm_title must equal the item's title (\"\(it.title)\"). Nothing was deleted.") }
        try s.delete(it)
        return "Moved \"\(it.title)\" to the Trash."
    })

    return t
}()
