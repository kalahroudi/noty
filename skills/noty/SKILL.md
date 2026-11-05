---
name: noty
description: Use on macOS when the user has captured highlights, tasks or notes in Noty and wants you to review them, break them down, turn them into skills or Markdown files, or process and fix what they describe. Uses the Noty menu bar app through its MCP tools. Also covers installing Noty.
---

# Noty

Noty is a macOS menu bar app where the user files text they highlighted in any app into a tree of workspaces and categories (for example `Work/Q4 Launch/Research`). Each item keeps its highlighted text, notes, tags and source (app, page title, URL). Use these tools instead of asking the user to paste things.

## Workflow

1. `list_workspaces` to see the tree, then `list_items` (filter by `path`, `today`, `query`) or `search`.
2. `get_item` for every item you will act on: the full highlighted text and the source link are there.
3. Do the work, then record it: `update_item` with `append_notes` (keeps what is there), `complete_item` when finished, `add_item` for follow-up subtasks in the same category.
4. To create a file (a skill, a summary, a plan) use `propose_file`. Nothing is written until the user approves it in Noty under Agent results. For a skill use the name `skills/<skill-name>/SKILL.md` with `name` and `description` front matter. Set `item_ids` and `complete_items` so approved items are finished.

## Rules

- Ask which category or items first if the request is vague. Do not act on the whole library.
- Never delete. `delete_item` exists but needs `confirm_title`; prefer `complete_item`, and ask the user before using it.
- If a call returns an error, report it plainly and do not retry in a loop.
- Items are Markdown files in the library folder (`get_status` shows where). Do not edit them behind the tools' back.

## Tool reference

| MCP tool | Changes things |
|---|---|
| `get_status {}` | no |
| `list_workspaces {}` | no |
| `list_items {path?, status?, today?, query?, limit?}` | no |
| `get_item {id}` | no |
| `search {query, limit?}` | no |
| `add_item {title, path?, kind?, quote?, notes?, tags?, today?, source_*?}` | yes |
| `update_item {id, title?, kind?, tags?, today?, notes?, append_notes?}` | yes |
| `move_item {id, path}` | yes |
| `complete_item {id, done?}` | yes |
| `create_category {path}` | yes |
| `propose_file {name, content, note?, item_ids?, complete_items?}` | only after the user approves |
| `delete_item {id, confirm_title}` | yes, ask the user first |

## Installing Noty (ask the user first)

Only install when `/Applications/Noty.app` does not exist.

1. `curl -fsSL https://raw.githubusercontent.com/kalahroudi/noty/main/scripts/install.sh | bash`
2. Noty opens in the menu bar. Tell the user to press the capture shortcut once (⌥⌘N) and allow Accessibility when macOS asks.
3. Register the MCP server: `claude mcp add noty --scope user -- /Applications/Noty.app/Contents/MacOS/noty-mcp`
4. Call `get_status` and report what it says.
