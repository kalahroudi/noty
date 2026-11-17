// SPDX-License-Identifier: Apache-2.0

import Foundation

/// What the user is looking for: words, filters and a sort order. Shared by the Mac app and the remote web app.
public struct ItemQuery: Equatable, Sendable {
    public enum Status: String, CaseIterable, Sendable {
        case any, open, done
        public var label: String { switch self { case .any: "Any"; case .open: "Open"; case .done: "Done" } }
    }
    public enum DateField: String, CaseIterable, Sendable {
        case created, updated
        public var label: String {
            switch self { case .created: "Created"; case .updated: "Updated" }
        }
    }
    public enum DateRange: String, CaseIterable, Sendable {
        case any, today, yesterday, day, thisWeek, week, thisMonth, month, year, custom
        public var label: String {
            switch self {
            case .any: "Any time"
            case .today: "Today"
            case .yesterday: "Yesterday"
            case .day: "Last 24 hours"
            case .thisWeek: "This week"
            case .week: "Last 7 days"
            case .thisMonth: "This month"
            case .month: "Last 30 days"
            case .year: "Last year"
            case .custom: "Custom range"
            }
        }
        public var shortLabel: String {
            switch self {
            case .any: "All"
            case .today: "Today"
            case .yesterday: "Yesterday"
            case .day: "24h"
            case .thisWeek: "This week"
            case .week: "7 days"
            case .thisMonth: "This month"
            case .month: "30 days"
            case .year: "Year"
            case .custom: "Custom…"
            }
        }
        /// Presets shown in the quick-filter bar.
        public static let quickPresets: [DateRange] = [.any, .today, .yesterday, .thisWeek, .week, .thisMonth, .month, .year, .custom]
    }
    public enum Sort: String, CaseIterable, Sendable {
        case relevance, newest, updated, oldest, titleAZ, titleZA, category, nextReminder
        public var label: String {
            switch self {
            case .relevance: "Best match"; case .newest: "Newest first"; case .updated: "Recently updated"; case .oldest: "Oldest first"; case .titleAZ: "Title A–Z"
            case .titleZA: "Title Z–A"; case .category: "Category"; case .nextReminder: "Next reminder"
            }
        }
    }

    public var text = ""
    public var tags: Set<String> = []
    public var categories: Set<[String]> = []
    public var kinds: Set<ItemKind> = []
    public var status: Status = .any
    public var onlyToday = false
    public var withReminders = false
    public var withAttachments = false
    public var dateField: DateField = .created
    public var added: DateRange = .any
    public var dateFrom: Date?
    public var dateTo: Date?
    public var sort: Sort = .newest

    public init() {}

    public var hasDateFilter: Bool { added != .any || dateFrom != nil || dateTo != nil }

    public var activeFilterCount: Int {
        tags.count + categories.count + kinds.count + (status == .any ? 0 : 1) + (onlyToday ? 1 : 0) + (withReminders ? 1 : 0) + (withAttachments ? 1 : 0) + (hasDateFilter ? 1 : 0)
    }
    public var isFiltering: Bool { activeFilterCount > 0 }

    public func clearingFilters() -> ItemQuery {
        var q = ItemQuery(); q.text = text; q.sort = sort; return q
    }

    // MARK: Applying

