import SwiftUI
import HostsKit

struct PreviewSheet: View {
    let data: PreviewData
    let onApply: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Apply \u{201C}\(data.profileName)\u{201D}").font(.headline)

            if data.addedLocal.isEmpty && data.removedLocal.isEmpty {
                Text("No local entry changes.").font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Local entries").font(.caption).foregroundStyle(.secondary)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(data.removedLocal, id: \.self) { Text("- \($0)").foregroundStyle(.red) }
                            if data.removedOverflow > 0 {
                                Text("…and \(data.removedOverflow) more removed").foregroundStyle(.red.opacity(0.7))
                            }
                            ForEach(data.addedLocal, id: \.self) { Text("+ \($0)").foregroundStyle(.green) }
                            if data.addedOverflow > 0 {
                                Text("…and \(data.addedOverflow) more added").foregroundStyle(.green.opacity(0.7))
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxHeight: 180)
                }.font(.system(.caption, design: .monospaced))
            }

            Divider()
            VStack(alignment: .leading, spacing: 2) {
                Text("Blocklists").font(.caption).foregroundStyle(.secondary)
                ForEach(data.stats.perSource, id: \.name) { s in
                    Text("\(s.name)  —  \(s.domains) domains").font(.caption)
                }
                Text("Total: ~\(data.stats.totalDomains) null-routed domains")
                    .font(.caption).bold()
            }

            if !data.missingSources.isEmpty {
                Label("Not downloaded yet: \(data.missingSources.joined(separator: ", ")). Refresh sources first.",
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Apply", action: onApply).keyboardShortcut(.defaultAction)
                    .disabled(!data.missingSources.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
