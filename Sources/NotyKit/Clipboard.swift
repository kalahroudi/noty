// SPDX-License-Identifier: Apache-2.0

import AppKit
import PDFKit
import UniformTypeIdentifiers

/// A file kept with an item: a picture (png), the original formatting (html), a PDF, or any file that was copied.
public struct Attachment: Sendable, Equatable {
    public var ext: String
    public var data: Data
    public init(ext: String, data: Data) { self.ext = ext; self.data = data }
}

/// Reads what a copied selection really contains and keeps its structure: plain text, Markdown made from HTML / RTF / RTFD / Word / PDF,
/// every picture, the original HTML, and any files that were copied (Finder, Mail attachments).
public enum ClipboardContent {
    public struct Result: Sendable {
        public var text: String             // plain text
        public var markdown: String         // structured text (headings, lists, links, tables…); empty when the source had no formatting
        public var attachments: [Attachment]
        public var types: [String]          // pasteboard type names, for the log only (never content)
        public var images: [Data] { attachments.filter { $0.ext == "png" }.map(\.data) }
        public init(text: String, markdown: String, attachments: [Attachment], types: [String]) { self.text = text; self.markdown = markdown; self.attachments = attachments; self.types = types }
    }

    static let maxFile = 25_000_000
    static let maxAttachments = 8

    public static func extract(from pb: NSPasteboard) -> Result {
        var atts: [Attachment] = []
        func hasData(_ d: Data) -> Bool { atts.contains { $0.data == d } }
        func addPNG(_ data: Data?) {
            guard let data, data.count > 100, data.count < maxFile, atts.count < maxAttachments, let rep = NSBitmapImageRep(data: data),
                  let out = rep.representation(using: .png, properties: [:]), !hasData(out) else { return }
            atts.append(Attachment(ext: "png", data: out))
        }

        var typeNames: [String] = []
        var html: String?
        var richText: NSAttributedString?
        var pdfData: Data?
        var fileURLs: [URL] = []
        var direct: [Data] = []
        for item in pb.pasteboardItems ?? [] {
            for t in item.types {
                let raw = t.rawValue; typeNames.append(raw)
                guard let data = item.data(forType: t) else { continue }
                if raw == "com.apple.flat-rtfd" || raw == "NeXT RTFD pasteboard type" || raw.contains("rtfd") {
                    if richText == nil { richText = NSAttributedString(rtfd: data, documentAttributes: nil) }
                } else if t == .rtf || raw == "public.rtf" || raw == "NeXT Rich Text Format v1.0 pasteboard type" {
                    if richText == nil { richText = NSAttributedString(rtf: data, documentAttributes: nil) }
                } else if t == .html || raw == "public.html" || raw == "Apple HTML pasteboard type" {
                    if html == nil { html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) ?? String(data: data, encoding: .isoLatin1) }
                } else if raw == "com.adobe.pdf" || (UTType(raw)?.conforms(to: .pdf) ?? false) {
                    pdfData = data
                } else if t == .fileURL {
                    if let s = String(data: data, encoding: .utf8), let u = URL(string: s), u.isFileURL { fileURLs.append(u) }
                } else if let ut = UTType(raw), ut.conforms(to: .image) { direct.append(data) }
            }
        }
        // The pasteboard object can expose flavours that no single item lists.
        if richText == nil { for t in [NSPasteboard.PasteboardType("com.apple.flat-rtfd"), .rtfd] { if let d = pb.data(forType: t) { richText = NSAttributedString(rtfd: d, documentAttributes: nil); break } } }
        if richText == nil, let d = pb.data(forType: .rtf) { richText = NSAttributedString(rtf: d, documentAttributes: nil) }
        if html == nil, let d = pb.data(forType: .html) { html = String(data: d, encoding: .utf8) }

        var plain = (pb.string(forType: .string) ?? "").replacingOccurrences(of: "\u{FFFC}", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        var markdown = ""

        // Structure: rich text with embedded pictures wins (placeholders line up with the images); then HTML; then RTF without pictures.
        var rich: RichText.Output?
        if let rt = richText { rich = RichText.markdown(from: rt) }
        if let r = rich, !r.images.isEmpty {
            for d in r.images { if atts.count < maxAttachments { atts.append(Attachment(ext: "png", data: d)) } }
            markdown = r.markdown
        } else if let h = html {
            for d in dataImages(in: h) { addPNG(d) }
            let md = HTMLMarkdown.convert(h)
            if hasStructure(md, comparedTo: plain) {
                markdown = md
                if h.utf8.count < 3_000_000 { atts.append(Attachment(ext: "html", data: Data(h.utf8))) }   // original formatting, to paste back out
            }
        }
        if markdown.isEmpty, let r = rich, hasStructure(r.markdown, comparedTo: plain) { markdown = r.markdown }

        for d in direct { addPNG(d) }
        if let d = pdfData { addPDF(d, into: &atts, text: &plain) }
        for url in fileURLs.prefix(maxAttachments) { addFile(url, into: &atts, text: &plain, markdown: &markdown) }
        if plain.isEmpty, !markdown.isEmpty { plain = markdown }
        return Result(text: plain, markdown: markdown, attachments: atts, types: typeNames)
    }

