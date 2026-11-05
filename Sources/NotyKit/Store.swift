// SPDX-License-Identifier: Apache-2.0

import Foundation

/// An agent's suggestion to write a file (a skill, a summary) and optionally finish some items. Nothing is written until the user approves.
public struct Proposal: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String             // relative path inside the library's `_files` folder, e.g. "skills/latency/SKILL.md"
    public var content: String
    public var note: String
    public var itemIds: [String]
    public var completeItems: Bool
    public var created: Date
    public init(id: String = UUID().uuidString, name: String, content: String, note: String = "", itemIds: [String] = [], completeItems: Bool = false, created: Date = Date()) {
        self.id = id; self.name = name; self.content = content; self.note = note; self.itemIds = itemIds; self.completeItems = completeItems; self.created = created
    }
}

public struct LibrarySnapshot: Sendable {
    public var items: [Item]
    public var categories: [CategoryNode]
    /// Files that carried an id already present elsewhere (sync conflicts). The older copy was moved to `_history`.
    public var conflicts: Int
}

/// The library: a folder tree where folders are workspaces/categories and every item is a Markdown file.
/// Plain files make sync trivial (iCloud Drive, Dropbox, git) and let agents and humans edit items directly.
/// Folders starting with `_` or `.` are internal (`_files`, `_proposals`, `_history`, `_trash`) and never shown as categories.
public final class NotyStore: @unchecked Sendable {
    public static let inbox = "Inbox"
    public let root: URL
    private let fm = FileManager.default

    public init(root: URL) { self.root = root }

    // MARK: Location (local, iCloud Drive or any folder)

