import Foundation

enum JoinLinkParser {
    enum JoinLinkError: Error, Equatable {
        case invalidPath
        case invalidVersion
        case invalidMode
        case invalidHosts
        case invalidMinBuild
        case updateRequired(minBuild: Int)
    }

    static func parse(url: URL, currentBuild: Int) -> Result<JoinRequestV1, JoinLinkError> {
        guard url.path == "/join" else {
            return .failure(.invalidPath)
        }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return .failure(.invalidPath)
        }
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })

        guard query["v"] == "1" else {
            return .failure(.invalidVersion)
        }
        guard let mode = query["mode"], mode == "wifi" || mode == "nearby" else {
            return .failure(.invalidMode)
        }
        guard let hostsRaw = query["hosts"] else {
            return .failure(.invalidHosts)
        }

        let hostParts = hostsRaw.split(separator: ",").map { String($0) }
        guard !hostParts.isEmpty else {
            return .failure(.invalidHosts)
        }
        var hostUUIDs: [UUID] = []
        for part in hostParts {
            guard let uuid = UUID(uuidString: part) else {
                return .failure(.invalidHosts)
            }
            hostUUIDs.append(uuid)
        }

        var deviceNames: [String] = []
        if let namesRaw = query["device_names"] {
            let rawNames = namesRaw.split(separator: "|").map { String($0) }
            deviceNames = rawNames.map { raw in
                let decoded = raw.removingPercentEncoding ?? raw
                return String(decoded.prefix(40))
            }
        }
        if deviceNames.count > hostUUIDs.count {
            deviceNames = Array(deviceNames.prefix(hostUUIDs.count))
        }
        if deviceNames.count < hostUUIDs.count {
            for index in deviceNames.count..<hostUUIDs.count {
                deviceNames.append("Host \(index + 1)")
            }
        }
        for index in 0..<deviceNames.count where deviceNames[index].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            deviceNames[index] = "Host \(index + 1)"
        }

        let roomLabel: String?
        if let rawRoom = query["room_label"] {
            roomLabel = (rawRoom.removingPercentEncoding ?? rawRoom)
        } else {
            roomLabel = nil
        }

        var transportHint: String? = nil
        if let hint = query["transport_hint"], mode == "wifi", hint.lowercased() == "bonjour" {
            transportHint = "bonjour"
        }

        var minBuild: Int? = nil
        if let minBuildRaw = query["min_build"] {
            guard let parsed = Int(minBuildRaw) else {
                return .failure(.invalidMinBuild)
            }
            minBuild = parsed
            if currentBuild < parsed {
                return .failure(.updateRequired(minBuild: parsed))
            }
        }

        let request = JoinRequestV1(
            schemaVersion: 1,
            createdAt: Date().timeIntervalSince1970,
            requestId: UUID().uuidString,
            mode: mode,
            transportHint: transportHint,
            hostUUIDs: hostUUIDs,
            roomLabel: roomLabel,
            deviceNames: deviceNames,
            selectedHostUUID: nil,
            minBuild: minBuild,
            sourceURL: url.absoluteString
        )
        return .success(request)
    }
}
