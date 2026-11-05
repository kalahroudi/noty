// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Every file the app owns lives under one folder, so uninstalling is deleting it.
/// The library itself (the user's items) lives in `NotyStore.resolveRoot()`, which the user can move (iCloud Drive, any folder).
public struct AppPaths: Sendable {
    public let root: URL

    public init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Noty", isDirectory: true)
    }

    public var updateDir: URL { root.appendingPathComponent("update", isDirectory: true) }
    public var settingsFile: URL { root.appendingPathComponent("settings.json") }
    /// Where the library is. Written by the app, read by the MCP server, so both always open the same folder.
    public var locationFile: URL { root.appendingPathComponent("location.json") }
    /// The default library, used until the user picks iCloud Drive or another folder.
    public var defaultLibrary: URL { root.appendingPathComponent("Library", isDirectory: true) }

    public func ensureDirectories() throws {
        for dir in [root, updateDir] { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
    }
}
