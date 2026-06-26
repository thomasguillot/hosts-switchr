import SwiftUI
import HostsKit

struct SourceDetailView: View {
    @Environment(AppModel.self) private var model
    let sourceID: UUID

    private var source: RemoteSource? { model.sources.first { $0.id == sourceID } }

    var body: some View {
        if let source {
            VStack(alignment: .leading, spacing: 12) {
                Text(source.name).font(.title2).bold()
                Text(source.url.absoluteString)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary).textSelection(.enabled)
                if let err = source.lastError {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
                Spacer()
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ContentUnavailableView("No Source Selected", systemImage: "antenna.radiowaves.left.and.right")
        }
    }
}
