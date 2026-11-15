import XCTest
@testable import NotyKit

final class ItemQueryAdversarialTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func ago(_ s: TimeInterval) -> Date { now.addingTimeInterval(-s) }
    func ids(_ q: ItemQuery, _ items: [Item]) -> [String] { q.apply(items, now: now).map(\.id) }

    // MARK: categories

    func testCategoryPrefixIsByPathComponentNotString() {
        let items = [Item(id: "w", title: "x", path: ["Work"]), Item(id: "wq", title: "y", path: ["Work", "Q4"]),
                     Item(id: "wo", title: "z", path: ["Wo"])]
        var q = ItemQuery(); q.categories = [["Wo"]]
        XCTAssertEqual(ids(q, items), ["wo"])
        q.categories = [["Work", "Q"]]
        XCTAssertEqual(ids(q, items), [])
        q.categories = [["Work", "Q4", "Deeper"]]           // longer than item path: no match
        XCTAssertEqual(ids(q, items), [])
    }

    func testCategoryWithPipeInNameRoundTrips() {
        var q = ItemQuery(); q.categories = [["A|B", "C"], ["D"]]
        let back = ItemQuery(query: q.queryItems)
        XCTAssertEqual(back.categories, q.categories, "cats=\(q.queryItems["cats"] ?? "")")
    }

    func testCategoryWithSlashInNameRoundTrips() {
        // Stored names are cleaned of "/" but an in-memory category could still carry one.
        var q = ItemQuery(); q.categories = [["A/B"]]
        let back = ItemQuery(query: q.queryItems)
        XCTAssertEqual(back.categories, q.categories, "cats=\(q.queryItems["cats"] ?? "")")
    }

    // MARK: tags

    func testTagFoldingCaseAndDiacritics() {
        let items = [Item(id: "a", title: "x", tags: ["Café"]), Item(id: "b", title: "y", tags: ["CAFE"]), Item(id: "c", title: "z", tags: ["caff"])]
        var q = ItemQuery(); q.tags = ["cafe"]
        XCTAssertEqual(Set(ids(q, items)), ["a", "b"])
        q.tags = ["CAFÉ"]
        XCTAssertEqual(Set(ids(q, items)), ["a", "b"])
    }

    func testTagMustMatchWholeTagNotSubstring() {
        let items = [Item(id: "a", title: "x", tags: ["workshop"])]
        var q = ItemQuery(); q.tags = ["work"]
        XCTAssertEqual(ids(q, items), [])
    }

    func testTagCountsMergeCaseAndCountOncePerItem() {
        let items = [Item(id: "a", title: "x", tags: ["Work", "work", "WORK"]), Item(id: "b", title: "y", tags: ["work"]),
                     Item(id: "c", title: "z", tags: ["b", "a"])]
        let c = ItemQuery.tagCounts(items)
        XCTAssertEqual(c.first?.tag, "Work"); XCTAssertEqual(c.first?.count, 2)
        XCTAssertEqual(c.map(\.tag), ["Work", "a", "b"])
    }

    // MARK: URL params

    func testEmptyAndGarbageParamsAreIgnored() {
        let q = ItemQuery(query: ["tags": ",, ,", "cats": "||/|", "kinds": "bogus,,TASK", "status": "OPEN", "today": "true",
                                  "reminders": "yes", "attachments": "", "added": "decade", "sort": "random", "zzz": "1"])
        XCTAssertEqual(q, ItemQuery())
        XCTAssertFalse(q.isFiltering)
        XCTAssertEqual(q.activeFilterCount, 0)
    }

    func testPartialGarbageKeepsValidParts() {
        let q = ItemQuery(query: ["kinds": "task,bogus", "tags": " a , ,b ", "cats": "Work//Q4| |Home"])
        XCTAssertEqual(q.kinds, [.task])
        XCTAssertEqual(q.tags, ["a", "b"])
        XCTAssertEqual(q.categories, [["Work", "Q4"], ["Home"]])
    }

    func testFullRoundTrip() {
        var q = ItemQuery()
        q.text = "  café  plan "; q.tags = ["Work", "urgent", "a b"]; q.categories = [["Work", "Q4 Launch"], ["Inbox"]]
        q.kinds = [.task, .idea, .note, .reference]; q.status = .done; q.onlyToday = true; q.withReminders = true
        q.withAttachments = true; q.added = .month
        for s in ItemQuery.Sort.allCases {
            q.sort = s
            XCTAssertEqual(ItemQuery(query: q.queryItems), q, "\(s)")
        }
        XCTAssertEqual(ItemQuery(query: ItemQuery().queryItems), ItemQuery())
        XCTAssertEqual(ItemQuery().queryItems, [:])
    }

    func testQueryItemsDeterministic() {
        var q = ItemQuery(); q.tags = Set((0..<20).map { "t\($0)" }); q.categories = Set((0..<20).map { ["c\($0)", "x"] })
        let a = q.queryItems
        for _ in 0..<5 { XCTAssertEqual(ItemQuery(query: a).queryItems, a) }
    }

    func testClearingFiltersKeepsTextAndSort() {
        var q = ItemQuery(query: ["q": "x", "sort": "oldest", "tags": "a", "today": "1", "added": "week", "status": "open"])
        XCTAssertEqual(q.activeFilterCount, 4)
        q = q.clearingFilters()
        XCTAssertEqual(q.text, "x"); XCTAssertEqual(q.sort, .oldest); XCTAssertFalse(q.isFiltering)
    }

    // MARK: dates

    func testDateBoundariesWithFixedNow() {
        let items = [Item(id: "edge", title: "e", created: ago(86_400)), Item(id: "over", title: "o", created: ago(86_401)),
                     Item(id: "future", title: "f", created: now.addingTimeInterval(1000)),
                     Item(id: "y", title: "y", created: ago(365 * 86_400)), Item(id: "y+", title: "y", created: ago(365 * 86_400 + 1))]
        var q = ItemQuery(); q.added = .day
        XCTAssertEqual(Set(ids(q, items)), ["edge", "future"])
        q.added = .year
        XCTAssertEqual(Set(ids(q, items)), ["edge", "over", "future", "y"])
        q.added = .any
        XCTAssertEqual(ids(q, items).count, 5)
    }

    // MARK: sorting

    func testSortTieDeterminismIndependentOfInputOrder() {
        let t = ago(10)
        let items = (0..<12).map { Item(id: String(format: "id%02d", $0), title: $0 % 2 == 0 ? "Same" : "same", created: t, path: ["P"]) }
        for s in ItemQuery.Sort.allCases {
            var q = ItemQuery(); q.sort = s
            let a = ids(q, items), b = ids(q, items.reversed()), c = ids(q, items.shuffled())
            XCTAssertEqual(a, b, "\(s)"); XCTAssertEqual(a, c, "\(s)")
            if s != .titleAZ && s != .titleZA { XCTAssertEqual(a, a.sorted(), "\(s) ties should fall back to id") }  // "Same" vs "same" is not a tie for localizedStandardCompare
        }
        var q = ItemQuery(); q.text = "same"; q.sort = .relevance
        XCTAssertEqual(ids(q, items), ids(q, items.reversed()))
    }

    func testNextReminderIgnoresDoneReminders() {
        let items = [
            Item(id: "doneSoon", title: "a", created: ago(1), reminders: [Reminder(text: "x", due: now.addingTimeInterval(10), done: true),
                                                                          Reminder(text: "y", due: now.addingTimeInterval(9_000))]),
            Item(id: "open", title: "b", created: ago(2), reminders: [Reminder(text: "z", due: now.addingTimeInterval(500))]),
            Item(id: "allDone", title: "c", created: ago(3), reminders: [Reminder(text: "w", due: now.addingTimeInterval(1), done: true)]),
            Item(id: "none", title: "d", created: ago(0)),
        ]
        var q = ItemQuery(); q.sort = .nextReminder
        XCTAssertEqual(ids(q, items), ["open", "doneSoon", "none", "allDone"])
    }

    func testRelevanceWithEmptyOrBlankTextEqualsNewest() {
        let items = (0..<8).map { Item(id: "i\($0)", title: "t\(7 - $0)", created: ago(TimeInterval(($0 * 37) % 5))) }
        var rel = ItemQuery(); rel.sort = .relevance
        var new = ItemQuery(); new.sort = .newest
        XCTAssertEqual(ids(rel, items), ids(new, items))
        rel.text = "   \t "
        XCTAssertEqual(ids(rel, items), ids(new, items))
    }

    func testRelevanceTitleHitsFirst() {
        let items = [Item(id: "notes", title: "Other", notes: "plan", created: ago(1)),
                     Item(id: "title", title: "The plan", created: ago(100))]
        var q = ItemQuery(); q.text = "PLAN"; q.sort = .relevance
        XCTAssertEqual(ids(q, items), ["title", "notes"])
    }

    // MARK: remote

    private func tmp() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("noty-adv-\(UUID().uuidString)", isDirectory: true) }

    private func get(_ api: RemoteAPI, _ path: String, _ q: [String: String] = [:]) throws -> (Int, [String: Any]) {
        let r = api.handle(HTTPRequest(method: "GET", path: path, query: q, headers: ["host": "127.0.0.1:47653"]))
        return (r.status, (try JSONSerialization.jsonObject(with: r.body) as? [String: Any]) ?? [:])
    }

    func testRemoteItemsFiltersSortsAndIgnoresGarbage() throws {
        let root = tmp(); defer { try? FileManager.default.removeItem(at: root) }
        let s = NotyStore(root: root); try s.prepare()
        try s.createCategory(["Work"]); try s.createCategory(["Wo"])
        _ = try s.save(Item(id: "a", title: "Alpha", tags: ["Café"], created: ago(10), path: ["Work"]))
        _ = try s.save(Item(id: "b", title: "Beta", tags: ["cafe", "x"], created: ago(20), path: ["Wo"]))
        _ = try s.save(Item(id: "c", title: "Gamma", done: true, tags: ["x"], created: ago(5), path: ["Work"]))
        let api = RemoteAPI(store: s)

        func idsOf(_ q: [String: String]) throws -> [String] {
            let (st, j) = try get(api, "/api/items", q); XCTAssertEqual(st, 200)
            return ((j["items"] as? [[String: Any]]) ?? []).compactMap { $0["id"] as? String }
        }
        XCTAssertEqual(try idsOf([:]), ["a", "b"])                                    // open, newest
        XCTAssertEqual(try idsOf(["cats": "Wo"]), ["b"])
        XCTAssertEqual(try idsOf(["tags": "CAFE"]), ["a", "b"])
        XCTAssertEqual(try idsOf(["sort": "titleZA"]), ["b", "a"])
        XCTAssertEqual(try idsOf(["view": "done"]), ["c"])
        XCTAssertEqual(try idsOf(["q": "a", "tags": "x", "sort": "oldest"]), ["b", "c"])  // q searches everything
        XCTAssertEqual(try idsOf(["sort": "nope", "status": "??", "added": "x", "tags": ",", "cats": "|"]), ["a", "b"])
        let (_, j) = try get(api, "/api/items", ["tags": "x"])
        XCTAssertEqual(j["total"] as? Int, 1)
        let first = (j["items"] as? [[String: Any]])?.first
        XCTAssertEqual(first?["tags"] as? [String], ["cafe", "x"])
    }

    func testRemoteFacets() throws {
        let root = tmp(); defer { try? FileManager.default.removeItem(at: root) }
        let s = NotyStore(root: root); try s.prepare()
        try s.createCategory(["Empty", "Sub"])
        _ = try s.save(Item(id: "a", title: "A", tags: ["Work"], path: ["Work", "Q4"]))
        _ = try s.save(Item(id: "b", title: "B", done: true, tags: ["work", "z"], path: ["Work"]))
        let (st, j) = try get(RemoteAPI(store: s), "/api/facets", ["view": "today"])
        XCTAssertEqual(st, 200)
        let tags = (j["tags"] as? [[String: Any]]) ?? []
        XCTAssertEqual(tags.first?["name"] as? String, "Work"); XCTAssertEqual(tags.first?["count"] as? Int, 2)
        let keys = ((j["categories"] as? [[String: Any]]) ?? []).compactMap { $0["key"] as? String }
        XCTAssertTrue(keys.contains("Work/Q4")); XCTAssertTrue(keys.contains("Empty/Sub"))
        XCTAssertEqual(keys.count, Set(keys).count, "no duplicate categories")
        let cat = ((j["categories"] as? [[String: Any]]) ?? []).first { $0["key"] as? String == "Work/Q4" }
        XCTAssertEqual(cat?["path"] as? String, "Work › Q4")
        // keys must feed back into cats
        XCTAssertEqual(ItemQuery(query: ["cats": keys.joined(separator: "|")]).categories.count, keys.count)
    }
}
