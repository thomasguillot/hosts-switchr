import AppKit
import HostsKit
import SwiftUI

/// Hosts the update window. An AppKit shell rather than a SwiftUI `Window` scene
/// because a background check has to be able to open it with no other UI on
/// screen — `openWindow` is only reachable from a live view.
@MainActor
final class UpdateWindowController: NSObject, NSWindowDelegate {
    static let shared = UpdateWindowController()

    private var window: NSWindow?
    private weak var controller: UpdateController?

    func show(controller: UpdateController) {
        self.controller = controller
        if let window {
            NSApplication.shared.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let hosting = NSHostingView(rootView: UpdateWindowView().environment(controller))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "Software Update"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.delegate = self
        window.center()
        self.window = window
        // Accessory app: windows open behind the frontmost app without this.
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close() { window?.close() }

    func windowWillClose(_ notification: Notification) {
        controller?.windowClosed()
        window = nil
    }
}

struct UpdateWindowView: View {
    @Environment(UpdateController.self) private var update

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            notes
            Divider()
            footer
        }
        .frame(width: 480, height: 520)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable().frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text("A new version of Hosts Switchr is available")
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
    }

    private var subtitle: String {
        let available = update.plan.map { "Hosts Switchr \(update.displayVersion($0.version)) is available" }
            ?? "An update is available"
        return "\(available) — you have \(update.currentDisplayVersion)."
    }

    private var notes: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array((update.plan?.notes ?? []).enumerated()), id: \.offset) { index, note in
                    if index > 0 { Divider().padding(.vertical, 14) }
                    ReleaseNoteSection(note: note, showVersionHeading: (update.plan?.notes.count ?? 0) > 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    @ViewBuilder
    private var footer: some View {
        switch update.state {
        case .downloading(let received, let total):
            VStack(spacing: 10) {
                if total > 0 {
                    ProgressView(value: Double(received), total: Double(total))
                } else {
                    ProgressView().progressViewStyle(.linear)
                }
                HStack {
                    Text(Self.byteProgress(received: received, total: total))
                        .font(.caption).foregroundStyle(.secondary)
                        .monospacedDigit()
                    Spacer()
                    Button("Cancel") { update.cancelDownload() }
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding(20)

        case .readyToInstall:
            HStack {
                Spacer()
                Button("Install and Relaunch") { update.installAndRelaunch() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)

        case .failed(let message):
            VStack(alignment: .leading, spacing: 10) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("Close") { update.dismissWindow() }
                        .keyboardShortcut(.cancelAction)
                    Button("Try Again") { update.startDownload() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)

        default:
            HStack {
                Button("Skip This Version") { update.skipThisVersion() }
                Spacer()
                Button("Later") { update.dismissWindow() }
                    .keyboardShortcut(.cancelAction)
                Button("Install Update") { update.startDownload() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
    }

    private static func byteProgress(received: Int, total: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        // Otherwise a not-yet-started download reads "Zero KB of 769 KB".
        formatter.allowsNonnumericFormatting = false
        let got = formatter.string(fromByteCount: Int64(received))
        guard total > 0 else { return got }
        return "\(got) of \(formatter.string(fromByteCount: Int64(total)))"
    }
}

private struct ReleaseNoteSection: View {
    let note: ReleaseNote
    let showVersionHeading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showVersionHeading {
                Text("Version \(note.version)")
                    .font(.headline)
                    .padding(.bottom, 2)
            }
            ForEach(Array(note.blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case let .heading(level, text):
                    Text(text)
                        .font(level <= 2 ? .subheadline.bold() : .callout.bold())
                        .padding(.top, 6)
                case let .bullet(text):
                    HStack(alignment: .top, spacing: 8) {
                        Text("•").foregroundStyle(.secondary)
                        Text(inline(text)).fixedSize(horizontal: false, vertical: true)
                    }
                case let .paragraph(text):
                    Text(inline(text)).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Release bodies are our own markdown; on a parse failure show the raw text
    // rather than dropping the line.
    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}
