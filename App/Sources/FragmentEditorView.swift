import SwiftUI
import HostsKit

struct FragmentEditorView: View {
    @Environment(AppModel.self) private var model
    let fragmentID: UUID
    var requestApply: (UUID) -> Void

    @State private var text: String = ""

    private var fragment: LocalFragment? { model.fragments.first { $0.id == fragmentID } }

    // The active profile is the only one live in /etc/hosts; applying an edited fragment means re-applying it.
    private var activeIncludingID: UUID? {
        guard let activeID = model.activeProfileID,
              model.profiles.contains(where: { $0.id == activeID && $0.fragmentIDs.contains(fragmentID) })
        else { return nil }
        return activeID
    }

    private var canApply: Bool {
        guard let activeID = activeIncludingID else { return false }
        return !model.isApplying && model.staleProfileIDs.contains(activeID)
    }

    var body: some View {
        // Apply stays pinned below a scrollable body, matching the profile editor.
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    TextEditor(text: $text)
                        .font(.system(.body, design: .monospaced))
                        .onChange(of: text) { _, new in model.updateFragmentContent(fragmentID, content: new) }
                        .frame(maxWidth: .infinity, minHeight: 220)
                        .padding(8)

                    let warnings = model.warningsForFragment(fragmentID)
                    if !warnings.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(warnings, id: \.line) { w in
                                Label("Line \(w.line): \(w.message)", systemImage: "exclamationmark.triangle")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    }
                }
            }

            Divider()
            HStack {
                Button("Apply") { if let activeID = activeIncludingID { requestApply(activeID) } }
                .buttonStyle(.borderedProminent)
                .help("Re-apply the active profile with this fragment’s changes")
                .disabled(!canApply)
                Spacer()
            }
            .padding(8)
        }
        .onAppear { text = fragment?.content ?? "" }
        .onChange(of: fragmentID) { _, _ in text = fragment?.content ?? "" }
    }
}
