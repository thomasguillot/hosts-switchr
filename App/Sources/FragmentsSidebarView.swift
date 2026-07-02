import SwiftUI
import HostsKit

struct FragmentsSidebarView: View {
    @Environment(AppModel.self) private var model
    @State private var renamingID: UUID?
    @State private var renameText: String = ""
    @FocusState private var renameFocus: UUID?

    var body: some View {
        @Bindable var model = model
        Group {
            if model.fragments.isEmpty {
                ContentUnavailableView {
                    Label("No Fragments", systemImage: "rectangle.stack")
                } description: {
                    Text("Reusable host snippets you toggle per profile — e.g. a \u{201C}Docker\u{201D} fragment listing every local container hostname, switched on only in your Dev profile.")
                } actions: {
                    Button("Add Fragment") { createAndRename() }
                }
            } else {
                List(selection: $model.selectedFragmentID) {
                    ForEach(model.fragments) { fragment in
                        Group {
                            if renamingID == fragment.id {
                                TextField("Name", text: $renameText)
                                    .textFieldStyle(.plain)
                                    .focused($renameFocus, equals: fragment.id)
                                    .onSubmit { commitRename() }
                                    .onExitCommand { renamingID = nil }
                            } else {
                                Text(fragment.name)
                            }
                        }
                        .tag(fragment.id)
                        .contextMenu {
                            Button("Rename") { startRename(fragment) }
                            Button("Delete", role: .destructive) { model.deleteFragment(fragment.id) }
                        }
                        .listRowSeparator(.hidden)
                    }
                    .onMove(perform: model.fragments.count > 1
                        ? { model.moveFragments(fromOffsets: $0, toOffset: $1) } : nil)
                    Button("Add Fragment") { createAndRename() }
                        .buttonStyle(.bordered)
                        .padding(.top, 8)
                        .listRowSeparator(.hidden)
                }
            }
        }
        .onChange(of: renameFocus) { _, new in if new == nil, renamingID != nil { commitRename() } }
        .onKeyPress(.return) {
            guard renamingID == nil,
                  let id = model.selectedFragmentID,
                  let f = model.fragments.first(where: { $0.id == id })
            else { return .ignored }
            startRename(f)
            return .handled
        }
        .focusedSceneValue(\.deleteAction, deleteAction)
        .navigationTitle("Fragments")
    }

    private var deleteAction: (() -> Void)? {
        guard renamingID == nil,
              let id = model.selectedFragmentID,
              model.fragments.contains(where: { $0.id == id })
        else { return nil }
        return { model.deleteFragment(id) }
    }

    private func startRename(_ fragment: LocalFragment) {
        model.selectedFragmentID = fragment.id
        renameText = fragment.name
        renamingID = fragment.id
        renameFocus = fragment.id
    }

    private func createAndRename() {
        guard let id = model.createFragment(),
              let fragment = model.fragments.first(where: { $0.id == id }) else { return }
        renameText = fragment.name
        renamingID = id
        DispatchQueue.main.async { renameFocus = id }
    }

    private func commitRename() {
        guard let id = renamingID else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { model.renameFragment(id, to: trimmed) }
        renamingID = nil
    }
}
