// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import AppKit

enum Theme {
    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light })
    }
    static func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: a)
    }

    // Highlighter-marker yellow on slate: the app is about highlighting. Text on accent is always near-black.
    static let accent = dynamic(light: rgb(0xF5C518), dark: rgb(0xF5C518))
    static let onAccent = dynamic(light: rgb(0x241C00), dark: rgb(0x241C00))
    static let accentSoft = dynamic(light: rgb(0xF5C518, 0.22), dark: rgb(0xF5C518, 0.16))
    static let highlight = dynamic(light: rgb(0xE0AE00), dark: rgb(0xF5C518))
    /// Dark gold for text sitting on the soft accent fill; yellow text itself would not be readable on a light background.
    static let onSoft = dynamic(light: rgb(0x7A5C00), dark: rgb(0xF5C518))
    /// Accent used for text and selection on neutral backgrounds (yellow text would not be readable on white).
    static let link = dynamic(light: rgb(0x2F6FED), dark: rgb(0x7FA6ED))
    static let ok = dynamic(light: rgb(0x1B7F43), dark: rgb(0x4ADE80))
    static let warn = dynamic(light: rgb(0xA35A00), dark: rgb(0xFBBF24))
    static let warnSoft = dynamic(light: rgb(0xFFF4E0), dark: rgb(0xFBBF24, 0.14))
    static let danger = dynamic(light: rgb(0xC0302B), dark: rgb(0xF87171))
    static let dangerSoft = dynamic(light: rgb(0xFDE9E7), dark: rgb(0xF87171, 0.14))
    static let card = dynamic(light: .white, dark: rgb(0x26272B))
    static let pane = dynamic(light: rgb(0xF5F5F7), dark: rgb(0x1C1C1F))
    static let sidebar = dynamic(light: rgb(0xE8E9EE), dark: rgb(0x232326))
    static let hairline = dynamic(light: NSColor.black.withAlphaComponent(0.08), dark: NSColor.white.withAlphaComponent(0.1))
    static let fill = dynamic(light: NSColor.black.withAlphaComponent(0.06), dark: NSColor.white.withAlphaComponent(0.08))
    static let terminal = Color(nsColor: rgb(0x1E1F24))
}

extension View {
    func card(padding: CGFloat = 12) -> some View {
        self.padding(padding)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline))
    }
}
