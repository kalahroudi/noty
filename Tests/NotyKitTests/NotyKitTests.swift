import XCTest
import AppKit
import PDFKit
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

    func testAttachmentsRoundTripAndTravelWithTheItem() throws {
        let root = tmp(); defer { try? FileManager.default.removeItem(at: root) }
        let s = NotyStore(root: root); try s.prepare()
        var it = Item(title: "shot", path: ["Work"])
        it.attachments = [try s.saveAttachment(Data([1, 2, 3]), itemID: it.id, index: 1)]
        let saved = try s.save(it)
        XCTAssertEqual(s.load().items.first?.attachments, saved.attachments)
        XCTAssertEqual(try Data(contentsOf: s.attachmentURL(saved.attachments[0])), Data([1, 2, 3]))
        XCTAssertEqual(s.attachmentURL("../../etc/passwd").deletingLastPathComponent().lastPathComponent, "_attachments")   // never escapes
        try s.delete(saved)
        XCTAssertFalse(FileManager.default.fileExists(atPath: s.attachmentURL(saved.attachments[0]).path))
    }

    func testDeeplinksAndReferences() throws {
        let it = Item(id: "ABC-123", title: "T", quote: "q", sourceApp: "Notes", attachments: ["a.png"], path: ["Projects", "MLX Player"])
        XCTAssertEqual(it.deepLink, "noty://item/ABC-123")
        XCTAssertEqual(Deeplink.parse(URL(string: it.deepLink)!), .item("ABC-123"))
        XCTAssertEqual(Deeplink.itemID(from: "noty://item/ABC-123"), "ABC-123")
        let cat = Deeplink.url(category: ["Projects", "MLX Player"])
        XCTAssertEqual(Deeplink.parse(URL(string: cat)!), .category(["Projects", "MLX Player"]))
        let ref = it.agentReference()
        XCTAssertTrue(ref.contains("noty://item/ABC-123")); XCTAssertTrue(ref.contains("get_item")); XCTAssertTrue(ref.contains("> q")); XCTAssertTrue(ref.contains("a.png"))
        XCTAssertTrue(ListReference.text(title: "P", link: nil, items: [it]).contains("id ABC-123"))
    }

    /// Notes and other apps put pictures inside RTFD (flat or classic) rather than as image data.
    func testClipboardImagesFromRichTextAndImageData() throws {
        let img = NSImage(size: NSSize(width: 40, height: 30)); img.lockFocus(); NSColor.red.setFill(); NSRect(x: 0, y: 0, width: 40, height: 30).fill(); img.unlockFocus()
        let png = NSBitmapImageRep(data: img.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        let wrapper = FileWrapper(regularFileWithContents: png); wrapper.preferredFilename = "pic.png"
        let body = NSMutableAttributedString(string: "Error when a user loads a model\n"); body.append(NSAttributedString(attachment: NSTextAttachment(fileWrapper: wrapper)))
        let rtfd = try XCTUnwrap(body.rtfd(from: NSRange(location: 0, length: body.length)))
        for type in [NSPasteboard.PasteboardType("com.apple.flat-rtfd"), .rtfd] {
            let pb = NSPasteboard(name: NSPasteboard.Name("noty-test-\(UUID().uuidString)"))
            pb.clearContents(); pb.setString(body.string, forType: .string); pb.setData(rtfd, forType: type)
            let r = ClipboardContent.extract(from: pb)
            XCTAssertEqual(r.images.count, 1, "\(type.rawValue)"); XCTAssertEqual(r.text, "Error when a user loads a model")
        }
        let pb = NSPasteboard(name: NSPasteboard.Name("noty-test-\(UUID().uuidString)")); pb.clearContents(); pb.setData(png, forType: .png)
        XCTAssertEqual(ClipboardContent.extract(from: pb).images.count, 1)
        let html = "<p>x</p><img src=\"data:image/png;base64,\(png.base64EncodedString())\">"
        XCTAssertEqual(ClipboardContent.dataImages(in: html).count, 1)
    }

    // MARK: rich content

    func testHTMLToMarkdownKeepsStructure() {
        let html = """
        <html><head><style>p{color:red}</style><!--[if gte mso 9]><xml>junk</xml><![endif]--></head><body>
        <h1>Release &amp; notes</h1><p>Some <b>bold</b>, <i>italic</i> and a <a href="https://x.test/a b">link</a>.<br>Next line</p>
        <ul><li>one</li><li>two<ul><li>nested</li></ul></li></ul><ol><li>first</li><li>second</li></ol>
        <blockquote><p>quoted</p></blockquote><pre><code>let a = 1\nlet b = 2</code></pre>
        <table><tr><th>Name</th><th>Size</th></tr><tr><td>base</td><td>74 MB</td></tr></table></body></html>
        """
        let md = HTMLMarkdown.convert(html)
        XCTAssertTrue(md.hasPrefix("# Release & notes"), md)
        XCTAssertTrue(md.contains("**bold**") && md.contains("*italic*") && md.contains("[link](https://x.test/a%20b)"), md)
        XCTAssertTrue(md.contains("- one\n- two\n  - nested"), md)
        XCTAssertTrue(md.contains("1. first\n2. second"), md)
        XCTAssertTrue(md.contains("> quoted"), md)
        XCTAssertTrue(md.contains("```\nlet a = 1\nlet b = 2\n```"), md)
        XCTAssertTrue(md.contains("| Name | Size |\n| --- | --- |\n| base | 74 MB |"), md)
        XCTAssertFalse(md.contains("junk") || md.contains("color:red"), md)
    }

    func testRichTextToMarkdown() throws {
        let body = NSFont.systemFont(ofSize: 12)
        let s = NSMutableAttributedString()
        s.append(NSAttributedString(string: "Big title\n", attributes: [.font: NSFont.boldSystemFont(ofSize: 24)]))
        s.append(NSAttributedString(string: "Plain and ", attributes: [.font: body]))
        s.append(NSAttributedString(string: "bold", attributes: [.font: NSFont.boldSystemFont(ofSize: 12)]))
        s.append(NSAttributedString(string: " and ", attributes: [.font: body]))
        s.append(NSAttributedString(string: "site", attributes: [.font: body, .link: URL(string: "https://x.test")!]))
        s.append(NSAttributedString(string: ".\nMore body text here to make 12pt the common size.\n", attributes: [.font: body]))
        let rtf = try XCTUnwrap(s.rtf(from: NSRange(location: 0, length: s.length)))
        let back = try XCTUnwrap(NSAttributedString(rtf: rtf, documentAttributes: nil))
        let md = RichText.markdown(from: back).markdown
        XCTAssertTrue(md.hasPrefix("# Big title"), md)
        XCTAssertTrue(md.contains("Plain and **bold** and [site](https://x.test)."), md)
    }

    func testClipboardHTMLKeepsOriginalAndMarkdown() {
        let pb = NSPasteboard(name: NSPasteboard.Name("noty-test-\(UUID().uuidString)")); pb.clearContents()
        pb.setString("Title\nitem one", forType: .string)
        pb.setString("<h2>Title</h2><ul><li>item one</li></ul>", forType: .html)
        let r = ClipboardContent.extract(from: pb)
        XCTAssertTrue(r.markdown.contains("## Title") && r.markdown.contains("- item one"), r.markdown)
        XCTAssertEqual(r.attachments.map(\.ext), ["html"]); XCTAssertEqual(r.text, "Title\nitem one")
        // plain text wrapped in trivial HTML adds nothing, so no markdown or html copy is kept
        let pb2 = NSPasteboard(name: NSPasteboard.Name("noty-test-\(UUID().uuidString)")); pb2.clearContents()
        pb2.setString("just words", forType: .string); pb2.setString("<p>just words</p>", forType: .html)
        let r2 = ClipboardContent.extract(from: pb2)
        XCTAssertTrue(r2.markdown.isEmpty); XCTAssertTrue(r2.attachments.isEmpty)
    }

    func testClipboardPDFAndCopiedFiles() throws {
        let img = NSImage(size: NSSize(width: 200, height: 100)); img.lockFocus(); NSColor.blue.setFill(); NSRect(x: 0, y: 0, width: 200, height: 100).fill(); img.unlockFocus()
        let doc = PDFDocument(); doc.insert(try XCTUnwrap(PDFPage(image: img)), at: 0)
        let pdf = try XCTUnwrap(doc.dataRepresentation())
        let pb = NSPasteboard(name: NSPasteboard.Name("noty-test-\(UUID().uuidString)")); pb.clearContents(); pb.setData(pdf, forType: NSPasteboard.PasteboardType("com.adobe.pdf"))
        XCTAssertEqual(Set(ClipboardContent.extract(from: pb).attachments.map(\.ext)), ["pdf", "png"])

        let dir = tmp(); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("spec.rtf")
        let s = NSMutableAttributedString(string: "Spec title\n", attributes: [.font: NSFont.boldSystemFont(ofSize: 24)])
        s.append(NSAttributedString(string: "Body text of the document goes here.\nMore body text.\n", attributes: [.font: NSFont.systemFont(ofSize: 12)]))
        try XCTUnwrap(s.rtf(from: NSRange(location: 0, length: s.length))).write(to: file)
        let pb2 = NSPasteboard(name: NSPasteboard.Name("noty-test-\(UUID().uuidString)")); pb2.clearContents(); pb2.writeObjects([file as NSURL])
        let r = ClipboardContent.extract(from: pb2)
        XCTAssertTrue(r.attachments.contains { $0.ext == "rtf" }); XCTAssertTrue(r.markdown.hasPrefix("# Spec title"), r.markdown)
        XCTAssertTrue(r.text.contains("Body text of the document"))
    }

    func testMarkdownStrippingAndQuoteResolution() {
        XCTAssertEqual(MarkdownText.stripped("# Title\n**bold** [a](http://x) ![i](attachment:1)\n- item"), "Title\nbold a [image]\nitem")
        var it = Item(title: "t", quote: "see ![image](attachment:1)", attachments: ["abc-1.png", "abc-2.html"])
        let store = NotyStore(root: URL(fileURLWithPath: "/tmp/lib"))
        XCTAssertEqual(it.resolvedQuote(store: store), "see ![image](/tmp/lib/_attachments/abc-1.png)")
        XCTAssertEqual(it.previewText, "see [image]"); it.quote = ""; XCTAssertEqual(it.previewText, "")
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

    func testSubcategoriesAndRename() throws {
        let root = tmp(); defer { try? FileManager.default.removeItem(at: root) }
        let s = NotyStore(root: root); try s.prepare()
        try s.createCategory(["Projects", "acme", "Design"])
        try s.save(Item(title: "logo", path: ["Projects", "acme", "Design"]))
        XCTAssertTrue(s.load().categories.map(\.id).contains("Projects/acme/Design"))
        try s.renameCategory(["Projects", "acme"], to: "Acme Corp")
        let lib = s.load()
        XCTAssertEqual(lib.items.first?.path, ["Projects", "Acme Corp", "Design"])
        XCTAssertThrowsError(try s.renameCategory(["Projects", "Acme Corp"], to: "Acme Corp"))   // name already taken
        try s.createCategory(["Projects", "other"])
        XCTAssertThrowsError(try s.renameCategory(["Projects", "other"], to: "Acme Corp"))
        XCTAssertThrowsError(try s.renameCategory(["Inbox"], to: "x"))
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
