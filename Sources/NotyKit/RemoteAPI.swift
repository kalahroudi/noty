// SPDX-License-Identifier: Apache-2.0

import Foundation
import AppKit
import ImageIO

public struct HTTPRequest: Sendable {
    public var method: String
    public var path: String
    public var query: [String: String]
    public var headers: [String: String]      // lower-cased names
    public var body: Data
    public init(method: String, path: String, query: [String: String] = [:], headers: [String: String] = [:], body: Data = Data()) {
        self.method = method; self.path = path; self.query = query; self.headers = headers; self.body = body
    }
}

public struct HTTPResponse: Sendable {
    public var status: Int
    public var contentType: String
    public var body: Data
    public var headers: [String: String]
    public init(status: Int = 200, contentType: String = "application/json; charset=utf-8", body: Data = Data(), headers: [String: String] = [:]) { self.status = status; self.contentType = contentType; self.body = body; self.headers = headers }

    public static func json(_ v: Any, status: Int = 200) -> HTTPResponse {
        HTTPResponse(status: status, body: (try? JSONSerialization.data(withJSONObject: v, options: [.withoutEscapingSlashes])) ?? Data("{}".utf8))
    }
    public static func error(_ status: Int, _ message: String) -> HTTPResponse { .json(["error": message], status: status) }

    public func serialized() -> Data {
        let reason = [200: "OK", 400: "Bad Request", 403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed", 413: "Payload Too Large", 415: "Unsupported Media Type", 500: "Internal Server Error"][status] ?? "OK"
        var head = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\n"
        head += "X-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\nConnection: close\r\n"
        for (k, v) in headers { head += "\(k): \(v)\r\n" }
        head += "\r\n"
        return Data(head.utf8) + body
    }
}

public enum HTTPParser {
    public enum Result { case needMore, bad, tooLarge, request(HTTPRequest) }
    /// Large enough for a phone photo or a PDF; endpoints that are not uploads refuse more than `maxJSON`.
    public static let maxBody = 40_000_000

    public static func parse(_ data: Data) -> Result {
        let sep = Data("\r\n\r\n".utf8)
        guard let r = data.range(of: sep) else { return data.count > 16_384 ? .tooLarge : .needMore }
        let lines = String(decoding: data[..<r.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
        let first = lines[0].split(separator: " ")
        guard first.count == 3 else { return .bad }
        var headers: [String: String] = [:]
        for l in lines.dropFirst() { if let c = l.firstIndex(of: ":") { headers[l[..<c].lowercased()] = l[l.index(after: c)...].trimmingCharacters(in: .whitespaces) } }
        let length = Int(headers["content-length"] ?? "0") ?? -1
        guard length >= 0 else { return .bad }
        guard length <= maxBody else { return .tooLarge }
        let body = data[r.upperBound...]
        if body.count < length { return .needMore }
        let target = String(first[1])
        let parts = target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        var q: [String: String] = [:]
        if parts.count == 2 {
            for pair in parts[1].split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                let dec = { (s: Substring) in String(s).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? String(s) }
                q[dec(kv[0])] = kv.count == 2 ? dec(kv[1]) : ""
            }
        }
        return .request(HTTPRequest(method: String(first[0]).uppercased(), path: parts[0].removingPercentEncoding ?? String(parts[0]), query: q, headers: headers, body: Data(body.prefix(length))))
    }
}

/// The JSON API behind the remote web app. Pure: a request in, a response out, so it is unit tested without a socket.
/// Safety: reachable only through Tailscale Serve (which adds the signed-in user's identity) or from this Mac, never from another website.
public struct RemoteAPI: Sendable {
    public static let maxJSON = 1_000_000
    public let store: NotyStore
    public var page: String
    public init(store: NotyStore, page: String = "") { self.store = store; self.page = page }

