import SwiftUI
import AppKit
import HostsKit

struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(WindowRouter.self) private var router
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
                Label(profile.name + (stale ? " \u{21BB}" : ""),
                      systemImage: isActive ? "checkmark" : "")
            }
        }
        Divider()
        Button {
            Task { await model.refreshAllSources() }
        } label: {
            Label("Refresh All Sources", systemImage: "arrow.clockwise")
        }
        Button {
            NSApplication.shared.activate(ignoringOtherApps: true)
            openWindow(id: "main")
        } label: {
            Label("Open Hosts Switchr\u{2026}", systemImage: "macwindow")
        }
        updateItem
        Divider()
        Button {
            NSApplication.shared.activate(ignoringOtherApps: true)
            router.section = .settings
            openWindow(id: "main")
        } label: {
            Label("Settings\u{2026}", systemImage: "gearshape")
        }
        Button {
            model.flushPendingSave()
            NSApplication.shared.terminate(nil)
        } label: {
            Label("Quit", systemImage: "xmark.rectangle")
        }
    }

    @ViewBuilder
    private var updateItem: some View {
        switch update.state {
        case .available, .readyToInstall:
            Button {
                Task { await update.showWindowOrCheck() }
            } label: {
                let version = update.plan.map { update.displayVersion($0.version) } ?? ""
                Label("Update to v\(version)\u{2026}", systemImage: "arrow.down.circle.fill")
            }
        case .checking:
            Button {} label: { Label("Checking for Updates\u{2026}", systemImage: "arrow.down.circle") }
                .disabled(true)
        case .downloading:
            Button {
                Task { await update.showWindowOrCheck() }
            } label: {
                Label("Downloading Update\u{2026}", systemImage: "arrow.down.circle")
            }
        default:
            Button {
                Task { await update.checkNow(userInitiated: true) }
            } label: {
                Label("Check for Updates\u{2026}", systemImage: "arrow.down.circle")
            }
        }
    }
}
