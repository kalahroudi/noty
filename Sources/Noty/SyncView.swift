// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import NotyKit

/// Sync is plain files: the library folder is copied between Macs by iCloud Drive (or Dropbox, Syncthing, git) and Noty re-reads it when it changes.
struct SyncView: View {
    let lib = LibraryModel.shared
    @State private var tick = 0

    private enum Place { case local, icloud, custom }
    private var place: Place {
        let p = lib.store.root.standardizedFileURL.path
        if p == NotyStore.iCloudDriveFolder.standardizedFileURL.path { return .icloud }
        if p == AppPaths().defaultLibrary.standardizedFileURL.path { return .local }
        return .custom
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsGroup("Where your library lives") {
                SettingRow("Location", "Your items are Markdown files in one folder. Sync copies that folder between your Macs; there is no Noty server and no account.") {
                    Segmented(options: [(Place.local, "This Mac"), (Place.icloud, "iCloud Drive"), (Place.custom, "Folder…")], selection: Binding(get: { place }, set: choose))
                }
                SettingRow("Folder", "Move it anywhere, including a Dropbox, Syncthing or git folder. Existing items are copied, never overwritten.") {
                    HStack(spacing: 6) {
                        Text(lib.store.root.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).font(.system(size: 11.5, design: .monospaced)).lineLimit(1).truncationMode(.middle).frame(maxWidth: 260, alignment: .trailing)
                        Button { NSWorkspace.shared.activateFileViewerSelecting([lib.store.root]) } label: { Image(systemName: "folder") }.buttonStyle(.plain).help("Show in Finder").accessibilityLabel("Show in Finder")
                    }
                }
            }
            SettingsGroup("Status") {
                SettingRow("Items", "\(lib.categories.count) categories in the library.") { Text("\(lib.items.count)").font(.system(size: 13)).monospacedDigit() }
                SettingRow("Conflicts", "If the same item is edited on two Macs before they sync, the newer copy wins and the other is kept in the _history folder of the library.") {
                    if lib.conflicts == 0 { Badge(text: "none", kind: .ok) } else { Badge(text: "\(lib.conflicts) resolved", kind: .warn) }
                }
                if place == .icloud {
                    SettingRow("iCloud Drive", "Make sure iCloud Drive is on in System Settings → Apple Account → iCloud so the folder syncs.") { Badge(text: NotyStore.iCloudDriveAvailable ? "available" : "not found", kind: NotyStore.iCloudDriveAvailable ? .ok : .danger) }
                }
            }
        }
    }

    private func choose(_ p: Place) {
        switch p {
        case .local: lib.moveLibrary(to: AppPaths().defaultLibrary)
        case .icloud:
            guard NotyStore.iCloudDriveAvailable else { AppModel.shared.show("iCloud Drive isn't turned on for this Mac. Turn it on in System Settings, or choose a folder.", error: true); return }
            lib.moveLibrary(to: NotyStore.iCloudDriveFolder)
        case .custom:
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
            panel.prompt = "Use this folder"; panel.message = "Choose the folder that holds your Noty library."
            if panel.runModal() == .OK, let url = panel.url { lib.moveLibrary(to: url.lastPathComponent == "Noty" ? url : url.appendingPathComponent("Noty", isDirectory: true)) }
        }
    }
}
