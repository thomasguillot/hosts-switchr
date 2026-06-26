import SwiftUI
import HostsKit

struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model
    @AppStorage("showActiveNameInMenuBar") private var showName = false

    var body: some View {
        let activeName = model.profiles.first { $0.id == model.activeProfileID }?.name
        if let text = MenuBarLabelText.displayName(showName: showName, activeName: activeName) {
            HStack(spacing: 0) {
                Image("MenuBarIcon")
                Text(" \(text)")
            }
        } else {
            Image("MenuBarIcon")
        }
    }
}
