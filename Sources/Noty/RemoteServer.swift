// SPDX-License-Identifier: Apache-2.0

import Foundation
import Network
import AppKit
import CoreImage
import NotyKit

/// A tiny HTTP server bound to this Mac only (127.0.0.1). Tailscale Serve is the only thing that puts it on the network, and only on your tailnet.
final class RemoteServer: @unchecked Sendable {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "noty.remote")
    private let api: @Sendable () -> RemoteAPI

    init(api: @escaping @Sendable () -> RemoteAPI) { self.api = api }

    func start(port: Int, onFailure: @escaping @Sendable (String) -> Void) throws {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(integerLiteral: UInt16(port)))
        let l = try NWListener(using: params)
        l.newConnectionHandler = { [weak self] c in self?.accept(c) }
        l.stateUpdateHandler = { if case .failed(let e) = $0 { onFailure("Port \(port) is not available: \(e.localizedDescription)") } }
        l.start(queue: queue)
        listener = l
    }

    func stop() { listener?.cancel(); listener = nil }

    private func accept(_ c: NWConnection) {
        c.start(queue: queue)
        c.stateUpdateHandler = { if case .failed = $0 { c.cancel() } }
        read(c, Data())
        queue.asyncAfter(deadline: .now() + 15) { c.cancel() }          // a client that never finishes its request is dropped
    }

    private func read(_ c: NWConnection, _ so_far: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, done, err in
            guard let self else { c.cancel(); return }
            var buf = so_far; if let data { buf.append(data) }
            switch HTTPParser.parse(buf) {
            case .needMore: if done || err != nil { c.cancel() } else { self.read(c, buf) }
            case .bad: self.send(c, .error(400, "Bad request."))
            case .tooLarge: self.send(c, .error(413, "Too large."))
            case .request(let r): self.send(c, self.api().handle(r))
            }
        }
    }

    private func send(_ c: NWConnection, _ r: HTTPResponse) {
        c.send(content: r.serialized(), contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in c.cancel() })
    }
}

/// Settings → Remote: turns the server and the Tailscale publishing on and off and reports where you can reach Noty.
@MainActor @Observable
final class RemoteController {
    static let shared = RemoteController()
    static let localPort = 47653

    enum State: Equatable { case off, working, on(url: String), needsTailscale, needsLogin, needsHTTPS, failed(String) }
    private(set) var state: State = .off
    private var server: RemoteServer?

    var enabled: Bool { if case .off = state { return false }; return true }

    /// Called at launch: if remote access was on, bring it back (and repair the Tailscale publishing if it was reset).
    func startIfEnabled() { if Prefs.shared.remoteEnabled { Task { await enable() } } }

    func setEnabled(_ on: Bool) {
        Prefs.shared.remoteEnabled = on
        Task { if on { await enable() } else { await disable() } }
    }

    func retry() { Task { await enable() } }

    private func enable() async {
        state = .working
        guard Tailscale.cli != nil else { state = .needsTailscale; return }
        do {
            let st = try await Tailscale.status()
            guard st.running, let name = st.dnsName else { state = .needsLogin; return }
            guard st.httpsEnabled else { state = .needsHTTPS; return }
            try startServer()
            try await Tailscale.serve(localPort: Self.localPort)
            state = .on(url: Tailscale.url(for: name))
        } catch {
            server?.stop(); server = nil
            state = .failed(error.localizedDescription)
        }
    }

    private func disable() async {
        server?.stop(); server = nil
        await Tailscale.stopServing()
        state = .off
    }

    private func startServer() throws {
        guard server == nil else { return }
        let s = RemoteServer { RemoteAPI(store: NotyStore(root: NotyStore.resolveRoot()), page: RemotePage.html) }
        try s.start(port: Self.localPort) { msg in Task { @MainActor in RemoteController.shared.state = .failed(msg) } }
        server = s
    }

    func openTailscale() { NSWorkspace.shared.open(URL(string: Tailscale.cli != nil ? "file:///Applications/Tailscale.app" : "https://tailscale.com/download/mac")!) }
    func openHTTPSAdmin() { NSWorkspace.shared.open(URL(string: "https://login.tailscale.com/admin/dns")!) }

    static func qr(_ text: String, size: CGFloat) -> NSImage? {
        guard let f = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        f.setValue(Data(text.utf8), forKey: "inputMessage"); f.setValue("M", forKey: "inputCorrectionLevel")
        guard let out = f.outputImage else { return nil }
        let scale = floor(size / out.extent.width)
        let img = out.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let rep = NSCIImageRep(ciImage: img)
        let ns = NSImage(size: rep.size); ns.addRepresentation(rep)
        return ns
    }
}
