import SwiftUI
import HostsKit

struct ProfileSidebarView: View {
    @Environment(AppModel.self) private var model
    @State private var renamingID: UUID?
    @State private var renameText: String = ""
    @FocusState private var renameFocus: UUID?

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selectedProfileID) {
            ForEach(model.profiles) { profile in
                HStack {
                    let isActive = profile.id == model.activeProfileID
                    Image(systemName: "checkmark")
                        .opacity(isActive ? 1 : 0)
                        .accessibilityLabel("Active")
                        .accessibilityHidden(!isActive)
                    if renamingID == profile.id {
                        TextField("Name", text: $renameText)
                            .textFieldStyle(.plain)
                            .focused($renameFocus, equals: profile.id)
                            .onSubmit { commitRename() }
                            .onExitCommand { renamingID = nil }
                    } else {
                        Text(profile.name)
                    }
                    if model.staleProfileIDs.contains(profile.id) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    if profile.isProtected { Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary) }
                }
                .tag(profile.id)
                .contextMenu {
                    Button("Apply") {
                        model.selectedProfileID = profile.id
                        Task { await model.applyAsync(profile.id) }
                    }.disabled(model.isApplying || (profile.id == model.activeProfileID && !model.staleProfileIDs.contains(profile.id)))
                    Divider()
                    Button("Rename") { startRename(profile) }
                        .disabled(profile.isProtected)
                    Button("Duplicate") { model.selectedProfileID = profile.id; model.duplicateSelected() }
                    Button("Delete", role: .destructive) {
                        model.selectedProfileID = profile.id; model.deleteSelected()
                    }.disabled(profile.isProtected || profile.id == model.activeProfileID)
                }
                .listRowSeparator(.hidden)
                .moveDisabled(profile.isProtected)
            }
            .onMove { model.moveProfiles(fromOffsets: $0, toOffset: $1) }
            Button("Add Profile") { createAndRename() }
                .buttonStyle(.bordered)
                .padding(.top, 8)
                .listRowSeparator(.hidden)
        }
        .onChange(of: renameFocus) { _, new in if new == nil, renamingID != nil { commitRename() } }
        .onKeyPress(.return) {
            guard renamingID == nil,
                  let id = model.selectedProfileID,
                  let p = model.profiles.first(where: { $0.id == id }), !p.isProtected
            else { return .ignored }
            startRename(p)
            return .handled
        }
        .focusedSceneValue(\.deleteAction, deleteAction)
        .navigationTitle("Profiles")
    }

    private var deleteAction: (() -> Void)? {
        guard renamingID == nil,
              let id = model.selectedProfileID,
              let profile = model.profiles.first(where: { $0.id == id }),
              !profile.isProtected, id != model.activeProfileID
        else { return nil }
        return { model.deleteSelected() }
    }

    private func startRename(_ profile: Profile) {
        model.selectedProfileID = profile.id
        renameText = profile.name
        renamingID = profile.id
        renameFocus = profile.id
    }

    private func createAndRename() {
        guard let id = model.createProfile(),
              let profile = model.profiles.first(where: { $0.id == id }) else { return }
        renameText = profile.name
        renamingID = id
        DispatchQueue.main.async { renameFocus = id }
    }

    private func commitRename() {
        guard let id = renamingID else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { model.rename(id, to: trimmed) }
        renamingID = nil
    }
}
