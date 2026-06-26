import AppKit
import HostsKit
import SwiftUI
import UniformTypeIdentifiers

enum SidebarSection: Hashable { case profiles, sources, fragments }

struct MainWindowView: View {
    @Environment(AppModel.self) private var model
    @State private var section: SidebarSection = .profiles
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var preview: PreviewData?
    @State private var pendingApplyID: UUID?
    @State private var previewToken = 0
    @State private var importSummary: AppModel.ImportSummary?
    @State private var selectedSourceID: UUID?
    @State private var showingAddSource = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $section) {
                railItem(.profiles, "Profiles", "doc.text",
                         help: "Switchable /etc/hosts profiles")
                railItem(.fragments, "Fragments", "rectangle.stack",
                         help: "Reusable host snippets you toggle per profile")
                railItem(.sources, "Sources", "antenna.radiowaves.left.and.right",
                         help: "Subscribed remote blocklist / hosts sources")
            }
            .scrollContentBackground(.hidden)
            .toolbar(removing: .sidebarToggle)
        } content: {
            Group {
                switch section {
                case .profiles: ProfileSidebarView()
                case .sources: SourcesView(selectedSourceID: $selectedSourceID,
                                           onAddSource: { showingAddSource = true })
                case .fragments: FragmentsSidebarView()
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 224, max: 400)
        } detail: {
            switch section {
            case .profiles:
                if let id = model.selectedProfileID {
                    ProfileEditorView(profileID: id, requestApply: { requestPreview(id) })
                } else {
                    placeholder("No Profile Selected", "doc.text")
                }
            case .sources:
                if let id = selectedSourceID, model.sources.contains(where: { $0.id == id }) {
                    SourceDetailView(sourceID: id)
                } else {
                    placeholder("No Source Selected", "antenna.radiowaves.left.and.right")
                }
            case .fragments:
                if let id = model.selectedFragmentID {
                    FragmentEditorView(fragmentID: id)
                } else if !model.fragments.isEmpty {
                    placeholder("No Fragment Selected", "rectangle.stack")
                }
            }
        }
        .sheet(item: Binding(get: { preview.map { PreviewItem(data: $0) } }, set: { if $0 == nil { preview = nil } })) { item in
            PreviewSheet(
                data: item.data,
                onApply: {
                    preview = nil
                    let id = pendingApplyID
                    pendingApplyID = nil
                    if let id { Task { await model.applyAsync(id) } }
                },
                onCancel: { preview = nil; pendingApplyID = nil })
        }
        .sheet(isPresented: $showingAddSource) { AddSourceSheet() }
        .alert("Error", isPresented: Binding(
            get: { model.lastError != nil },
            set: { if !$0 { model.lastError = nil } }
        )) {
            Button("OK") { model.lastError = nil }
        } message: { Text(model.lastError ?? "") }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Export Config…") { exportConfig() }
                    Button("Import Config…") { importConfig() }
                    Divider()
                    Button("Import Hosts File as Profile…") { importHostsFile(.profile) }
                    Button("Import Hosts File as Fragment…") { importHostsFile(.fragment) }
                } label: { Label("Import / Export", systemImage: "square.and.arrow.up.on.square") }
                .help("Import or export configuration")
            }
        }
        .onAppear { NSApp.setActivationPolicy(.regular) }
        .onDisappear { NSApp.setActivationPolicy(.accessory) }
        .alert("Import complete", isPresented: Binding(
            get: { importSummary != nil },
            set: { if !$0 { importSummary = nil } }
        )) {
            Button("OK") { importSummary = nil }
        } message: {
            if let s = importSummary {
                Text(summaryMessage(s))
            }
        }
        .background(WindowConfigurator())
    }

    private func railItem(_ tag: SidebarSection, _ title: String,
                          _ symbol: String, help: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.title3)
            .tag(tag)
            .help(help)
    }

    // Fixed-height icon box keeps the three "No … Selected" placeholders vertically aligned despite differing glyph heights.
    private func placeholder(_ title: String, _ symbol: String) -> some View {
        ContentUnavailableView {
            Label {
                Text(title)
            } icon: {
                Image(systemName: symbol)
                    .font(.system(size: 44))
                    .frame(height: 48)
            }
        }
    }

    private func exportConfig() {
        guard let data = model.exportConfigData() else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "HostsSwitchr-backup.json"
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            do { try data.write(to: url, options: .atomic) }
            catch { model.lastError = "Couldn't save backup: \(error.localizedDescription)" }
        }
    }

    private func importConfig() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let data: Data
        do { data = try Data(contentsOf: url) }
        catch { model.lastError = "Couldn't read backup: \(error.localizedDescription)"; return }
        let alert = NSAlert()
        alert.messageText = "Import configuration"
        alert.informativeText = "Merge adds items from the backup without touching what you have. Replace removes your current profiles, fragments, and custom sources first (System Default and built-in sources are kept)."
        alert.addButton(withTitle: "Merge")
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        let mode: ConfigBundle.ImportMode
        switch response {
        case .alertFirstButtonReturn: mode = .merge
        case .alertSecondButtonReturn: mode = .replace
        default: return
        }
        if let summary = model.importBundle(data, mode: mode) { importSummary = summary }
    }

    private func importHostsFile(_ kind: AppModel.HostsImportKind) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .data]   // permissive: Gas Mask hosts files often have no extension
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            model.importHostsFile(at: url, as: kind)
        }
    }

    private func summaryMessage(_ s: AppModel.ImportSummary) -> String {
        var parts = ["Added \(s.profilesAdded) profile(s), \(s.fragmentsAdded) fragment(s), \(s.sourcesAdded) source(s)."]
        if !s.warnings.isEmpty {
            parts.append("Skipped insecure (non-https) sources: \(s.warnings.joined(separator: ", ")).")
        }
        if s.skipped > 0 { parts.append("Skipped \(s.skipped) item(s) already present.") }
        return parts.joined(separator: "\n")
    }

    private func requestPreview(_ id: UUID) {
        pendingApplyID = id
        previewToken += 1
        let token = previewToken
        Task {
            let data = await model.previewData(for: id)
            if token == previewToken { preview = data }
        }
    }
}

private struct PreviewItem: Identifiable {
    let data: PreviewData
    var id: String { data.profileID.uuidString }
}

private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in removeSeparators(view?.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in removeSeparators(nsView?.window) }
    }

    // NavigationSplitView draws a titlebar separator per column; suppress the window's and every split item's.
    // SwiftUI's navigationSplitViewColumnWidth is only a preference that restored state overrides, so pin the
    // sidebar (rail) to a fixed thickness at the AppKit layer. The managing NSSplitViewController isn't in the
    // view-controller children tree — it's reachable via the NSSplitView's delegate.
    private func removeSeparators(_ window: NSWindow?) {
        guard let window else { return }
        window.titlebarSeparatorStyle = .none
        func walk(_ v: NSView) {
            if let split = v as? NSSplitView, let controller = split.delegate as? NSSplitViewController {
                for item in controller.splitViewItems {
                    item.titlebarSeparatorStyle = .none
                    if item.behavior == .sidebar {
                        item.minimumThickness = 174
                        item.maximumThickness = 174
                    }
                }
            }
            v.subviews.forEach(walk)
        }
        window.contentView.map(walk)
    }
}
