import SwiftUI
import AppKit

struct DocumentationView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Hosts Switchr")
                        .font(.largeTitle.bold())
                    Text("Manage your /etc/hosts file through switchable profiles.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                section("Profiles", """
                A profile is a named set of hosts entries. Select one in the sidebar and click \
                Apply to make it active — the active profile is marked with a checkmark. \
                The System Default profile holds your original hosts file; apply it to restore \
                your machine to how it was before Hosts Switchr.
                """)

                section("Fragments", """
                Fragments are reusable snippets you toggle on per profile, such as a "Docker" or \
                "Staging" block. Enabled fragments are merged into the active profile under a \
                "# <name>" header so you can see where they came from.
                """)

                section("Sources", """
                Sources are remote blocklists you subscribe to, like StevenBlack or HaGeZi. \
                Toggle them per profile and refresh to pull updates. You can add your own source \
                by URL — it must be https, and its contents are verified by checksum before use.
                """)

                section("Applying changes", """
                Apply merges your content in order — local profile entries, then enabled \
                fragments, then source lists — and writes the result to /etc/hosts. macOS asks \
                for your administrator password because that file is system-owned. Your previous \
                hosts file is backed up automatically before each apply.
                """)

                section("Menu bar & Settings", """
                Switch profiles, refresh sources, or open the window from the menu-bar icon. \
                In Settings you can set the auto-refresh interval, re-apply the active profile \
                automatically after a refresh, show the active profile's name in the menu bar, \
                and launch Hosts Switchr at login.
                """)
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 480, idealWidth: 560, minHeight: 420, idealHeight: 640)
        .onAppear { NSApplication.shared.activate(ignoringOtherApps: true) }
    }

    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
