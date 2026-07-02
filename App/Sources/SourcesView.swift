import SwiftUI
import HostsKit

struct SourcesView: View {
    @Environment(AppModel.self) private var model
    @Binding var selectedSourceID: UUID?
    var onAddSource: () -> Void

    private var builtins: [RemoteSource] { model.sources.filter { $0.kind == .builtin } }
    private var customs: [RemoteSource] { model.sources.filter { $0.kind == .custom } }

    var body: some View {
        List(selection: $selectedSourceID) {
            sectionLabel("Built-in")
            ForEach(builtins) { sourceRow($0) }
            if !customs.isEmpty {
                sectionLabel("Your sources").padding(.top, 8)
                ForEach(customs) { sourceRow($0) }
                    .onMove { model.moveCustomSources(fromOffsets: $0, toOffset: $1) }
            }
            Button("Add Source") { onAddSource() }
                .buttonStyle(.bordered)
                .padding(.top, 8)
                .listRowSeparator(.hidden)
        }
        .focusedSceneValue(\.deleteAction, deleteAction)
        .navigationTitle("Sources")
    }

    private var deleteAction: (() -> Void)? {
        guard let id = selectedSourceID,
              let source = model.sources.first(where: { $0.id == id }),
              source.kind == .custom
        else { return nil }
        return { model.removeSource(id); selectedSourceID = nil }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.subheadline).fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .listRowSeparator(.hidden)
    }

    @ViewBuilder private func sourceRow(_ source: RemoteSource) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            nameLabel(source)
            Text(subtitle(source)).font(.caption).foregroundStyle(.secondary)
        }
        .tag(source.id)
        .contextMenu {
            Button("Refresh") { Task { await model.refreshSource(source.id) } }
            if source.kind == .custom {
                Button("Remove", role: .destructive) { model.removeSource(source.id) }
            }
        }
        .listRowSeparator(.hidden)
    }

    @ViewBuilder private func nameLabel(_ s: RemoteSource) -> some View {
        HStack(spacing: 4) {
            Text(s.name)
            if s.lastError != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private func subtitle(_ s: RemoteSource) -> String {
        var parts: [String] = []
        if let n = s.domainCount { parts.append("\(n) domains") }
        if let t = s.lastFetchedAt {
            let f = RelativeDateTimeFormatter()
            parts.append("updated \(f.localizedString(for: t, relativeTo: Date()))")
        } else {
            parts.append("never fetched")
        }
        return parts.joined(separator: " · ")
    }
}