    /// Host must be this Mac or a tailnet name; tailnet traffic must carry the identity header Tailscale Serve adds;
    /// browsers' cross-site requests are refused by checking Origin against Host and requiring a custom header on writes.
    public func authorize(_ req: HTTPRequest) -> HTTPResponse? {
        let host = (req.headers["host"] ?? "").split(separator: ":").first.map(String.init)?.lowercased() ?? ""
        let local = host == "127.0.0.1" || host == "localhost"
        guard local || host.hasSuffix(".ts.net") else { return .error(403, "Unknown host.") }
        if !local && (req.headers["tailscale-user-login"] ?? "").isEmpty { return .error(403, "Open this through Tailscale.") }
        if let origin = req.headers["origin"], URL(string: origin)?.host?.lowercased() != host { return .error(403, "Cross-site request refused.") }
        if req.method != "GET" && req.headers["x-noty"] != "1" { return .error(403, "Missing X-Noty header.") }
        return nil
    }

    public func handle(_ req: HTTPRequest) -> HTTPResponse {
        if let denied = authorize(req) { return denied }
        let seg = req.path.split(separator: "/").map(String.init)
        do {
            let get = req.method == "GET", post = req.method == "POST"
            guard get || post else { return .error(405, "Method not allowed.") }
            let upload = post && seg.count == 4 && seg[3] == "attach"
            if !upload && req.body.count > Self.maxJSON { return .error(413, "Too large.") }
            if get && seg.isEmpty {
                return HTTPResponse(contentType: "text/html; charset=utf-8", body: Data(page.utf8),
                                    headers: ["Content-Security-Policy": "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'"])
            }
            if get && seg.count == 3 && seg[0] == "api" && seg[1] == "attachments" { return attachment(seg[2]) }
            if seg.count >= 2, seg[0] == "api", seg[1] == "items" {
                if seg.count == 2 { return get ? list(req) : try add(req) }
                if seg.count == 3 && get { return try detail(seg[2]) }
                if seg.count == 4 && post { return try update(seg[2], seg[3], req) }
            }
            return .error(404, "Not found.")
        } catch { return .error(500, error.localizedDescription) }
    }

    private func summary(_ it: Item) -> [String: Any] {
        var d: [String: Any] = ["id": it.id, "title": it.title, "kind": it.kind.rawValue, "done": it.done, "today": it.today, "path": it.path.joined(separator: " › ")]
        let files = it.attachments.filter { !$0.lowercased().hasSuffix(".html") }.count
        if files > 0 { d["attachments"] = files }
        if !it.reminders.filter({ !$0.done }).isEmpty { d["reminders"] = it.reminders.filter { !$0.done }.count }
        return d
    }

    private func list(_ req: HTTPRequest) -> HTTPResponse {
        let items = store.load().items
        let words = (req.query["q"] ?? "").lowercased().split(separator: " ").map(String.init)
        var hits: [Item]
        if !words.isEmpty {
            hits = items.filter { it in let hay = (it.title + " " + it.quote + " " + it.notes + " " + it.tags.joined(separator: " ") + " " + it.pathLabel).lowercased(); return words.allSatisfy(hay.contains) }
        } else {
            switch req.query["view"] ?? "open" {
            case "today": hits = items.filter { $0.today && !$0.done }
            case "inbox": hits = items.filter { $0.path.first == NotyStore.inbox && !$0.done }
            case "done": hits = items.filter { $0.done }
            default: hits = items.filter { !$0.done }
            }
        }
        hits.sort { $0.created > $1.created }
        return .json(["total": hits.count, "items": hits.prefix(200).map(summary)] as [String: Any])
    }

    private func detail(_ id: String) throws -> HTTPResponse {
        guard let it = store.item(id: id) else { return .error(404, "No such item.") }
        var d = summary(it)
        d["quote"] = it.quote; d["notes"] = it.notes; d["tags"] = it.tags
        d["images"] = it.imageAttachments
        d["files"] = it.otherAttachments.map { name -> [String: Any] in
            let size = (try? FileManager.default.attributesOfItem(atPath: store.attachmentURL(name).path)[.size] as? Int) ?? 0
            return ["name": name, "size": size ?? 0]
        }
        if let u = it.sourceURL { d["sourceURL"] = u }
        if let t = it.sourceTitle { d["sourceTitle"] = t }
        d["created"] = ISO8601DateFormatter().string(from: it.created)
        d["reminders"] = it.reminders.sorted { $0.due < $1.due }.map { ["text": $0.text, "due": ISO8601DateFormatter().string(from: $0.due), "done": $0.done] as [String: Any] }
        return .json(d)
    }

    private func body(_ req: HTTPRequest) -> [String: Any] { (try? JSONSerialization.jsonObject(with: req.body)) as? [String: Any] ?? [:] }

