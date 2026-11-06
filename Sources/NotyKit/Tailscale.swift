// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Drives the Tailscale command line (the one inside Tailscale.app, or Homebrew's) so remote access needs no manual setup.
public enum Tailscale {
    public static let cliPaths = ["/Applications/Tailscale.app/Contents/MacOS/Tailscale", "/opt/homebrew/bin/tailscale", "/usr/local/bin/tailscale"]
    /// The HTTPS port Noty publishes on. Not 443, so it never replaces something the user already serves.
    public static let httpsPort = 8443

    public static var cli: String? { cliPaths.first { FileManager.default.isExecutableFile(atPath: $0) } }

    public struct Status: Equatable, Sendable {
        public var state: String                // "Running", "NeedsLogin", "Stopped", …
        public var dnsName: String?             // "my-mac.tail1234.ts.net" (no trailing dot)
        public var httpsEnabled: Bool           // the tailnet has HTTPS certificates turned on
        public var running: Bool { state == "Running" }
    }

    public static func parseStatus(_ data: Data) -> Status? {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let state = o["BackendState"] as? String else { return nil }
        var name = (o["Self"] as? [String: Any])?["DNSName"] as? String
        if name?.hasSuffix(".") == true { name?.removeLast() }
        let domains = o["CertDomains"] as? [Any] ?? []
        return Status(state: state, dnsName: name, httpsEnabled: !domains.isEmpty)
    }

    /// True if `serve status --json` already publishes `httpsPort` for this machine.
    public static func isServing(_ data: Data, port: Int = httpsPort) -> Bool {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let web = o["Web"] as? [String: Any] else { return false }
        return web.keys.contains { $0.hasSuffix(":\(port)") }
    }

    public static func url(for dnsName: String, port: Int = httpsPort) -> String { "https://\(dnsName):\(port)" }

    public static func status() async throws -> Status {
        guard let cli else { throw ShellError.toolNotFound("tailscale") }
        let r = try await Shell.run(cli, ["status", "--json"], timeout: 15)
        guard let s = parseStatus(Data(r.stdout.utf8)) else { throw ShellError.failed(command: "tailscale status", status: r.status, stderr: r.stderr.isEmpty ? "Tailscale is not running." : r.stderr) }
        return s
    }

    public static func serving() async -> Bool {
        guard let cli, let r = try? await Shell.run(cli, ["serve", "status", "--json"], timeout: 15) else { return false }
        return isServing(Data(r.stdout.utf8))
    }

    /// Publishes `localPort` on the tailnet over HTTPS. Reachable only by your own devices (this is `serve`, never `funnel`).
    public static func serve(localPort: Int) async throws {
        guard let cli else { throw ShellError.toolNotFound("tailscale") }
        try await Shell.check(cli, ["serve", "--bg", "--yes", "--https=\(httpsPort)", "http://127.0.0.1:\(localPort)"], timeout: 30)
    }

    public static func stopServing() async {
        guard let cli else { return }
        _ = try? await Shell.run(cli, ["serve", "--https=\(httpsPort)", "off"], timeout: 15)
    }
}
