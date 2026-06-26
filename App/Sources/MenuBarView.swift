import SwiftUI
import AppKit
import HostsKit

struct MenuBarView: View {
    @Environment(AppModel.self) private var model
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
        Divider()
        Button("Quit") { model.flushPendingSave(); NSApplication.shared.terminate(nil) }
    }
}
