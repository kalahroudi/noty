// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import NotyKit

/// Remote access: your library as a web app on your phone or another computer, over Tailscale. One switch does the setup.
struct RemoteView: View {
    let remote = RemoteController.shared
    let prefs = Prefs.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsGroup("Remote access") {
                SettingRow("Use Noty from your phone or another computer", "Turns on a private web app, published only to your own Tailscale devices (never the public internet). Noty sets it up for you; nothing to configure.") {
                    Toggle("", isOn: Binding(get: { prefs.remoteEnabled }, set: { remote.setEnabled($0) })).labelsHidden().toggleStyle(.switch).tint(Theme.accent)
                }
                if prefs.remoteEnabled { status }
            }
            if case .on(let url) = remote.state { pairing(url) }
            SettingsGroup("What you can do there") {
                SettingRow("Browse and add", "See Today, Inbox, open and done items, search, add to the Inbox, tick items off, edit notes and add to Today. Needs this Mac to be on and Noty running.") { EmptyView() }
                SettingRow("Who can open it", "Only devices signed in to your Tailscale account. Websites cannot reach it, and it is not exposed with Funnel.") { Badge(text: "tailnet only", kind: .ok) }
            }
        }
    }

    @ViewBuilder private var status: some View {
        switch remote.state {
        case .off, .working:
            SettingRow("Status", "Checking Tailscale and publishing Noty…") { ProgressView().controlSize(.small) }
        case .on:
            SettingRow("Status", "Running. Open the address on any device in your tailnet.") { Badge(text: "on", kind: .ok) }
        case .needsTailscale:
            SettingRow("Tailscale", "Noty needs the Tailscale app. Install it, sign in, then come back and press Try again.") {
                HStack { Button("Get Tailscale") { remote.openTailscale() }.buttonStyle(Pill(kind: .primary)); Button("Try again") { remote.retry() }.buttonStyle(Pill()) }
            }
        case .needsLogin:
            SettingRow("Tailscale", "Tailscale is installed but not connected. Open it and sign in, then press Try again.") {
                HStack { Button("Open Tailscale") { remote.openTailscale() }.buttonStyle(Pill(kind: .primary)); Button("Try again") { remote.retry() }.buttonStyle(Pill()) }
            }
        case .needsHTTPS:
            SettingRow("HTTPS certificates", "Tailscale needs HTTPS turned on for your tailnet once (DNS page → Enable HTTPS). Then press Try again.") {
                HStack { Button("Open admin page") { remote.openHTTPSAdmin() }.buttonStyle(Pill(kind: .primary)); Button("Try again") { remote.retry() }.buttonStyle(Pill()) }
            }
        case .failed(let message):
            SettingRow("Could not start", message, error: message) { Button("Try again") { remote.retry() }.buttonStyle(Pill(kind: .primary)) }
        }
    }

    private func pairing(_ url: String) -> some View {
        SettingsGroup("Pair a device") {
            HStack(alignment: .center, spacing: 18) {
                if let qr = RemoteController.qr(url, size: 180) {
                    Image(nsImage: qr).interpolation(.none).resizable().frame(width: 150, height: 150).padding(8).background(.white, in: RoundedRectangle(cornerRadius: 10)).accessibilityLabel("QR code for \(url)")
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Scan with your phone's camera").font(.system(size: 13, weight: .semibold))
                    Text("Your phone needs the Tailscale app, signed in to the same account. Then add the page to your Home Screen to use it like an app.").font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text(url).font(.system(size: 11.5, design: .monospaced)).textSelection(.enabled).lineLimit(2)
                    HStack {
                        Button("Copy address") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(url, forType: .string) }.buttonStyle(Pill())
                        Button("Open here") { NSWorkspace.shared.open(URL(string: url)!) }.buttonStyle(Pill())
                    }
                }
            }.padding(.vertical, 4)
        }
    }
}
