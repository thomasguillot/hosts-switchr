import SwiftUI
import HostsKit

struct FragmentEditorView: View {
    @Environment(AppModel.self) private var model
    let fragmentID: UUID
    var requestApply: (UUID) -> Void

    @State private var text: String = ""

    private var fragment: LocalFragment? { model.fragments.first { $0.id == fragmentID } }
    private var isDirty: Bool { text != (fragment?.content ?? "") }

    // The active profile is the only one live in /etc/hosts; re-applying it publishes saved fragment changes.
    private var activeIncludingID: UUID? {
        guard let activeID = model.activeProfileID,
              model.profiles.contains(where: { $0.id == activeID && $0.fragmentIDs.contains(fragmentID) })
        else { return nil }
        return activeID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(8)

            let warnings = HostsValidator.validate(HostsFile(parsing: text))
            if !warnings.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(warnings, id: \.line) { w in
                        Label("Line \(w.line): \(w.message)", systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }

            Divider()
            HStack {
                Button("Save") { save(fragmentID) }
                .buttonStyle(.borderedProminent)
                .help("Save this fragment — does not change /etc/hosts")
                .disabled(!isDirty)
                Button("Cancel") { text = fragment?.content ?? "" }
                .help("Discard this draft and go back to the saved fragment")
                .disabled(!isDirty)
                Spacer()
                if let activeID = activeIncludingID, model.fragmentNeedsApply(fragmentID) {
                    Button("Re-apply Profile") { requestApply(activeID) }
                    .help("Publish the active profile with this fragment’s saved changes")
                    .disabled(model.isApplying)
                }
            }
            .padding(8)
        }
        .onAppear { text = fragment?.content ?? "" }
        .onChange(of: fragmentID) { old, _ in
            // A draft is committed when you navigate away, never silently discarded.
            save(old)
            text = fragment?.content ?? ""
        }
        .onDisappear { save(fragmentID) }
    }

    private func save(_ id: UUID) {
        model.updateFragmentContent(id, content: text)
        model.flushPendingSave()
    }
}
