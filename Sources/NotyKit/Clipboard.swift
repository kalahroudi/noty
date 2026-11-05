// SPDX-License-Identifier: Apache-2.0

import AppKit
import UniformTypeIdentifiers

/// Reads what a copied selection really contains: plain text, and every picture in any of the formats apps use
/// (image data, RTFD with embedded pictures in either flavour, image file URLs, inline data: images in HTML).
public enum ClipboardContent {
    public struct Result: Sendable {
        public var text: String
        public var images: [Data]      // PNG
        public var types: [String]     // pasteboard type names, for the log only (never content)
    }

    public static func extract(from pb: NSPasteboard) -> Result {
        var png: [Data] = []
        func add(_ data: Data?) {
            guard let data, data.count > 100, data.count < 25_000_000, png.count < 6, let rep = NSBitmapImageRep(data: data),
                  let out = rep.representation(using: .png, properties: [:]), !png.contains(out) else { return }
            png.append(out)
        }
        func addFromRichText(_ data: Data) {
            guard let str = NSAttributedString(rtfd: data, documentAttributes: nil) ?? (try? NSAttributedString(data: data, options: [:], documentAttributes: nil)) else { return }
            str.enumerateAttribute(.attachment, in: NSRange(location: 0, length: str.length)) { v, _, _ in
                guard let att = v as? NSTextAttachment else { return }
                if let d = att.fileWrapper?.regularFileContents { add(d) }
                else if let img = att.image { add(img.tiffRepresentation) }
            }
        }
        var typeNames: [String] = []
        for item in pb.pasteboardItems ?? [] {
            for t in item.types {
                typeNames.append(t.rawValue)
                let raw = t.rawValue
                if let ut = UTType(raw), ut.conforms(to: .image), !ut.conforms(to: .pdf) { add(item.data(forType: t)); continue }
                if raw == "com.apple.flat-rtfd" || raw == "NeXT RTFD pasteboard type" || raw.contains("rtfd") { if let d = item.data(forType: t) { addFromRichText(d) }; continue }
                if t == .fileURL, let s = item.string(forType: t), let url = URL(string: s), url.isFileURL,
                   let ut = UTType(filenameExtension: url.pathExtension), ut.conforms(to: .image) { add(try? Data(contentsOf: url)); continue }
                if t == .html, let d = item.data(forType: t), let html = String(data: d, encoding: .utf8) { for img in dataImages(in: html) { add(img) } }
            }
        }
        // Some apps only publish the rich flavour on the pasteboard object, not per item.
        if png.isEmpty { for t in [NSPasteboard.PasteboardType("com.apple.flat-rtfd"), .rtfd] { if let d = pb.data(forType: t) { addFromRichText(d) } } }
        let text = (pb.string(forType: .string) ?? "").replacingOccurrences(of: "\u{FFFC}", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        return Result(text: text, images: png, types: typeNames)
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
