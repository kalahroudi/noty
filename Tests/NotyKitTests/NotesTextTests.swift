import XCTest
@testable import NotyKit

final class NotesTextTests: XCTestCase {
    func testMarkdownPasteStaysMarkdown() {
        let md = "## Summary\n\n- fixed the **bug**\n- added `tests`"
        XCTAssertEqual(NotesText.pasteMarkdown(plain: md, html: "<p>## Summary</p>"), md)
    }

    func testHTMLPasteBecomesMarkdown() {
        // Claude desktop / browser selection: rendered plain text plus HTML with the structure.
        let plain = "Summary\n\nfixed the bug\nadded tests"
        let html = "<h2>Summary</h2><ul><li>fixed the <strong>bug</strong></li><li>added <code>tests</code></li></ul><pre><code>let x = 1\n  y</code></pre>"
        let out = NotesText.pasteMarkdown(plain: plain, html: html)
        XCTAssertTrue(out.contains("## Summary"), out)
        XCTAssertTrue(out.contains("- fixed the **bug**"), out)
        XCTAssertTrue(out.contains("```\nlet x = 1\n  y\n```"), out)
    }

    func testRawHTMLSourceIsConverted() {
        let out = NotesText.pasteMarkdown(plain: "<div><h1>Title</h1><p>Hello <b>world</b></p></div>", html: nil)
        XCTAssertEqual(out, "# Title\n\nHello **world**")
        XCTAssertFalse(NotesText.looksLikeHTMLSource("<u>under</u> and more"))
        XCTAssertFalse(NotesText.looksLikeHTMLSource("<span style=\"color:#D64545\">red</span>"))
        XCTAssertFalse(NotesText.looksLikeHTMLSource("a < b"))
    }

    func testCodeEditorHTMLKeepsPlainText() {
        let plain = "func a() {\n    return 1\n}"
        let html = "<div style=\"font-family: Menlo, monospace; white-space: pre;\"><div><span>func a() {</span></div></div>"
        XCTAssertEqual(NotesText.pasteMarkdown(plain: plain, html: html), "```\n" + plain + "\n```")
    }

    func testANSIOutputIsStrippedAndFenced() {
        let raw = "\u{1B}[1m\u{1B}[32m✓\u{1B}[0m 12 passed\r\n\u{1B}]8;;https://x.y\u{07}link\u{1B}]8;;\u{07} done\nloading 10%\rloading 100%"
        XCTAssertEqual(NotesText.pasteMarkdown(plain: raw, html: nil), "```\n✓ 12 passed\nlink done\nloading 100%\n```")
        XCTAssertEqual(NotesText.stripANSI("\u{1B}[31mred\u{1B}[0m"), "red")
    }

    func testTerminalAndStructureDetection() {
        let claude = "⏺ Bash(git status)\n  ⎿  On branch main\n     nothing to commit"
        XCTAssertTrue(NotesText.isStructured(claude))
        XCTAssertTrue(NotesText.looksLikeTerminal("┌───┬───┐\n│ a │ b │\n└───┴───┘"))
        XCTAssertFalse(NotesText.isStructured("just **bold** and <span style=\"color:#D64545\">red</span>"))
        XCTAssertTrue(NotesText.isStructured("# Heading"))
        XCTAssertTrue(NotesText.isStructured("text\n\n- item"))
        XCTAssertTrue(NotesText.isTableSeparator("|:---|---:|"))
        XCTAssertTrue(NotesText.isTableSeparator("--- | ---"))
        XCTAssertFalse(NotesText.isTableSeparator("-"))
    }

    func testCodeMask() {
        func code(_ s: String) -> String {
            let m = NotesText.codeMask(s); var o = ""
            for (k, c) in s.unicodeScalars.enumerated() where m[k] { o.unicodeScalars.append(c) }
            return o
        }
        XCTAssertEqual(code("a `b*c` d"), "`b*c`")
        XCTAssertEqual(code("x ``a ` b`` y"), "``a ` b``")
        XCTAssertEqual(code("no `close"), "")
        XCTAssertEqual(code("t\n```py\n*x*\n```\nafter"), "```py\n*x*\n```\n")
        XCTAssertEqual(code("~~~\nunclosed *"), "~~~\nunclosed *")
        XCTAssertEqual(code("~~strike~~"), "")
    }
}
