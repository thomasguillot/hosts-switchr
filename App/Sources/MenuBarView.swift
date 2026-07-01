import SwiftUI
import AppKit
import HostsKit

struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(UpdateController.self) private var update
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ForEach(model.profiles) { profile in
            Button {
                model.selectedProfileID = profile.id
                Task { await model.applyAsync(profile.id) }
            } label: {
                let isActive = profile.id == model.activeProfileID
                let stale = model.staleProfileIDs.contains(profile.id)
                Label(profile.name + (stale ? " \u{26A0}\u{FE0E}" : ""),
                      systemImage: isActive ? "checkmark" : "")
            }
        }
        Divider()
        Button("Refresh All Sources") { Task { await model.refreshAllSources() } }
        Button("Open Hosts Switchr\u{2026}") {
            NSApplication.shared.activate(ignoringOtherApps: true)
            openWindow(id: "main")
        }
        SettingsLink { Text("Settings\u{2026}") }
        updateItem
        Divider()
        Button("Quit") { model.flushPendingSave(); NSApplication.shared.terminate(nil) }
    }

    @ViewBuilder
    private var updateItem: some View {
        switch update.state {
        case let .available(version, _, _):
            Button {
                Task { await update.downloadAndOpen() }
            } label: {
                Label("Update to v\(version)\u{2026}", systemImage: "arrow.down.circle.fill")
            }
        case .checking:
            Button("Checking for Updates\u{2026}") {}.disabled(true)
        case .downloading:
            Button("Downloading Update\u{2026}") {}.disabled(true)
        default:
            Button("Check for Updates\u{2026}") {
                Task { await update.checkNow(userInitiated: true) }
            }
        }
    }
}
