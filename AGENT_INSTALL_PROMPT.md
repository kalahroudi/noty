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
