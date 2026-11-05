// SPDX-License-Identifier: Apache-2.0

import Foundation

/// What the user can ask an agent to do with items. The prompt tells the agent to use the Noty MCP tools,
/// so the same words work in Claude Code, Codex, Cursor or Claude Desktop.
public enum AgentAction: Hashable, Sendable, CaseIterable, Identifiable {
    case review, subtasks, skill, markdown, fix
    public var id: Self { self }
    public var label: String {
        switch self { case .review: "Review"; case .subtasks: "Break into subtasks"; case .skill: "Turn into a skill"; case .markdown: "Write a .md file"; case .fix: "Process & fix" }
    }
    public var symbol: String {
        switch self { case .review: "magnifyingglass"; case .subtasks: "list.bullet.indent"; case .skill: "sparkles"; case .markdown: "doc.text"; case .fix: "wrench.and.screwdriver" }
    }
    var instruction: String {
        switch self {
        case .review: "Review them: say what is clear, what is missing or risky, and what I should do next. Add your findings to each item with update_item (notes), keeping what is already there."
        case .subtasks: "Break each one into small concrete subtasks. Create them with add_item in the same category as the original, as tasks, and mention the original title in their notes."
        case .skill: "Turn them into one reusable agent skill (a SKILL.md with name and description front matter, then clear steps). Send it with propose_file under skills/<name>/SKILL.md and set complete_items to true."
        case .markdown: "Write a clear Markdown document that captures them, with the sources cited. Send it with propose_file."
        case .fix: "Process them: if an item describes something to fix or build in my project, do the work, then record what you did in the item's notes with update_item and complete it with complete_item."
        }
    }
}

public enum AgentPrompt {
    public static func build(_ action: AgentAction, items: [Item], extra: String = "") -> String { build(instruction: action.instruction, items: items, extra: extra) }

    public static func build(instruction: String, items: [Item], extra: String = "") -> String {
        let list = items.map { "- \($0.id)  \($0.title)  [\($0.pathLabel)]" }.joined(separator: "\n")
        var p = "Use the noty MCP tools. Read these items first with get_item:\n\(list)\n\n\(instruction)"
        if !extra.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { p += "\n\nExtra instructions: \(extra.trimmingCharacters(in: .whitespacesAndNewlines))" }
        p += "\n\nChanges to files must go through propose_file so I can approve them. Never delete items."
        return p
    }
}
