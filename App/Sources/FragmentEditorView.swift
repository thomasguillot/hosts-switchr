import SwiftUI
import HostsKit

struct FragmentEditorView: View {
    @Environment(AppModel.self) private var model
    let fragmentID: UUID

    @State private var text: String = ""

    private var fragment: LocalFragment? { model.fragments.first { $0.id == fragmentID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .onChange(of: text) { _, new in model.updateFragmentContent(fragmentID, content: new) }
                .frame(maxWidth: .infinity, minHeight: 200)
                .padding(8)

            let warnings = model.warningsForFragment(fragmentID)
            if !warnings.isEmpty {
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(warnings, id: \.line) { w in
                            Label("Line \(w.line): \(w.message)", systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }.frame(maxHeight: 100)
            }
        }
        .onAppear { text = fragment?.content ?? "" }
        .onChange(of: fragmentID) { _, _ in text = fragment?.content ?? "" }
    }
}