    public static var iCloudDriveFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Noty", isDirectory: true)
    }
    public static var iCloudDriveAvailable: Bool {
        FileManager.default.fileExists(atPath: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs").path)
    }

    public static func resolveRoot(paths: AppPaths = AppPaths()) -> URL {
        if let data = try? Data(contentsOf: paths.locationFile),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let p = obj["library"] as? String, !p.isEmpty {
            return URL(fileURLWithPath: p, isDirectory: true)
        }
        return paths.defaultLibrary
    }

    public static func saveRoot(_ url: URL, paths: AppPaths = AppPaths()) throws {
        try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: ["library": url.path], options: [.prettyPrinted])
        try data.write(to: paths.locationFile, options: .atomic)
    }

    /// Copies everything from one library folder to another (used when the user switches sync location). Never overwrites.
    public static func copyLibrary(from: URL, to: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: to, withIntermediateDirectories: true)
        guard let en = fm.enumerator(at: from, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        for case let src as URL in en {
            let rel = String(src.path.dropFirst(from.path.count + 1))
            let dst = to.appendingPathComponent(rel)
            if (try? src.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { try fm.createDirectory(at: dst, withIntermediateDirectories: true) }
            else if !fm.fileExists(atPath: dst.path) { try fm.copyItem(at: src, to: dst) }
        }
    }

    // MARK: Names

    public static func cleanName(_ s: String) -> String {
        var n = s.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while n.hasPrefix(".") || n.hasPrefix("_") { n.removeFirst() }
        n = String(n.prefix(60)).trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? "Untitled" : n
    }

    /// "Work/Q4 Launch" or "Work › Q4 Launch" into clean path components.
    public static func parsePath(_ s: String) -> [String] {
        s.replacingOccurrences(of: "›", with: "/").split(separator: "/").map { cleanName(String($0)) }
    }

    private func dir(for path: [String]) -> URL { path.reduce(root) { $0.appendingPathComponent($1, isDirectory: true) } }
    private func isInternal(_ name: String) -> Bool { name.hasPrefix("_") || name.hasPrefix(".") }

    // MARK: Read

    /// Creates the folder and the starter workspaces on first run.
    public func prepare() throws {
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let existing = (try? fm.contentsOfDirectory(atPath: root.path)) ?? []
        if !existing.contains(where: { !isInternal($0) }) {
            for name in [Self.inbox, "Work", "Personal"] { try createCategory([name]) }
        }
        if !fm.fileExists(atPath: dir(for: [Self.inbox]).path) { try createCategory([Self.inbox]) }
    }

    public func load() -> LibrarySnapshot {
        var items: [Item] = []
        var categories: [CategoryNode] = []
        var seen: [String: (Item, Date)] = [:]
        var conflicts = 0
        func walk(_ url: URL, _ path: [String]) {
            guard let kids = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey]) else { return }
            for k in kids.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
                let name = k.lastPathComponent
                if isInternal(name) { continue }
                let vals = try? k.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
                if vals?.isDirectory == true {
                    let p = path + [name]
                    categories.append(CategoryNode(path: p)); walk(k, p)
                } else if name.hasSuffix(".md"), !path.isEmpty, let text = try? String(contentsOf: k, encoding: .utf8), var item = ItemFile.decode(text) {
                    item.path = path; item.file = k
                    let mod = vals?.contentModificationDate ?? .distantPast
                    if let (other, otherMod) = seen[item.id] {
                        conflicts += 1
                        let loser = mod > otherMod ? other : item
                        archive(loser.file)
                        if mod > otherMod { seen[item.id] = (item, mod) }
                    } else { seen[item.id] = (item, mod) }
                }
            }
        }
        walk(root, [])
        items = seen.values.map(\.0).sorted { $0.created > $1.created }
        return LibrarySnapshot(items: items, categories: categories, conflicts: conflicts)
    }

    /// Cheap change detector for polling: file count and newest modification time.
    public func signature() -> String {
        var count = 0; var newest = Date.distantPast
        if let en = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey]) {
            for case let u as URL in en {
                if u.lastPathComponent.hasPrefix(".") { continue }
                count += 1
                if let d = try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, d > newest { newest = d }
            }
        }
        return "\(count)-\(newest.timeIntervalSince1970)"
    }

    private func archive(_ file: URL?) {
        guard let file else { return }
        let h = root.appendingPathComponent("_history", isDirectory: true)
        try? fm.createDirectory(at: h, withIntermediateDirectories: true)
        try? fm.moveItem(at: file, to: h.appendingPathComponent("\(Int(Date().timeIntervalSince1970))-\(file.lastPathComponent)"))
    }

    public func item(id: String) -> Item? { load().items.first { $0.id == id } }

    // MARK: Write

    public func createCategory(_ path: [String]) throws {
        guard !path.isEmpty else { throw UserFacingError("A category needs a name.") }
        try fm.createDirectory(at: dir(for: path.map(Self.cleanName)), withIntermediateDirectories: true)
    }

    public func deleteCategory(_ path: [String]) throws {
        guard path != [Self.inbox], !path.isEmpty else { throw UserFacingError("The Inbox can't be deleted.") }
        let d = dir(for: path)
        let has = (fm.enumerator(at: d, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? []).contains { $0.pathExtension == "md" }
        guard !has else { throw UserFacingError("Move or finish the items in this category before deleting it.") }
        try fm.trashItem(at: d, resultingItemURL: nil)
    }

    /// Renames a workspace or category (the last path component). Items inside move with the folder.
    public func renameCategory(_ path: [String], to newName: String) throws {
        guard path != [Self.inbox], !path.isEmpty else { throw UserFacingError("The Inbox can't be renamed.") }
        let name = Self.cleanName(newName)
        let target = dir(for: Array(path.dropLast()) + [name])
        guard !fm.fileExists(atPath: target.path) else { throw UserFacingError("There is already a category called “\(name)” here.") }
        try fm.moveItem(at: dir(for: path), to: target)
    }

    /// Writes the item, creating its folder and moving the file if its category changed. Returns the saved item (with `file` set).
    @discardableResult
    public func save(_ item: Item) throws -> Item {
        var it = item
        it.path = item.path.isEmpty ? [Self.inbox] : item.path.map(Self.cleanName)
        let folder = dir(for: it.path)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        var target = it.file
        if let f = target, f.deletingLastPathComponent().standardizedFileURL != folder.standardizedFileURL {
            let dest = folder.appendingPathComponent(f.lastPathComponent)
            if fm.fileExists(atPath: f.path) { try fm.moveItem(at: f, to: dest) }
            target = dest
        }
        let file = target ?? folder.appendingPathComponent(Self.fileName(for: it))
        try Data(ItemFile.encode(it).utf8).write(to: file, options: .atomic)
        it.file = file
        return it
    }

    public func delete(_ item: Item) throws {
        for a in item.attachments { try? fm.trashItem(at: attachmentURL(a), resultingItemURL: nil) }
        guard let f = item.file else { return }
        do { try fm.trashItem(at: f, resultingItemURL: nil) } catch { try fm.removeItem(at: f) }
    }

    static func fileName(for item: Item) -> String {
        let slug = item.title.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
            .split(separator: "-", omittingEmptySubsequences: true).joined(separator: "-")
        return "\(slug.prefix(40).isEmpty ? "item" : String(slug.prefix(40)))-\(item.id.prefix(6).lowercased()).md"
    }

    // MARK: Attachments (images from the highlighted selection)

    public var attachmentsDir: URL { root.appendingPathComponent("_attachments", isDirectory: true) }
    public func attachmentURL(_ name: String) -> URL { attachmentsDir.appendingPathComponent((name as NSString).lastPathComponent) }

    /// Saves PNG data next to the library and returns the file name to store on the item.
    public func saveAttachment(_ data: Data, itemID: String, index: Int, ext: String = "png") throws -> String {
        try fm.createDirectory(at: attachmentsDir, withIntermediateDirectories: true)
        let clean = String(ext.lowercased().filter { $0.isLetter || $0.isNumber }.prefix(8))
        let name = "\(itemID.prefix(8).lowercased())-\(index).\(clean.isEmpty ? "bin" : clean)"
        try data.write(to: attachmentURL(name), options: .atomic)
        return name
    }

    // MARK: Agent proposals

    private var proposalsDir: URL { root.appendingPathComponent("_proposals", isDirectory: true) }
    public var filesDir: URL { root.appendingPathComponent("_files", isDirectory: true) }

    public func addProposal(_ p: Proposal) throws {
        _ = try Self.safeRelativePath(p.name)
        try fm.createDirectory(at: proposalsDir, withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(p).write(to: proposalsDir.appendingPathComponent("\(p.id).json"), options: .atomic)
    }

    public func proposals() -> [Proposal] {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let files = (try? fm.contentsOfDirectory(at: proposalsDir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.compactMap { try? dec.decode(Proposal.self, from: Data(contentsOf: $0)) }.sorted { $0.created > $1.created }
    }

    public func discardProposal(_ id: String) { try? fm.removeItem(at: proposalsDir.appendingPathComponent("\(id).json")) }

    /// Writes the proposed file (never overwriting: a number is added to the name) and finishes the listed items if asked.
    @discardableResult
    public func approve(_ p: Proposal) throws -> URL {
        let rel = try Self.safeRelativePath(p.name)
        var dest = filesDir.appendingPathComponent(rel)
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        var n = 2
        while fm.fileExists(atPath: dest.path) {
            let base = dest.deletingPathExtension().lastPathComponent.replacingOccurrences(of: #" \d+$"#, with: "", options: .regularExpression)
            dest = dest.deletingLastPathComponent().appendingPathComponent("\(base) \(n)").appendingPathExtension(dest.pathExtension); n += 1
        }
        try Data(p.content.utf8).write(to: dest, options: .atomic)
        if p.completeItems {
            let lib = load()
            for id in p.itemIds { if var it = lib.items.first(where: { $0.id == id }) { it.done = true; try save(it) } }
        }
        discardProposal(p.id)
        return dest
    }

    /// A relative path made only of clean components, so an agent can never write outside `_files`.
    public static func safeRelativePath(_ name: String) throws -> String {
        let parts = name.split(separator: "/").map(String.init)
        guard !name.hasPrefix("/"), !parts.isEmpty, parts.count <= 6,
              !parts.contains(where: { $0 == ".." || $0 == "." || $0.hasPrefix(".") || $0.contains("\0") || $0.contains(":") }) else {
            throw UserFacingError("That file name isn't allowed. Use a simple relative name such as skills/my-skill/SKILL.md.")
        }
        return parts.joined(separator: "/")
    }
}
