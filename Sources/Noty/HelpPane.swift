// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import NotyKit

/// Plain-language help and a glossary. Every option in Settings that introduces a term gets an entry here.
struct HelpPane: View {
    private let entries: [(String, String)] = [
        ("Capture", "Select text in any app, then press the capture shortcut. A small panel opens next to your pointer: choose a type and a category with the arrow keys and press Return. You can also right-click a selection and choose Services → Add to Noty."),
        ("Workspace and category", "A workspace is a top-level folder such as Work or Personal. Categories nest inside it as deep as you like. The tree on the left mirrors real folders in your library."),
        ("Inbox", "Captures you did not sort yet. Turn off “Ask where every time” in Settings and everything lands in the last category used for that app."),
        ("Library", "One folder of Markdown files, one file per item. You can open them in any editor. Settings → Sync moves it to iCloud Drive or any folder."),
        ("Agents and MCP", "MCP is the standard way for AI agents to use an app. Connect Claude Code, Claude Desktop or Cursor in Settings → Agents, then use Ask agent on any item. Agents read and edit your items; files they want to create wait for your approval under Agent results."),
        ("Accessibility permission", "macOS asks you to allow Noty under Privacy & Security → Accessibility. It is used only to read the text you have selected when you press the shortcut."),
    ]
    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(title: "Help")
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Noty turns text you highlight anywhere on your Mac into a tidy, categorised to-do list that your AI agents can work on.").font(.system(size: 13.5))
                    ForEach(entries, id: \.0) { e in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(e.0).font(.system(size: 13, weight: .semibold))
                            Text(e.1).font(.system(size: 12.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }.card(padding: 12)
                    }
                }.padding(22).frame(maxWidth: 720, alignment: .leading)
            }
        }
    }
}
