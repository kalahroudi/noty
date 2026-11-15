import XCTest
@testable import NotyKit

final class ItemQueryTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func ago(_ s: TimeInterval) -> Date { now.addingTimeInterval(-s) }
    func ids(_ q: ItemQuery, _ items: [Item]) -> [String] { q.apply(items, now: now).map(\.id) }

    var sample: [Item] {
        [Item(id: "a", title: "Café plan", kind: .task, today: true, tags: ["Work", "urgent"], quote: "launch date", created: ago(3_600), attachments: ["a-1.png"], path: ["Work", "Q4"],
              reminders: [Reminder(text: "r", due: now.addingTimeInterval(500))]),
         Item(id: "b", title: "Read paper", kind: .reference, done: true, tags: ["research"], notes: "about plans", created: ago(3 * 86_400), path: ["Work", "Q4", "Research"]),
         Item(id: "c", title: "Buy milk", kind: .idea, tags: ["home", "work"], created: ago(20 * 86_400), attachments: ["c.html"], path: ["Inbox"],
              reminders: [Reminder(text: "late", due: now.addingTimeInterval(100), done: true)]),
         Item(id: "d", title: "zebra", kind: .note, created: ago(400 * 86_400), path: ["Home"],
              reminders: [Reminder(text: "soon", due: now.addingTimeInterval(50))])]
    }

    func testTextAllWordsCaseAndDiacriticInsensitive() {
        var q = ItemQuery(); q.text = "CAFE launch"
        XCTAssertEqual(ids(q, sample), ["a"])
        q.text = "plan work"
        XCTAssertEqual(Set(ids(q, sample)), ["a", "b"])   // notes + path label count
        q.text = "milk zzz"
        XCTAssertEqual(ids(q, sample), [])
    }

    func testTagsMustAllMatchIgnoringCase() {
        var q = ItemQuery(); q.tags = ["WORK"]
        XCTAssertEqual(Set(ids(q, sample)), ["a", "c"])
        q.tags = ["work", "Urgent"]
        XCTAssertEqual(ids(q, sample), ["a"])
    }

    func testCategoriesPrefixAny() {
        var q = ItemQuery(); q.categories = [["Work"]]
        XCTAssertEqual(Set(ids(q, sample)), ["a", "b"])
        q.categories = [["Work", "Q4", "Research"], ["Home"]]
        XCTAssertEqual(Set(ids(q, sample)), ["b", "d"])
    }

    func testKindsStatusAndFlags() {
        var q = ItemQuery(); q.kinds = [.task, .idea]
        XCTAssertEqual(Set(ids(q, sample)), ["a", "c"])
        q = ItemQuery(); q.status = .done
        XCTAssertEqual(ids(q, sample), ["b"])
        q.status = .open
        XCTAssertEqual(Set(ids(q, sample)), ["a", "c", "d"])
        q = ItemQuery(); q.onlyToday = true
        XCTAssertEqual(ids(q, sample), ["a"])
        q = ItemQuery(); q.withReminders = true           // c's only reminder is done
        XCTAssertEqual(Set(ids(q, sample)), ["a", "d"])
        q = ItemQuery(); q.withAttachments = true         // .html is not a file
        XCTAssertEqual(ids(q, sample), ["a"])
    }

    func testDateRanges() {
        var q = ItemQuery()
        for (r, want): (ItemQuery.DateRange, Set<String>) in [(.any, ["a", "b", "c", "d"]), (.day, ["a"]), (.week, ["a", "b"]), (.month, ["a", "b", "c"]), (.year, ["a", "b", "c"])] {
            q.added = r; XCTAssertEqual(Set(ids(q, sample)), want, "\(r)")
        }
    }

    func testSortOrders() {
        var q = ItemQuery()
        q.sort = .newest; XCTAssertEqual(ids(q, sample), ["a", "b", "c", "d"])
        q.sort = .oldest; XCTAssertEqual(ids(q, sample), ["d", "c", "b", "a"])
    }

    func testTitleSorts() {
        var q = ItemQuery()
        q.sort = .titleAZ; XCTAssertEqual(ids(q, sample), ["c", "a", "b", "d"])   // Buy, Café, Read, zebra
        q.sort = .titleZA; XCTAssertEqual(ids(q, sample), ["d", "b", "a", "c"])
    }
    func title(_ id: String) -> String { sample.first { $0.id == id }!.title }

    func testCategoryAndNextReminderSorts() {
        var q = ItemQuery()
        q.sort = .category; XCTAssertEqual(ids(q, sample), ["d", "c", "a", "b"])   // Home, Inbox, Work › Q4, Work › Q4 › Research
        q.sort = .nextReminder; XCTAssertEqual(ids(q, sample), ["d", "a", "b", "c"])
    }

    func testRelevancePutsTitleHitsFirst() {
        let items = [Item(id: "x", title: "other", notes: "milk", created: ago(10), path: ["Inbox"]), Item(id: "y", title: "milk run", created: ago(1000), path: ["Inbox"])]
        var q = ItemQuery(); q.text = "milk"; q.sort = .relevance
        XCTAssertEqual(ids(q, items), ["y", "x"])
        q.text = ""; XCTAssertEqual(ids(q, items), ["x", "y"])   // same as newest without text
    }

    func testTieBreakIsDeterministic() {
        let same = (0..<6).map { Item(id: "i\($0)", title: "Same", created: now, path: ["Inbox"]) }
        for s in ItemQuery.Sort.allCases {
            var q = ItemQuery(); q.sort = s
            let a = ids(q, same), b = ids(q, same.reversed())
            XCTAssertEqual(a, b, "\(s)")
            XCTAssertEqual(a.count, 6)
        }
    }

    func testTagCountsMergeCaseAndSort() {
        let items = [Item(title: "1", tags: ["Work", "x"]), Item(title: "2", tags: ["work"]), Item(title: "3", tags: ["a", "a"])]
        let r = ItemQuery.tagCounts(items)
        XCTAssertEqual(r.map(\.tag), ["Work", "a", "x"])
        XCTAssertEqual(r.map(\.count), [2, 1, 1])
    }

    func testFilterCountAndClearing() {
        var q = ItemQuery(); q.text = "hi"; q.sort = .oldest
        XCTAssertFalse(q.isFiltering)
        q.tags = ["a", "b"]; q.status = .open; q.added = .week
        XCTAssertEqual(q.activeFilterCount, 4)
        let c = q.clearingFilters()
        XCTAssertEqual(c.activeFilterCount, 0); XCTAssertEqual(c.text, "hi"); XCTAssertEqual(c.sort, .oldest)
    }

    func testQueryRoundTripAndUnknownValues() {
        var q = ItemQuery(); q.text = "hello world"; q.tags = ["a", "b"]; q.categories = [["Work", "Q4"], ["Home"]]; q.kinds = [.idea, .task]
        q.status = .done; q.onlyToday = true; q.withReminders = true; q.withAttachments = true; q.added = .month; q.sort = .titleZA
        XCTAssertEqual(ItemQuery(query: q.queryItems), q)
        XCTAssertEqual(ItemQuery().queryItems, [:])
        let bad = ItemQuery(query: ["status": "nope", "sort": "x", "added": "y", "kinds": "task,zzz", "today": "0"])
        XCTAssertEqual(bad.status, .any); XCTAssertEqual(bad.sort, .newest); XCTAssertEqual(bad.added, .any); XCTAssertEqual(bad.kinds, [.task]); XCTAssertFalse(bad.onlyToday)
    }

    func testTagsWithCommasAndEdgeSpacesRoundTrip() {
        var q = ItemQuery(); q.tags = ["a,b", " lead", "trail ", "100%", "x|y"]; q.categories = [["Work ", "a/b"]]
        let d = q.queryItems
        XCTAssertEqual(ItemQuery(query: d), q)
        XCTAssertEqual(d["tags"]?.split(separator: ",").count, 5)
        XCTAssertTrue(ItemQuery(query: ["tags": ItemQuery.encodeKey("a,b")]).matches(Item(title: "t", tags: ["A,B"], path: ["Inbox"])))
        XCTAssertEqual(ItemQuery(query: ["cats": ItemQuery.categoryKey(["Work "])]).categories, [["Work "]])
    }

    func testRemoteStatusReplacesViewRule() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let s = NotyStore(root: root); try s.prepare()
        _ = try s.save(Item(id: "o", title: "Open one", path: ["Inbox"])); _ = try s.save(Item(id: "d", title: "Done one", done: true, path: ["Inbox"]))
        let api = RemoteAPI(store: s)
        func ids(_ q: [String: String]) throws -> Set<String> {
            let r = api.handle(HTTPRequest(method: "GET", path: "/api/items", query: q, headers: ["host": "127.0.0.1:1"]))
            let j = try JSONSerialization.jsonObject(with: r.body) as! [String: Any]
            return Set((j["items"] as! [[String: Any]]).map { $0["id"] as! String })
        }
        XCTAssertEqual(try ids(["view": "inbox"]), ["o"])
        XCTAssertEqual(try ids(["view": "inbox", "status": "done"]), ["d"])
        XCTAssertEqual(try ids(["view": "done", "status": "open"]), ["o"])
        XCTAssertEqual(try ids(["view": "open", "status": "done"]), ["d"])
    }
}
