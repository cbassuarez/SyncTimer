import Foundation
import Testing
@testable import SyncTimer

struct JoinLinkParserTests {
    @Test func parseValidWifiLink() async throws {
        let host1 = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let host2 = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let url = URL(string: "https://synctimerapp.com/join?v=1&mode=wifi&hosts=\(host1.uuidString),\(host2.uuidString)&device_names=Main%20Host|Backup&room_label=Stage%20Left&transport_hint=bonjour&min_build=1")!

        let result = JoinLinkParser.parse(url: url, currentBuild: 99)
        switch result {
        case .success(let request):
            #expect(request.schemaVersion == 1)
            #expect(request.mode == "wifi")
            #expect(request.transportHint == "bonjour")
            #expect(request.hostUUIDs == [host1, host2])
            #expect(request.deviceNames == ["Main Host", "Backup"])
            #expect(request.roomLabel == "Stage Left")
            #expect(request.requestId.isEmpty == false)
            #expect(request.createdAt > 0)
            #expect(request.sourceURL == url.absoluteString)
        case .failure(let error):
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func parseInvalidMode() async throws {
        let host = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let url = URL(string: "https://synctimerapp.com/join?v=1&mode=invalid&hosts=\(host.uuidString)")!

        let result = JoinLinkParser.parse(url: url, currentBuild: 1)
        #expect(result == .failure(.invalidMode))
    }

    @Test func parseInvalidHosts() async throws {
        let url = URL(string: "https://synctimerapp.com/join?v=1&mode=wifi&hosts=not-a-uuid")!

        let result = JoinLinkParser.parse(url: url, currentBuild: 1)
        #expect(result == .failure(.invalidHosts))
    }

    @Test func parseUpdateRequired() async throws {
        let host = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let url = URL(string: "https://synctimerapp.com/join?v=1&mode=nearby&hosts=\(host.uuidString)&min_build=999")!

        let result = JoinLinkParser.parse(url: url, currentBuild: 1)
        #expect(result == .failure(.updateRequired(minBuild: 999)))
    }
}
