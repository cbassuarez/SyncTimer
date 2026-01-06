import XCTest
@testable import SyncTimer

final class JoinLinkParserTests: XCTestCase {
    func testParsesWifiSingleHost() {
        let host = UUID()
        let url = URL(string: "https://synctimerapp.com/join?v=1&mode=wifi&hosts=\(host.uuidString)&device_names=Alpha&room_label=Room")!
        let result = JoinLinkParser.parse(url: url, currentBuild: 100)

        switch result {
        case .success(let req):
            XCTAssertEqual(req.mode, "wifi")
            XCTAssertEqual(req.hostUUIDs, [host])
            XCTAssertEqual(req.deviceNames.first, "Alpha")
            XCTAssertEqual(req.roomLabel, "Room")
            XCTAssertFalse(req.needsHostSelection)
        default:
            XCTFail("Expected success")
        }
    }

    func testParsesWifiMultiHostPadsNames() {
        let hosts = [UUID(), UUID()]
        let url = URL(string: "https://synctimerapp.com/join?v=1&mode=wifi&hosts=\(hosts[0].uuidString),\(hosts[1].uuidString)&device_names=One|Two|Three&transport_hint=bonjour")!
        let result = JoinLinkParser.parse(url: url, currentBuild: 100)

        switch result {
        case .success(let req):
            XCTAssertEqual(req.hostUUIDs, hosts)
            XCTAssertEqual(req.deviceNames.count, 2)
            XCTAssertEqual(req.deviceNames[0], "One")
            XCTAssertEqual(req.deviceNames[1], "Two")
            XCTAssertTrue(req.needsHostSelection)
            XCTAssertEqual(req.transportHint, "bonjour")
        default:
            XCTFail("Expected success")
        }
    }

    func testParsesNearbySingleHost() {
        let host = UUID()
        let url = URL(string: "https://synctimerapp.com/join?v=1&mode=nearby&hosts=\(host.uuidString)")!
        let result = JoinLinkParser.parse(url: url, currentBuild: 100)

        switch result {
        case .success(let req):
            XCTAssertEqual(req.mode, "nearby")
            XCTAssertEqual(req.hostUUIDs, [host])
            XCTAssertNil(req.transportHint)
        default:
            XCTFail("Expected success")
        }
    }

    func testInvalidVersionFails() {
        let url = URL(string: "https://synctimerapp.com/join?v=2&mode=wifi&hosts=\(UUID().uuidString)")!
        let result = JoinLinkParser.parse(url: url, currentBuild: 100)

        switch result {
        case .failure(let error):
            XCTAssertEqual(error, .invalidVersion)
        default:
            XCTFail("Expected invalid version failure")
        }
    }

    func testInvalidHostFails() {
        let url = URL(string: "https://synctimerapp.com/join?v=1&mode=wifi&hosts=not-a-uuid")!
        let result = JoinLinkParser.parse(url: url, currentBuild: 100)

        switch result {
        case .failure(let error):
            XCTAssertEqual(error, .invalidHosts)
        default:
            XCTFail("Expected invalid host failure")
        }
    }

    func testMissingModeFails() {
        let url = URL(string: "https://synctimerapp.com/join?v=1&hosts=\(UUID().uuidString)")!
        let result = JoinLinkParser.parse(url: url, currentBuild: 100)

        switch result {
        case .failure(let error):
            XCTAssertEqual(error, .invalidMode)
        default:
            XCTFail("Expected invalid mode failure")
        }
    }

    func testUpdateRequired() {
        let url = URL(string: "https://synctimerapp.com/join?v=1&mode=wifi&hosts=\(UUID().uuidString)&min_build=200")!
        let result = JoinLinkParser.parse(url: url, currentBuild: 100)

        switch result {
        case .failure(let error):
            XCTAssertEqual(error, .updateRequired(minBuild: 200))
        default:
            XCTFail("Expected update required failure")
        }
    }
}