    /// True when Markdown carries more than the plain text does (otherwise keeping it only adds noise).
    static func hasStructure(_ md: String, comparedTo plain: String) -> Bool {
        let m = md.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !m.isEmpty else { return false }
        let squash: (String) -> String = { $0.filter { !$0.isWhitespace } }
        return squash(m) != squash(plain)
    }

    private static func addPDF(_ data: Data, into atts: inout [Attachment], text: inout String) {
        guard data.count < maxFile, atts.count < maxAttachments - 1 else { return }
        atts.append(Attachment(ext: "pdf", data: data))
        guard let doc = PDFDocument(data: data) else { return }
        if text.isEmpty, let s = doc.string?.trimmingCharacters(in: .whitespacesAndNewlines) { text = String(s.prefix(20_000)) }
        if let page = doc.page(at: 0), let tiff = page.thumbnail(of: CGSize(width: 900, height: 1200), for: .mediaBox).tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) { atts.append(Attachment(ext: "png", data: png)) }
    }

    private static func addFile(_ url: URL, into atts: inout [Attachment], text: inout String, markdown: inout String) {
        guard atts.count < maxAttachments, let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < maxFile, let data = try? Data(contentsOf: url) else { return }
        let ext = url.pathExtension.lowercased()
        guard let ut = UTType(filenameExtension: ext) else { atts.append(Attachment(ext: ext.isEmpty ? "bin" : ext, data: data)); return }
        if ut.conforms(to: .image) {
            if let png = NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]) { atts.append(Attachment(ext: "png", data: png)) }
        } else if ut.conforms(to: .pdf) {
            addPDF(data, into: &atts, text: &text)
        } else if ["docx", "doc", "rtf", "rtfd", "odt", "html", "htm", "webarchive"].contains(ext) {
            atts.append(Attachment(ext: ext, data: data))
            if let s = try? NSAttributedString(url: url, options: [:], documentAttributes: nil) {
                let r = RichText.markdown(from: s)
                if markdown.isEmpty { markdown = r.markdown }
                if text.isEmpty || text == url.lastPathComponent { text = s.string.replacingOccurrences(of: "\u{FFFC}", with: "").trimmingCharacters(in: .whitespacesAndNewlines) }
                for d in r.images where atts.count < maxAttachments { atts.append(Attachment(ext: "png", data: d)) }
            }
        } else if ut.conforms(to: .plainText) || ext == "md" {
            if let s = String(data: data, encoding: .utf8) { if text.isEmpty || text == url.lastPathComponent { text = s }; if ext == "md", markdown.isEmpty { markdown = s } }
            atts.append(Attachment(ext: ext, data: data))
        } else { atts.append(Attachment(ext: ext, data: data)) }
    }

    /// Writes an item's formatted text back to a pasteboard: the original HTML when we kept it, otherwise rich text built from the Markdown.
    public static func writeFormatted(markdown: String, html: Data?, plain: String, to pb: NSPasteboard) {
        pb.clearContents()
        if let html, let h = String(data: html, encoding: .utf8) {
            pb.setString(h, forType: .html); pb.setString(plain, forType: .string); return
        }
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let a = try? AttributedString(markdown: markdown, options: opts) { pb.writeObjects([NSAttributedString(a)]) } else { pb.setString(plain, forType: .string) }
    }

    /// `<img src="data:image/png;base64,...">` pictures (what browsers and many editors put in HTML).
    static func dataImages(in html: String) -> [Data] {
        guard let re = try? NSRegularExpression(pattern: #"src\s*=\s*["']data:image/[a-zA-Z+]+;base64,([A-Za-z0-9+/=\s]+)["']"#) else { return [] }
        let ns = html as NSString
        return re.matches(in: html, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            Data(base64Encoded: ns.substring(with: m.range(at: 1)), options: .ignoreUnknownCharacters)
        }
    }
}
