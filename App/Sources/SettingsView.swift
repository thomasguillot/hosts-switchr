import SwiftUI
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
        Form {
            Section("General") {
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
                Toggle("Show active profile name in menu bar", isOn: $showActiveName)
            }
            Section("Sources") {
                Picker("Refresh interval", selection: $intervalHours) {
                    Text("Off").tag(0)
                    Text("Every 6 hours").tag(6)
                    Text("Every 12 hours").tag(12)
                    Text("Daily").tag(24)
                    Text("Weekly").tag(168)
                }
                Toggle("Auto re-apply active profile after refresh", isOn: $autoReapply)
            }
            Section("Updates") {
                Toggle("Automatically check for updates on launch", isOn: $autoCheckForUpdates)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .focusedSceneValue(\.deleteAction, nil)
        .onChange(of: intervalHours) { _, _ in model.rescheduleRefresh() }
        .onAppear { launchAtLogin = loginItem.isEnabled }
    }
}
