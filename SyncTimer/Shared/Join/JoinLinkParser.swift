import Foundation

enum JoinLinkError: Error, Equatable {
    case invalidPath
    case invalidVersion
    case invalidMode
    case invalidHosts
    case updateRequired(minBuild: Int)
}

enum JoinLinkParser {
    static func parse(url: URL, currentBuild: Int) -> Result<JoinRequestV1, JoinLinkError> {
        guard url.path == "/join" else {
            return .failure(.invalidPath)
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return .failure(.invalidVersion)
        }

        var query: [String: String] = [:]
        components.queryItems?.forEach { item in
            if let value = item.value {
                query[item.name] = value
            }
        }

        guard query["v"] == "1" else {
            return .failure(.invalidVersion)
        }

        guard let mode = query["mode"], mode == "wifi" || mode == "nearby" else {
            return .failure(.invalidMode)
        }

        guard let hosts = query["hosts"] else {
            return .failure(.invalidHosts)
        }
        let hostUUIDs: [UUID] = hosts.split(separator: ",").compactMap { UUID(uuidString: String($0)) }
        guard !hostUUIDs.isEmpty, hostUUIDs.count == hosts.split(separator: ",").count else {
            return .failure(.invalidHosts)
        }

        let rawDeviceNames = (query["device_names"] ?? "").split(separator: "|").map { segment -> String in
            let decoded = segment.removingPercentEncoding ?? String(segment)
            let truncated = String(decoded.prefix(40))
            return truncated
        }
        var deviceNames: [String] = Array(rawDeviceNames.prefix(hostUUIDs.count))
        if deviceNames.count < hostUUIDs.count {
            for idx in deviceNames.count..<hostUUIDs.count {
                deviceNames.append("Host \(idx + 1)")
            }
        }

        let roomLabel = query["room_label"]?.removingPercentEncoding

        let transportHint: String?
        if let hint = query["transport_hint"], mode == "wifi", hint == "bonjour" {
            transportHint = hint
        } else {
            transportHint = nil
        }

        let minBuild: Int?
        if let minBuildStr = query["min_build"], let mb = Int(minBuildStr) {
            minBuild = mb
            if currentBuild < mb {
                return .failure(.updateRequired(minBuild: mb))
            }
        } else {
            minBuild = nil
        }

        let selectedHostUUID = query["selected_host"].flatMap { UUID(uuidString: $0) }

        let request = JoinRequestV1(
            schemaVersion: 1,
            createdAt: Date().timeIntervalSince1970,
            requestId: UUID().uuidString,
            mode: mode,
            transportHint: transportHint,
            hostUUIDs: hostUUIDs,
            roomLabel: roomLabel,
            deviceNames: deviceNames,
            selectedHostUUID: selectedHostUUID,
            minBuild: minBuild,
            sourceURL: url.absoluteString
        )

        return .success(request)
    }
}
