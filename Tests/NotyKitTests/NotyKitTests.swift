import XCTest
@testable import NotyKit

final class KitTests: XCTestCase {
    func testVersionOrdering() {
        XCTAssertTrue(Version.isNewer("0.2.0", than: "0.1.9"))
        XCTAssertTrue(Version.isNewer("v1.0.0", than: "1.0.0-beta.2"))
        XCTAssertFalse(Version.isNewer("1.0.0", than: "1.0.0"))
        XCTAssertFalse(Version.isNewer("garbage", than: "1.0.0"))
    }

    func testChecksumLookup() {
        let sums = "abc123  Noty-0.1.0.dmg\ndef456 *other.dmg\n"
        XCTAssertEqual(UpdateChecker.checksum(in: sums, for: "Noty-0.1.0.dmg"), "abc123")
        XCTAssertEqual(UpdateChecker.checksum(in: sums, for: "other.dmg"), "def456")
        XCTAssertNil(UpdateChecker.checksum(in: sums, for: "missing.dmg"))
    }

    func testCompareDecision() throws {
        let ahead = Data(#"{"status":"ahead","ahead_by":1,"commits":[{"commit":{"message":"Fix a thing\n\nbody"}}]}"#.utf8)
        guard case .available(let info) = try UpdateChecker.decide(compareJSON: ahead, head: "deadbeef") else { return XCTFail("expected available") }
        XCTAssertEqual(info.summaries, ["Fix a thing"])
        XCTAssertEqual(try UpdateChecker.decide(compareJSON: Data(#"{"status":"identical"}"#.utf8), head: "x"), .upToDate)
    }

    func testSwapScriptRollsBack() {
        XCTAssertTrue(UpdateSwap.script.contains("restored"))
    }

    func testAgentConfigRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("agent-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"other":1,"mcpServers":{"keep":{"command":"x"}}}"#.utf8).write(to: url)
        try AgentIntegrations.jsonInstall(at: url, command: "/Applications/Noty.app/Contents/MacOS/noty-mcp")
        XCTAssertEqual(AgentIntegrations.jsonCommand(at: url), "/Applications/Noty.app/Contents/MacOS/noty-mcp")
        try AgentIntegrations.jsonRemove(at: url)
        XCTAssertNil(AgentIntegrations.jsonCommand(at: url))
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        XCTAssertNotNil((root?["mcpServers"] as? [String: Any])?["keep"], "other servers must survive")
        XCTAssertEqual(root?["other"] as? Int, 1)
    }

    func testSetupStateWithNothingMissingIsReady() {
        XCTAssertTrue(SetupState(items: []).ready)
    }

    // MARK: library

    private func tmp() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("noty-\(UUID().uuidString)", isDirectory: true) }

    func testItemFileRoundTrip() {
        let item = Item(title: "Say \"hi\": a/b", kind: .idea, done: true, today: true, tags: ["a", "b c"], quote: "line one\n\nline three",
                        notes: "my note\nsecond", sourceApp: "Safari", sourceTitle: "T", sourceURL: "https://x.test/a?b=1", path: ["Work"])
        let back = ItemFile.decode(ItemFile.encode(item))
        XCTAssertEqual(back?.title, item.title); XCTAssertEqual(back?.kind, .idea); XCTAssertEqual(back?.done, true)
        XCTAssertEqual(back?.tags, ["a", "b c"]); XCTAssertEqual(back?.quote, item.quote); XCTAssertEqual(back?.notes, item.notes)
        XCTAssertEqual(back?.sourceURL, item.sourceURL); XCTAssertEqual(back?.id, item.id)
    }

    func testDecodeRejectsFilesWithoutHeader() {
        XCTAssertNil(ItemFile.decode("# just a note\n"))
        XCTAssertNil(ItemFile.decode("---\ntitle: \"x\"\n---\n"))
    }

    func testStoreSaveMoveLoadAndTree() throws {
        let root = tmp(); defer { try? FileManager.default.removeItem(at: root) }
        let s = NotyStore(root: root); try s.prepare()
        XCTAssertEqual(s.load().categories.map(\.id), ["Inbox", "Personal", "Work"])
        var it = try s.save(Item(title: "Read the RFC", quote: "q"))
        XCTAssertEqual(it.path, ["Inbox"])
        it.path = ["Work", "Q4 Launch", "Research"]
        it = try s.save(it)
        let lib = s.load()
        XCTAssertEqual(lib.items.count, 1)                                  // moved, not copied
        XCTAssertEqual(lib.items[0].path, ["Work", "Q4 Launch", "Research"])
        XCTAssertTrue(lib.categories.contains(CategoryNode(path: ["Work", "Q4 Launch"])))
        XCTAssertThrowsError(try s.deleteCategory(["Work", "Q4 Launch"]))   // not empty
        try s.delete(it)
        XCTAssertTrue(s.load().items.isEmpty)
    }

    func testDuplicateIdsFromSyncConflictAreArchived() throws {
        let root = tmp(); defer { try? FileManager.default.removeItem(at: root) }
        let s = NotyStore(root: root); try s.prepare()
        let a = try s.save(Item(title: "same", path: ["Work"]))
        let copy = root.appendingPathComponent("Work/same (conflict).md")
        try FileManager.default.copyItem(at: a.file!, to: copy)
        let lib = s.load()
        XCTAssertEqual(lib.items.count, 1); XCTAssertEqual(lib.conflicts, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("_history").path))
    }

    func testLocationFileIsSharedWithMCP() throws {
        let paths = AppPaths(root: tmp()); defer { try? FileManager.default.removeItem(at: paths.root) }
        XCTAssertEqual(NotyStore.resolveRoot(paths: paths), paths.defaultLibrary)
        let custom = URL(fileURLWithPath: "/tmp/somewhere", isDirectory: true)
        try NotyStore.saveRoot(custom, paths: paths)
        XCTAssertEqual(NotyStore.resolveRoot(paths: paths).path, custom.path)
    }

    func testProposalApprovalIsConfinedAndFinishesItems() throws {
        let root = tmp(); defer { try? FileManager.default.removeItem(at: root) }
        let s = NotyStore(root: root); try s.prepare()
        let it = try s.save(Item(title: "x", path: ["Work"]))
        XCTAssertThrowsError(try s.addProposal(Proposal(name: "../evil.md", content: "")))
        XCTAssertThrowsError(try s.addProposal(Proposal(name: "/etc/passwd", content: "")))
        let p = Proposal(name: "skills/x/SKILL.md", content: "# x", itemIds: [it.id], completeItems: true)
        try s.addProposal(p)
        XCTAssertEqual(s.proposals().count, 1)
        let url = try s.approve(p)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "# x")
        XCTAssertTrue(url.path.hasPrefix(s.filesDir.path))
        XCTAssertEqual(s.load().items.first?.done, true)
        XCTAssertTrue(s.proposals().isEmpty)
        let again = try s.approve(p)                                         // never overwrites
        XCTAssertNotEqual(again, url)
    }

    func testPathParsingAndTitles() {
        XCTAssertEqual(NotyStore.parsePath("Work › Q4 / Build"), ["Work", "Q4", "Build"])
        let c = NotyStore.cleanName("../.hidden"); XCTAssertFalse(c.contains("/")); XCTAssertFalse(c.hasPrefix(".")); XCTAssertEqual(NotyStore.cleanName(".hidden"), "hidden")
        XCTAssertEqual(Item.makeTitle(from: "\n  First line here\nsecond"), "First line here")
        XCTAssertTrue(Item.makeTitle(from: String(repeating: "word ", count: 40)).hasSuffix("…"))
    }

    func testAgentPromptMentionsToolsAndItems() {
        let p = AgentPrompt.build(.skill, items: [Item(id: "abc", title: "T", path: ["Work"])])
        XCTAssertTrue(p.contains("abc")); XCTAssertTrue(p.contains("propose_file")); XCTAssertTrue(p.contains("Never delete"))
    }
}
