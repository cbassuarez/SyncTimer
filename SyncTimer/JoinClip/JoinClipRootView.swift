import SwiftUI

struct JoinClipRootView: View {
    @ObservedObject var viewModel: JoinClipViewModel

    var body: some View {
        VStack(spacing: 16) {
            if let req = viewModel.request {
                Text(req.roomLabel ?? "Join Session")
                    .font(.title2)
                    .bold()
                if req.needsHostSelection {
                    List(req.hostUUIDs.indices, id: \.self) { idx in
                        let uuid = req.hostUUIDs[idx]
                        let name = req.deviceNames[safe: idx] ?? "Host \(idx + 1)"
                        Button(action: {
                            viewModel.persistAndShowOverlay(selectedHost: uuid)
                        }) {
                            HStack {
                                Text(name)
                                Spacer()
                                Text(uuid.uuidString.suffix(4))
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } else {
                    Text(req.deviceNames.first ?? "Host")
                        .font(.headline)
                    Button("Install SyncTimer") {
                        viewModel.persistAndShowOverlay(selectedHost: req.selectedHostUUID ?? req.hostUUIDs.first)
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                ProgressView()
            }
        }
        .padding()
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