    private func add(_ req: HTTPRequest) throws -> HTTPResponse {
        let b = body(req)
        let title = (b["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return .error(400, "title is required.") }
        let saved = try store.save(Item(title: String(title.prefix(300)), today: b["today"] as? Bool ?? false, notes: String((b["notes"] as? String ?? "").prefix(100_000))))
        return .json(summary(saved), status: 200)
    }

    private func update(_ id: String, _ action: String, _ req: HTTPRequest) throws -> HTTPResponse {
        guard var it = store.item(id: id) else { return .error(404, "No such item.") }
        let b = body(req)
        switch action {
        case "attach": return try attach(it, req)
        case "detach":
            guard let name = b["name"] as? String, it.attachments.contains(name) else { return .error(404, "No such attachment.") }
            it.attachments.removeAll { $0 == name }
            let saved = try store.save(it)
            try? FileManager.default.trashItem(at: store.attachmentURL(name), resultingItemURL: nil)
            return .json(summary(saved))
        case "done": it.done = b["done"] as? Bool ?? !it.done
        case "today": it.today = b["today"] as? Bool ?? !it.today
        case "notes": it.notes = String((b["notes"] as? String ?? "").prefix(100_000))
        default: return .error(404, "Not found.")
        }
        return .json(summary(try store.save(it)))
    }

    // MARK: Attachments

    private static let imageTypes: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "gif", "tiff", "tif", "bmp", "webp"]
    private static let types = ["png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif", "webp": "image/webp", "pdf": "application/pdf",
                                "txt": "text/plain; charset=utf-8", "md": "text/plain; charset=utf-8", "csv": "text/plain; charset=utf-8", "json": "text/plain; charset=utf-8",
                                "mp4": "video/mp4", "mov": "video/quicktime", "mp3": "audio/mpeg", "m4a": "audio/mp4", "wav": "audio/wav"]

    /// Serves a file from the library's `_attachments` folder. Only types a browser can show safely are shown inline; the rest (including HTML and SVG) download.
    private func attachment(_ name: String) -> HTTPResponse {
        let url = store.attachmentURL(name)
        guard url.lastPathComponent == name, !name.hasPrefix("."), let data = try? Data(contentsOf: url) else { return .error(404, "No such file.") }
        let ext = url.pathExtension.lowercased()
        if let type = Self.types[ext] { return HTTPResponse(contentType: type, body: data, headers: ["Content-Security-Policy": "sandbox"]) }
        return HTTPResponse(contentType: "application/octet-stream", body: data, headers: ["Content-Disposition": "attachment; filename=\"\(name.replacingOccurrences(of: "\"", with: ""))\""])
    }

    /// The upload is the raw file as the request body; `?name=` carries the original file name. Pictures become PNG (as in the app), scaled to a sensible size.
    private func attach(_ item: Item, _ req: HTTPRequest) throws -> HTTPResponse {
        guard !req.body.isEmpty else { return .error(400, "Empty file.") }
        var data = req.body
        var ext = ((req.query["name"] ?? "") as NSString).pathExtension.lowercased()
        if ext.isEmpty, let ct = req.headers["content-type"], let sub = ct.split(separator: "/").last { ext = String(sub.split(separator: ";").first ?? "").lowercased() }
        if Self.imageTypes.contains(ext) || (req.headers["content-type"] ?? "").hasPrefix("image/") {
            guard let png = Self.pngData(from: data) else { return .error(415, "That picture could not be read.") }
            data = png; ext = "png"
        }
        let saved = try store.addAttachment(data, ext: ext, to: item)
        return .json(summary(saved))
    }

    static func pngData(from data: Data, maxPixels: Int = 2560) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: maxPixels]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }
}

public extension NotyStore {
    /// Stores a file next to the library and lists it on the item.
    func addAttachment(_ data: Data, ext: String, to item: Item) throws -> Item {
        var it = item
        var n = it.attachments.count + 1
        while it.attachments.contains(where: { $0.hasPrefix("\(it.id.prefix(8).lowercased())-\(n).") }) { n += 1 }
        it.attachments.append(try saveAttachment(data, itemID: it.id, index: n, ext: ext))
        return try save(it)
    }
}
