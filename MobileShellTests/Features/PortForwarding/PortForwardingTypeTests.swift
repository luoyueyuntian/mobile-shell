import XCTest
@testable import MobileShell

final class PortForwardingTypeTests: XCTestCase {
    func testLegacyPortForwardRuleDecodesAsLocalLoopbackRule() throws {
        let legacyJSON = """
        {
          "id" : "11111111-2222-3333-4444-555555555555",
          "name" : "Legacy DB Tunnel",
          "sshHostID" : "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
          "localPort" : 15432,
          "remoteHost" : "127.0.0.1",
          "remotePort" : 5432,
          "isActive" : true
        }
        """

        let rule = try JSONDecoder().decode(PortForwardRule.self, from: Data(legacyJSON.utf8))

        XCTAssertEqual(rule.kind, .local)
        XCTAssertEqual(rule.localHost, "127.0.0.1")
        XCTAssertEqual(rule.routeSummary, "127.0.0.1:15432 -> 127.0.0.1:5432")
        XCTAssertFalse(rule.isActive)
    }

    func testAddingRemotePortForwardRuleStoresTypedEndpointsInactive() throws {
        let hostID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-000000000001")!
        let store = MobileShellStore(hosts: [
            ShellHost(
                id: hostID,
                name: "bastion",
                address: "bastion.example.com",
                username: "deploy",
                group: "Production",
                tags: ["ssh"],
                status: .idle
            )
        ])

        let rule = try XCTUnwrap(store.addPortForwardRule(
            kind: .remote,
            name: "  Webhook Reverse Tunnel  ",
            sshHostID: hostID,
            localHost: "  127.0.0.1  ",
            localPort: 3000,
            remoteHost: "  0.0.0.0  ",
            remotePort: 18080
        ))

        XCTAssertEqual(rule.kind, .remote)
        XCTAssertEqual(rule.name, "Webhook Reverse Tunnel")
        XCTAssertEqual(rule.localHost, "127.0.0.1")
        XCTAssertEqual(rule.localPort, 3000)
        XCTAssertEqual(rule.remoteHost, "0.0.0.0")
        XCTAssertEqual(rule.remotePort, 18080)
        XCTAssertFalse(rule.isActive)
        XCTAssertEqual(rule.routeSummary, "0.0.0.0:18080 -> 127.0.0.1:3000")
    }

    @MainActor
    func testStartingRemotePortForwardUsesTypedRuleAndMarksItActive() async throws {
        let hostID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-000000000002")!
        let host = ShellHost(
            id: hostID,
            name: "bastion",
            address: "bastion.example.com",
            username: "deploy",
            group: "Production",
            tags: ["ssh"],
            status: .idle
        )
        let rule = PortForwardRule(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-000000000003")!,
            kind: .remote,
            name: "Webhook Reverse Tunnel",
            sshHostID: hostID,
            localHost: "127.0.0.1",
            localPort: 3000,
            remoteHost: "0.0.0.0",
            remotePort: 18080,
            isActive: false
        )
        let vault = InMemoryCredentialVault()
        try vault.savePassword("secret", forHostID: hostID)
        let client = RecordingTypedPortForwardingClient()
        let store = MobileShellStore(
            hosts: [host],
            portForwardRules: [rule],
            credentialVault: vault,
            portForwardingClient: client
        )

        await store.togglePortForwardRule(rule)

        XCTAssertTrue(try XCTUnwrap(store.portForwardRules.first { $0.id == rule.id }).isActive)
        XCTAssertEqual(client.startedRules, [rule])
        XCTAssertEqual(client.requests.first?.hostname, "bastion.example.com")
        XCTAssertNil(store.portForwardErrorMessage)
    }

    @MainActor
    func testStartingDynamicPortForwardUsesTypedRuleAndMarksItActive() async throws {
        let hostID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-000000000004")!
        let host = ShellHost(
            id: hostID,
            name: "bastion",
            address: "bastion.example.com",
            username: "deploy",
            group: "Production",
            tags: ["ssh"],
            status: .idle
        )
        let rule = PortForwardRule(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-000000000005")!,
            kind: .dynamic,
            name: "SOCKS Proxy",
            sshHostID: hostID,
            localHost: "127.0.0.1",
            localPort: 1080,
            remoteHost: "",
            remotePort: 0,
            isActive: false
        )
        let vault = InMemoryCredentialVault()
        try vault.savePassword("secret", forHostID: hostID)
        let client = RecordingTypedPortForwardingClient()
        let store = MobileShellStore(
            hosts: [host],
            portForwardRules: [rule],
            credentialVault: vault,
            portForwardingClient: client
        )

        await store.togglePortForwardRule(rule)

        XCTAssertTrue(try XCTUnwrap(store.portForwardRules.first { $0.id == rule.id }).isActive)
        XCTAssertEqual(client.startedRules, [rule])
        XCTAssertEqual(client.requests.first?.hostname, "bastion.example.com")
        XCTAssertNil(store.portForwardErrorMessage)
    }
}

private final class RecordingTypedPortForwardingClient: PortForwardingClient, @unchecked Sendable {
    var startedRules: [PortForwardRule] = []
    var requests: [SSHConnectionRequest] = []
    var sessions: [RecordingTypedPortForwardingSession] = []

    func start(rule: PortForwardRule, using request: SSHConnectionRequest) async throws -> any PortForwardingSession {
        startedRules.append(rule)
        requests.append(request)
        let session = RecordingTypedPortForwardingSession()
        sessions.append(session)
        return session
    }
}

private final class RecordingTypedPortForwardingSession: PortForwardingSession, @unchecked Sendable {
    private(set) var stopCount = 0

    func stop() async {
        stopCount += 1
    }
}
