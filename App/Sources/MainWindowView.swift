import AppKit
import HostsKit
import SwiftUI
import UniformTypeIdentifiers

private let railWidth: CGFloat = 174

struct MainWindowView: View {
    @Environment(AppModel.self) private var model
    @Environment(WindowRouter.self) private var router
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var preview: PreviewData?
    @State private var pendingApplyID: UUID?
    @State private var previewToken = 0
    @State private var importSummary: AppModel.ImportSummary?
    @State private var selectedSourceID: UUID?
    @State private var showingAddSource = false

    // About and Settings are rail-plus-detail; the list column has nothing to show for them.
    private var isUtilitySection: Bool { router.section == .about || router.section == .settings }

    var body: some View {
        @Bindable var router = router
        return Group {
            if isUtilitySection {
                NavigationSplitView {
                    rail(selection: $router.section)
                } detail: {
                    detailColumn
                }
            } else {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    rail(selection: $router.section)
                } content: {
                    contentColumn
                        .navigationSplitViewColumnWidth(min: 200, ideal: 224, max: 400)
                } detail: {
                    detailColumn
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
                if isUtilitySection {
                    // Load-bearing, not filler: an empty toolbar is dropped entirely and the unified
                    // toolbar is what fuses the rail full height — but macOS platters every item, so
                    // any non-zero size renders as a hairline in the titlebar.
                    Color.clear.frame(width: 0, height: 0)
                } else {
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

    private func rail(selection: Binding<SidebarSection>) -> some View {
        List(selection: selection) {
            railItem(.profiles, "Profiles", "doc.text",
                     help: "Switchable /etc/hosts profiles")
            railItem(.fragments, "Fragments", "rectangle.stack",
                     help: "Reusable host snippets you toggle per profile")
            railItem(.sources, "Sources", "antenna.radiowaves.left.and.right",
                     help: "Subscribed remote blocklist / hosts sources")
        }
        .scrollContentBackground(.hidden)
        .toolbar(removing: .sidebarToggle)
        // Load-bearing: each swap builds a fresh NSSplitView and this re-pins its sidebar (min == max).
        .navigationSplitViewColumnWidth(railWidth)
        .safeAreaInset(edge: .bottom) {
            List(selection: selection) {
                railItem(.about, "About", "info.circle",
                         help: "Version and updates")
                railItem(.settings, "Settings", "gearshape",
                         help: "App preferences")
            }
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
            // Sized for two railItem rows at .title3; scrolling is off, so a taller row clips silently.
            .frame(height: 80)
        }
    }

    @ViewBuilder private var contentColumn: some View {
        switch router.section {
        case .profiles: ProfileSidebarView()
        case .sources: SourcesView(selectedSourceID: $selectedSourceID,
                                   onAddSource: { showingAddSource = true })
        case .fragments: FragmentsSidebarView()
        case .about: EmptyView()
        case .settings: EmptyView()
        }
    }

    @ViewBuilder private var detailColumn: some View {
        switch router.section {
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
                FragmentEditorView(fragmentID: id, requestApply: { requestPreview($0) })
            } else if !model.fragments.isEmpty {
                placeholder("No Fragment Selected", "rectangle.stack")
            }
        case .about: AboutView()
        case .settings: SettingsView()
        }
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
    // The rail width itself comes from navigationSplitViewColumnWidth; this pin only overrides restored state
    // on the window AppKit hands us at launch. The managing NSSplitViewController isn't in the view-controller
    // children tree — it's reachable via the NSSplitView's delegate.
    private func removeSeparators(_ window: NSWindow?) {
        guard let window else { return }
        window.titlebarSeparatorStyle = .none
        func walk(_ v: NSView) {
            if let split = v as? NSSplitView, let controller = split.delegate as? NSSplitViewController {
                for item in controller.splitViewItems {
                    item.titlebarSeparatorStyle = .none
                    if item.behavior == .sidebar {
                        item.minimumThickness = railWidth
                        item.maximumThickness = railWidth
                    }
                }
            }
            v.subviews.forEach(walk)
        }
        window.contentView.map(walk)
    }
}