    public static func fold(_ s: String) -> String { s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
    var words: [String] { text.split(whereSeparator: \.isWhitespace).map { Self.fold(String($0)) } }

    public func matches(_ it: Item, now: Date = Date()) -> Bool { matches(it, words: words, now: now) }

    private func matches(_ it: Item, words: [String], now: Date) -> Bool {
        if !words.isEmpty {
            let hay = Self.fold([it.title, it.quote, it.notes, it.tags.joined(separator: " "), it.pathLabel].joined(separator: " "))
            guard words.allSatisfy(hay.contains) else { return false }
        }
        if !tags.isEmpty {
            let have = Set(it.tags.map(Self.fold))
            guard tags.allSatisfy({ have.contains(Self.fold($0)) }) else { return false }
        }
        if !categories.isEmpty, !categories.contains(where: { it.path.starts(with: $0) }) { return false }
        if !kinds.isEmpty, !kinds.contains(it.kind) { return false }
        switch status { case .any: break; case .open: if it.done { return false }; case .done: if !it.done { return false } }
        if onlyToday, !it.today { return false }
        if withReminders, !it.reminders.contains(where: { !$0.done }) { return false }
        if withAttachments, !it.attachments.contains(where: { !$0.lowercased().hasSuffix(".html") }) { return false }
        let targetDate = dateField == .created ? it.created : it.updated
        if !matchesDate(targetDate, now: now) { return false }
        return true
    }

    private func matchesDate(_ date: Date, now: Date) -> Bool {
        let cal = Calendar.current
        switch added {
        case .any:
            if dateFrom != nil || dateTo != nil {
                if let from = dateFrom, date < cal.startOfDay(for: from) { return false }
                if let to = dateTo, let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: to)), date >= end { return false }
            }
            return true
        case .today:
            let start = cal.startOfDay(for: now)
            guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return true }
            return date >= start && date < end
        case .yesterday:
            let end = cal.startOfDay(for: now)
            guard let start = cal.date(byAdding: .day, value: -1, to: end) else { return true }
            return date >= start && date < end
        case .day:
            return date >= now.addingTimeInterval(-86_400)
        case .thisWeek:
            guard let iv = cal.dateInterval(of: .weekOfYear, for: now) else { return true }
            return date >= iv.start && date < iv.end
        case .week:
            return date >= now.addingTimeInterval(-7 * 86_400)
        case .thisMonth:
            guard let iv = cal.dateInterval(of: .month, for: now) else { return true }
            return date >= iv.start && date < iv.end
        case .month:
            return date >= now.addingTimeInterval(-30 * 86_400)
        case .year:
            return date >= now.addingTimeInterval(-365 * 86_400)
        case .custom:
            if let from = dateFrom, date < cal.startOfDay(for: from) { return false }
            if let to = dateTo, let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: to)), date >= end { return false }
            return true
        }
    }

    /// Filters, then sorts. Ties always fall back to the id so the order never flickers.
    public func apply(_ items: [Item], now: Date = Date()) -> [Item] {
        let w = words
        let hits = items.filter { matches($0, words: w, now: now) }
        func newest(_ a: Item, _ b: Item) -> Bool { a.created != b.created ? a.created > b.created : a.id < b.id }
        func nextDue(_ i: Item) -> Date? { i.reminders.filter { !$0.done }.map(\.due).min() }
        switch sort {
        case .relevance where !w.isEmpty:
            func rank(_ i: Item) -> Int { let t = Self.fold(i.title); return w.allSatisfy(t.contains) ? 0 : (w.contains(where: t.contains) ? 1 : 2) }
            return hits.sorted { let (x, y) = (rank($0), rank($1)); return x != y ? x < y : newest($0, $1) }
        case .relevance, .newest: return hits.sorted(by: newest)
        case .updated: return hits.sorted { $0.updated != $1.updated ? $0.updated > $1.updated : newest($0, $1) }
        case .oldest: return hits.sorted { $0.created != $1.created ? $0.created < $1.created : $0.id < $1.id }
        case .titleAZ, .titleZA:
            let up = sort == .titleAZ
            return hits.sorted {
                let c = $0.title.localizedStandardCompare($1.title)
                return c != .orderedSame ? (up ? c == .orderedAscending : c == .orderedDescending) : $0.id < $1.id
            }
        case .category:
            return hits.sorted {
                let c = $0.pathLabel.localizedStandardCompare($1.pathLabel)
                return c != .orderedSame ? c == .orderedAscending : newest($0, $1)
            }
        case .nextReminder:
            return hits.sorted {
                switch (nextDue($0), nextDue($1)) {
                case let (a?, b?) where a != b: return a < b
                case (.some, .none): return true
                case (.none, .some): return false
                default: return newest($0, $1)
                }
            }
        }
    }

    /// Every tag with how many items carry it. Spellings that differ only by case merge under the first one seen.
    public static func tagCounts(_ items: [Item]) -> [(tag: String, count: Int)] {
        var spell: [String: [String: Int]] = [:], counts: [String: Int] = [:]
        for it in items {
            var seen = Set<String>()
            for t in it.tags where !t.isEmpty {
                let k = fold(t)
                if seen.insert(k).inserted { counts[k, default: 0] += 1; spell[k, default: [:]][t, default: 0] += 1 }
            }
        }
        func name(_ k: String) -> String { spell[k]!.min { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }!.key }
        return counts.map { (tag: name($0.key), count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.tag.localizedStandardCompare($1.tag) == .orderedAscending }
    }

    // MARK: URL query (remote web app)

    /// A category path as one string for URLs: components percent-encoded (so "/", "|" and "%" survive), joined by "/".
    public static func categoryKey(_ path: [String]) -> String { path.map(encodeKey).joined(separator: "/") }
    /// One tag or path component with everything but letters, digits and `-._~` percent-encoded (spaces too, so edges survive).
    public static func encodeKey(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: keyAllowed) ?? s }
    private static let keyAllowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))

    private static let dayParser: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()

    public init(query d: [String: String]) {
        func list(_ k: String, _ sep: Character) -> [String] { (d[k] ?? "").split(separator: sep).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
        text = d["q"] ?? ""
        tags = Set(list("tags", ",").map { $0.removingPercentEncoding ?? $0 })
        categories = Set(list("cats", "|").map { $0.split(separator: "/").map { $0.removingPercentEncoding ?? String($0) } }.filter { !$0.isEmpty })
        kinds = Set(list("kinds", ",").compactMap { ItemKind(rawValue: $0) })
        status = d["status"].flatMap(Status.init(rawValue:)) ?? .any
        onlyToday = d["today"] == "1"; withReminders = d["reminders"] == "1"; withAttachments = d["attachments"] == "1"
        dateField = d["date_field"].flatMap(DateField.init(rawValue:)) ?? .created
        added = d["added"].flatMap(DateRange.init(rawValue:)) ?? .any
        dateFrom = d["from"].flatMap { Self.dayParser.date(from: $0) }
        dateTo = d["to"].flatMap { Self.dayParser.date(from: $0) }
        if added == .any && (dateFrom != nil || dateTo != nil) { added = .custom }
        sort = d["sort"].flatMap(Sort.init(rawValue:)) ?? .newest
    }

    public var queryItems: [String: String] {
        var d: [String: String] = [:]
        if !text.isEmpty { d["q"] = text }
        if !tags.isEmpty { d["tags"] = tags.map(Self.encodeKey).sorted().joined(separator: ",") }
        if !categories.isEmpty { d["cats"] = categories.map(Self.categoryKey).sorted().joined(separator: "|") }
        if !kinds.isEmpty { d["kinds"] = kinds.map(\.rawValue).sorted().joined(separator: ",") }
        if status != .any { d["status"] = status.rawValue }
        if onlyToday { d["today"] = "1" }
        if withReminders { d["reminders"] = "1" }
        if withAttachments { d["attachments"] = "1" }
        if dateField != .created { d["date_field"] = dateField.rawValue }
        if added != .any { d["added"] = added.rawValue }
        if added == .custom {
            if let from = dateFrom { d["from"] = Self.dayParser.string(from: from) }
            if let to = dateTo { d["to"] = Self.dayParser.string(from: to) }
        }
        if sort != .newest { d["sort"] = sort.rawValue }
        return d
    }
}
