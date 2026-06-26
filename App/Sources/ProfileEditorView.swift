import SwiftUI
import HostsKit

struct ProfileEditorView: View {
    @Environment(AppModel.self) private var model
    let profileID: UUID
    var requestApply: () -> Void

    @State private var text: String = ""
    @State private var fragmentsExpanded = false
    @State private var sourcesExpanded = false

    private var profile: Profile? { model.profiles.first { $0.id == profileID } }
    private var isStale: Bool { model.staleProfileIDs.contains(profileID) }

    var body: some View {
        // Apply stays pinned below a scrollable body: expanding Fragments/Sources must never push it out of view.
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if isStale && profileID == model.activeProfileID {
                        Label("Active profile is out of date — Apply to update", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.orange).padding(8)
                        Divider()
                    }

                    TextEditor(text: $text)
                        .font(.system(.body, design: .monospaced))
                        .onChange(of: text) { _, new in model.updateContent(profileID, content: new) }
                        .frame(maxWidth: .infinity, minHeight: 220)
                        .padding(8)

                    if !model.fragments.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 10) {
                            sectionHeader("Fragments", expanded: $fragmentsExpanded)
                            if fragmentsExpanded {
                                VStack(spacing: 0) {
                                    ForEach(Array(model.fragments.enumerated()), id: \.element.id) { i, fragment in
                                        if i > 0 { rowDivider }
                                        toggleRow(fragment.name,
                                                  isOn: profile?.fragmentIDs.contains(fragment.id) ?? false) {
                                            toggleFragment(fragment.id, $0)
                                        }
                                    }
                                }
                            }
                        }.padding(8)
                    }

                    Divider()
                    VStack(alignment: .leading, spacing: 10) {
                        sectionHeader("Sources", expanded: $sourcesExpanded)
                        if sourcesExpanded {
                            VStack(spacing: 0) {
                                ForEach(Array(model.sources.enumerated()), id: \.element.id) { i, source in
                                    if i > 0 { rowDivider }
                                    toggleRow(source.name,
                                              isOn: profile?.sourceIDs.contains(source.id) ?? false) {
                                        toggle(source.id, $0)
                                    }
                                }
                            }
                        }
                    }.padding(8)

                    let warnings = (profile?.isProtected ?? false) ? [] : model.warnings(for: profileID)
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
                Button("Apply") { requestApply() }
                .buttonStyle(.borderedProminent)
                .help("Apply this profile")
                .disabled(model.isApplying || (profileID == model.activeProfileID && !isStale))
                Spacer()
            }
            .padding(8)
        }
        .onAppear { text = profile?.content ?? "" }
        .onChange(of: profileID) { _, _ in text = profile?.content ?? "" }
    }

    private func sectionHeader(_ title: String, expanded: Binding<Bool>) -> some View {
        Button {
            expanded.wrappedValue.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.caption).foregroundStyle(.secondary)
                    .rotationEffect(.degrees(expanded.wrappedValue ? 90 : 0))
                Text(title).fontWeight(.semibold)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggleRow(_ name: String, isOn: Bool, set: @escaping (Bool) -> Void) -> some View {
        HStack {
            Text(name)
            Spacer()
            Toggle("", isOn: Binding(get: { isOn }, set: set))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .accessibilityLabel(name)
        }
        .padding(.vertical, 9)
    }

    private var rowDivider: some View {
        Rectangle().fill(.quinary).frame(height: 1)
    }

    private func toggle(_ id: UUID, _ on: Bool) {
        guard var ids = profile?.sourceIDs else { return }
        if on { if !ids.contains(id) { ids.append(id) } }
        else { ids.removeAll { $0 == id } }
        model.setProfileSources(profileID, ids)
    }

    private func toggleFragment(_ id: UUID, _ on: Bool) {
        guard var ids = profile?.fragmentIDs else { return }
        if on { if !ids.contains(id) { ids.append(id) } }
        else { ids.removeAll { $0 == id } }
        model.setProfileFragments(profileID, ids)
    }
}
