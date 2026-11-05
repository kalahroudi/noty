# Noty

Highlight text in any app, press a shortcut, and it lands in a categorised to-do tree. Your AI agents can then review it, break it down, turn it into skills or Markdown files, and work through it.

A light native macOS app (Swift, SwiftUI + AppKit, no dependencies): menu bar popover, Dock icon, manager window, MCP server for agents.

## Install with an AI agent

Paste this into an AI coding agent such as Claude Code. Noty needs nothing installed first:

```text
Install Noty on this Mac.
1. Run: curl -fsSL https://raw.githubusercontent.com/kalahroudi/noty/main/scripts/install.sh | bash
2. Noty opens in the menu bar. Tell me to press ⌥⌘N once and allow Accessibility when macOS asks.
3. Register its MCP server: claude mcp add noty --scope user -- /Applications/Noty.app/Contents/MacOS/noty-mcp
4. Call get_status and tell me what it reports.
Never delete my items without asking me first.
```

## How it works

- **Capture:** select text anywhere (mouse or `⇧`+arrows), press `⌥⌘N` (changeable). A small panel appears next to the pointer: pick a type and a category with the arrow keys, press `↩`. `⌘↩` adds and opens "Ask agent". Also available as right-click → Services → Add to Noty. Needs the Accessibility permission for the shortcut.
- **Library:** workspaces and categories are folders; every item is a Markdown file with its highlighted text, notes, tags and source link. Open them in any editor.
- **Sync:** Settings → Sync moves the library to iCloud Drive or any folder (Dropbox, Syncthing, git). No server, no account. If two Macs edit the same item, the newer copy wins and the other is kept in `_history`.
- **Agents (MCP):** Settings → Agents connects Claude Code, Claude Desktop, Cursor and others in one click. Tools: `list_workspaces`, `list_items`, `get_item`, `search`, `add_item`, `update_item`, `move_item`, `complete_item`, `create_category`, `rename_category`, `propose_file`, `delete_item`. Files an agent wants to create wait under Agent results until you approve them.
- **Ask agent:** on any item or list, choose Review, Break into subtasks, Turn into a skill, Write a .md file or Process & fix. Noty builds the prompt and can run it in Claude Code in your Terminal, or you copy it into any agent.

## Build

```sh
swift build && swift test
scripts/bundle.sh              # dist/Noty.app
dist/Noty.app/Contents/MacOS/Noty --self-test
dist/Noty.app/Contents/MacOS/Noty --snapshot docs/shots   # screenshots with sample data
```

Release, signing and the updater follow the native-mac-app scaffold (`scripts/`, `.github/workflows/`).
