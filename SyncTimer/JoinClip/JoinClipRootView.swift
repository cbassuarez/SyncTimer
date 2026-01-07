import StoreKit
import SwiftUI
import UIKit

struct JoinClipRootView: View {
    let joinRequest: JoinRequestV1?
    let onInstall: (UUID?) -> Void
    let onSelectHost: (UUID) -> Void

    @State private var selectedHost: UUID? = nil

    var body: some View {
        VStack(spacing: 24) {
            if let request = joinRequest {
                VStack(spacing: 8) {
                    Text(request.roomLabel ?? "Join Session")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text(request.mode == "nearby" ? "Nearby" : "Wi-Fi")
                        .foregroundColor(.secondary)
                }

                if request.needsHostSelection {
                    List {
                        ForEach(hostRows, id: \.id) { row in
                            Button {
                                selectedHost = row.id
                                onSelectHost(row.id)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(row.name)
                                        Text(row.suffix)
                                            .font(.footnote)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if selectedHost == row.id {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.accentColor)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                } else if let row = hostRows.first {
                    VStack(spacing: 4) {
                        Text(row.name)
                        Text(row.suffix)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }

                Button("Install SyncTimer") {
                    onInstall(selectedHost)
                }
                .buttonStyle(.borderedProminent)
                .disabled(request.needsHostSelection && selectedHost == nil)
            } else {
                Text("Open a SyncTimer join link to continue.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .onChange(of: joinRequest?.requestId) { _ in
            selectedHost = joinRequest?.selectedHostUUID
        }
    }

    private var hostRows: [(id: UUID, name: String, suffix: String)] {
        guard let request = joinRequest else { return [] }
        return request.hostUUIDs.enumerated().map { index, uuid in
            let name = request.deviceNames.indices.contains(index) ? request.deviceNames[index] : "Host \(index + 1)"
            let suffix = "…\(uuid.uuidString.suffix(4))"
            return (id: uuid, name: name, suffix: suffix)
        }
    }

    static func presentInstallOverlay() {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            return
        }
        let configuration = SKOverlay.AppConfiguration(appIdentifier: "0000000000", position: .bottom)
        configuration.userDismissible = true
        SKOverlay.present(in: scene, configuration: configuration)
    }
}
