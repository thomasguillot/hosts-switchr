import AppKit
import SwiftUI

struct AboutView: View {
    @Environment(UpdateController.self) private var update

    private var year: String { String(Calendar.current.component(.year, from: Date())) }

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Hosts Switchr")
                .font(.title2.weight(.semibold))
            Text("Version \(update.currentDisplayVersion)")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Check for Updates…") {
                Task { await update.checkNow(userInitiated: true) }
            }
            .padding(.top, 6)
            Text("© \(year) Thomas Guillot")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
        }
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
        .navigationTitle("About")
        .focusedSceneValue(\.deleteAction, nil)
    }
}
