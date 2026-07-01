import SwiftUI
import AppKit
import HostsKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("refreshIntervalHours") private var intervalHours: Int = 24
    @AppStorage("autoReapply") private var autoReapply: Bool = true
    @AppStorage("showActiveNameInMenuBar") private var showActiveName = false
    @AppStorage("autoCheckForUpdates") private var autoCheckForUpdates = true

    private let loginItem: LoginItemControlling = SMAppServiceLoginItem()
    @State private var launchAtLogin = false
    @State private var loginError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Refresh interval", selection: $intervalHours) {
                Text("Off").tag(0)
                Text("Every 6 hours").tag(6)
                Text("Every 12 hours").tag(12)
                Text("Daily").tag(24)
                Text("Weekly").tag(168)
            }
            .fixedSize()
            Toggle("Auto re-apply active profile after refresh", isOn: $autoReapply)
            Toggle("Show active profile name in menu bar", isOn: $showActiveName)
            Toggle("Automatically check for updates on launch", isOn: $autoCheckForUpdates)
            Toggle("Launch at login", isOn: Binding(
                get: { launchAtLogin },
                set: { newValue in
                    let result = LaunchAtLogin.apply(newValue, to: loginItem)
                    launchAtLogin = result.isEnabled
                    loginError = result.error
                }
            ))
            if let loginError {
                Text(loginError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(20)
        .frame(width: 400, alignment: .leading)
        .onChange(of: intervalHours) { _, _ in model.rescheduleRefresh() }
        .onAppear {
            launchAtLogin = loginItem.isEnabled
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}
