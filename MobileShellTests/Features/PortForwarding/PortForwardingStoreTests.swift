import XCTest
@testable import MobileShell

final class PortForwardingStoreTests: XCTestCase {
    @MainActor
    func testStartingPortForwardUsesVaultRequestAndMarksRuleActive() async throws {
        let hostID = UUID(uuidString: "B0B0B0B0-1111-2222-3333-B0B0B0B0B0B0")!
        let knownHost = KnownHost(
            host: "[bastion.example.com]:2222",
            keyType: "ssh-ed25519",
            fingerprint: "SHA256:bastion"
        )
        let host = ShellHost(
            id: hostID,
            name: "bastion-prod",
            address: "bastion.example.com",
            port: 2222,
            username: "deploy",
            group: "Production",
            tags: ["ssh"],
            status: .idle
        )
        let rule = PortForwardRule(
            id: UUID(uuidString: "F0F0F0F0-1111-2222-3333-F0F0F0F0F0F0")!,
            name: "Postgres Tunnel",
            sshHostID: hostID,
            localPort: 15432,
            remoteHost: "127.0.0.1",
            remotePort: 5432,
            isActive: false
        )
        let credentialVault = InMemoryCredentialVault()
        try credentialVault.savePassword("tunnel-secret", forHostID: hostID)
        let portForwardingClient = RecordingPortForwardingClient()
        let store = MobileShellStore(
            hosts: [host],
            portForwardRules: [rule],
            knownHosts: [knownHost],
            credentialVault: credentialVault,
            portForwardingClient: portForwardingClient
        )

        await store.togglePortForwardRule(rule)

        XCTAssertTrue(try XCTUnwrap(store.portForwardRules.first { $0.id == rule.id }).isActive)
        XCTAssertNil(store.portForwardErrorMessage)
        XCTAssertEqual(portForwardingClient.startedRules, [rule])
        XCTAssertEqual(portForwardingClient.requests.first?.hostname, "bastion.example.com")
        XCTAssertEqual(portForwardingClient.requests.first?.port, 2222)
        XCTAssertEqual(portForwardingClient.requests.first?.password, "tunnel-secret")
        XCTAssertEqual(portForwardingClient.requests.first?.knownHosts, [knownHost])
        XCTAssertEqual(store.history.first, "Started port forward Postgres Tunnel")
    }

    @MainActor
    func testTrustingPortForwardHostKeyChallengeStoresFingerprintAndRetriesTunnelStart() async throws {
        let hostID = UUID(uuidString: "B0B0B0B0-4444-5555-6666-B0B0B0B0B0B0")!
        let host = ShellHost(
            id: hostID,
            name: "bastion-new",
            address: "new-bastion.example.com",
            port: 2222,
            username: "deploy",
            group: "Production",
            tags: ["ssh"],
            status: .idle
        )
        let rule = PortForwardRule(
            id: UUID(uuidString: "F0F0F0F0-4444-5555-6666-F0F0F0F0F0F0")!,
            name: "Admin Tunnel",
            sshHostID: hostID,
            localPort: 18443,
            remoteHost: "127.0.0.1",
            remotePort: 8443,
            isActive: false
        )
        let challenge = HostKeyChallenge(
            id: UUID(uuidString: "CDCDCDCD-1111-2222-3333-CDCDCDCDCDCD")!,
            hostname: "new-bastion.example.com",
            port: 2222,
            keyType: "ssh-ed25519",
            fingerprint: "SHA256:newbastion"
        )
        let credentialVault = InMemoryCredentialVault()
        try credentialVault.savePassword("tunnel-secret", forHostID: hostID)
        let portForwardingClient = RecordingPortForwardingClient(results: [
            .failure(challenge),
            .success(())
        ])
        let store = MobileShellStore(
            hosts: [host],
            portForwardRules: [rule],
            credentialVault: credentialVault,
            portForwardingClient: portForwardingClient
        )

        await store.togglePortForwardRule(rule)

        XCTAssertEqual(portForwardingClient.startedRules, [rule])
        XCTAssertEqual(store.pendingHostKeyChallenge, challenge)
        XCTAssertFalse(try XCTUnwrap(store.portForwardRules.first { $0.id == rule.id }).isActive)
        XCTAssertNil(store.portForwardErrorMessage)

        await store.trustPendingHostKey()

        XCTAssertNil(store.pendingHostKeyChallenge)
        XCTAssertEqual(portForwardingClient.startedRules, [rule, rule])
        XCTAssertEqual(portForwardingClient.requests.last?.knownHosts.first?.host, "[new-bastion.example.com]:2222")
        XCTAssertEqual(store.knownHosts.first?.knownHostLine, "[new-bastion.example.com]:2222 ssh-ed25519 SHA256:newbastion")
        XCTAssertTrue(try XCTUnwrap(store.portForwardRules.first { $0.id == rule.id }).isActive)
    }

    @MainActor
    func testStoppingActivePortForwardStopsSessionAndMarksRuleInactive() async throws {
        let hostID = UUID(uuidString: "B1B1B1B1-1111-2222-3333-B1B1B1B1B1B1")!
        let host = ShellHost(
            id: hostID,
            name: "api-prod",
            address: "api.example.com",
            username: "deploy",
            group: "Production",
            tags: ["ssh"],
            status: .idle
        )
        let rule = PortForwardRule(
            id: UUID(uuidString: "F1F1F1F1-1111-2222-3333-F1F1F1F1F1F1")!,
            name: "API Tunnel",
            sshHostID: hostID,
            localPort: 13001,
            remoteHost: "127.0.0.1",
            remotePort: 3000,
            isActive: false
        )
        let credentialVault = InMemoryCredentialVault()
        try credentialVault.savePassword("tunnel-secret", forHostID: hostID)
        let portForwardingClient = RecordingPortForwardingClient()
        let store = MobileShellStore(
            hosts: [host],
            portForwardRules: [rule],
            credentialVault: credentialVault,
            portForwardingClient: portForwardingClient
        )

        await store.togglePortForwardRule(rule)
        await store.togglePortForwardRule(rule)

        XCTAssertFalse(try XCTUnwrap(store.portForwardRules.first { $0.id == rule.id }).isActive)
        XCTAssertEqual(portForwardingClient.createdSessions.first?.stopCount, 1)
        XCTAssertNil(store.portForwardErrorMessage)
        XCTAssertEqual(store.history.first, "Stopped port forward API Tunnel")
    }

    @MainActor
    func testFailedPortForwardStartStoresErrorAndLeavesRuleInactive() async throws {
        let hostID = UUID(uuidString: "B2B2B2B2-1111-2222-3333-B2B2B2B2B2B2")!
        let host = ShellHost(
            id: hostID,
            name: "db-prod",
            address: "db.example.com",
            username: "deploy",
            group: "Production",
            tags: ["ssh"],
            status: .idle
        )
        let rule = PortForwardRule(
            id: UUID(uuidString: "F2F2F2F2-1111-2222-3333-F2F2F2F2F2F2")!,
            name: "Broken Tunnel",
            sshHostID: hostID,
            localPort: 15432,
            remoteHost: "127.0.0.1",
            remotePort: 5432,
            isActive: false
        )
        let credentialVault = InMemoryCredentialVault()
        try credentialVault.savePassword("tunnel-secret", forHostID: hostID)
        let portForwardingClient = RecordingPortForwardingClient(result: .failure(RecordingPortForwardingError.refused))
        let store = MobileShellStore(
            hosts: [host],
            portForwardRules: [rule],
            credentialVault: credentialVault,
            portForwardingClient: portForwardingClient
        )

        await store.togglePortForwardRule(rule)

        XCTAssertFalse(try XCTUnwrap(store.portForwardRules.first { $0.id == rule.id }).isActive)
        XCTAssertEqual(store.portForwardErrorMessage, "Port forward error: Tunnel fixture refused")
        XCTAssertTrue(store.history.isEmpty)
    }

    func testAddingPortForwardRuleTrimsFieldsAndStoresInactiveRule() throws {
        let hostID = UUID(uuidString: "B3B3B3B3-1111-2222-3333-B3B3B3B3B3B3")!
        let store = MobileShellStore(
            hosts: [
                ShellHost(
                    id: hostID,
                    name: "jump-box",
                    address: "jump.example.com",
                    username: "deploy",
                    group: "Production",
                    tags: ["ssh"],
                    status: .idle
                )
            ]
        )

        let rule = try XCTUnwrap(store.addPortForwardRule(
            name: "  Redis Tunnel  ",
            sshHostID: hostID,
            localPort: 16379,
            remoteHost: "  127.0.0.1  ",
            remotePort: 6379
        ))

        XCTAssertEqual(rule.name, "Redis Tunnel")
        XCTAssertEqual(rule.sshHostID, hostID)
        XCTAssertEqual(rule.localPort, 16379)
        XCTAssertEqual(rule.remoteHost, "127.0.0.1")
        XCTAssertEqual(rule.remotePort, 6379)
        XCTAssertFalse(rule.isActive)
        XCTAssertEqual(store.portForwardRules, [rule])
        XCTAssertNil(store.portForwardErrorMessage)
    }

    @MainActor
    func testUpdatingActivePortForwardRuleStopsCurrentSessionAndStoresEditedRule() async throws {
        let hostID = UUID(uuidString: "B4B4B4B4-1111-2222-3333-B4B4B4B4B4B4")!
        let host = ShellHost(
            id: hostID,
            name: "api-prod",
            address: "api.example.com",
            username: "deploy",
            group: "Production",
            tags: ["ssh"],
            status: .idle
        )
        let rule = PortForwardRule(
            id: UUID(uuidString: "F4F4F4F4-1111-2222-3333-F4F4F4F4F4F4")!,
            name: "API Tunnel",
            sshHostID: hostID,
            localPort: 13001,
            remoteHost: "127.0.0.1",
            remotePort: 3000,
            isActive: false
        )
        let credentialVault = InMemoryCredentialVault()
        try credentialVault.savePassword("tunnel-secret", forHostID: hostID)
        let portForwardingClient = RecordingPortForwardingClient()
        let store = MobileShellStore(
            hosts: [host],
            portForwardRules: [rule],
            credentialVault: credentialVault,
            portForwardingClient: portForwardingClient
        )

        await store.togglePortForwardRule(rule)
        let updatedRule = await store.updatePortForwardRule(
            rule,
            name: "  API Debug  ",
            sshHostID: hostID,
            localPort: 13002,
            remoteHost: " api.internal ",
            remotePort: 3001
        )
        let edited = try XCTUnwrap(updatedRule)

        XCTAssertEqual(portForwardingClient.createdSessions.first?.stopCount, 1)
        XCTAssertEqual(edited.id, rule.id)
        XCTAssertEqual(edited.name, "API Debug")
        XCTAssertEqual(edited.localPort, 13002)
        XCTAssertEqual(edited.remoteHost, "api.internal")
        XCTAssertEqual(edited.remotePort, 3001)
        XCTAssertFalse(edited.isActive)
        XCTAssertEqual(store.portForwardRules, [edited])
        XCTAssertEqual(store.history.first, "Updated port forward API Debug")
    }

    @MainActor
    func testDeletingActivePortForwardRuleStopsCurrentSessionAndRemovesRule() async throws {
        let hostID = UUID(uuidString: "B5B5B5B5-1111-2222-3333-B5B5B5B5B5B5")!
        let host = ShellHost(
            id: hostID,
            name: "db-prod",
            address: "db.example.com",
            username: "deploy",
            group: "Production",
            tags: ["ssh"],
            status: .idle
        )
        let rule = PortForwardRule(
            id: UUID(uuidString: "F5F5F5F5-1111-2222-3333-F5F5F5F5F5F5")!,
            name: "DB Tunnel",
            sshHostID: hostID,
            localPort: 15432,
            remoteHost: "127.0.0.1",
            remotePort: 5432,
            isActive: false
        )
        let credentialVault = InMemoryCredentialVault()
        try credentialVault.savePassword("tunnel-secret", forHostID: hostID)
        let portForwardingClient = RecordingPortForwardingClient()
        let store = MobileShellStore(
            hosts: [host],
            portForwardRules: [rule],
            credentialVault: credentialVault,
            portForwardingClient: portForwardingClient
        )

        await store.togglePortForwardRule(rule)
        await store.deletePortForwardRule(rule)

        XCTAssertEqual(portForwardingClient.createdSessions.first?.stopCount, 1)
        XCTAssertTrue(store.portForwardRules.isEmpty)
        XCTAssertNil(store.portForwardErrorMessage)
        XCTAssertEqual(store.history.first, "Deleted port forward DB Tunnel")
    }

    @MainActor
    func testStartingPortForwardWithoutLinkedHostIDFallsBackToMatchingHostAddress() async throws {
        let host = ShellHost(
            id: UUID(uuidString: "B6B6B6B6-1111-2222-3333-B6B6B6B6B6B6")!,
            name: "bastion-prod",
            address: "bastion.example.com",
            port: 2222,
            username: "deploy",
            group: "Production",
            tags: ["ssh"],
            status: .idle
        )
        let rule = PortForwardRule(
            id: UUID(uuidString: "F6F6F6F6-1111-2222-3333-F6F6F6F6F6F6")!,
            name: "Address Fallback",
            sshHostID: nil,
            localPort: 15432,
            remoteHost: "bastion.example.com",
            remotePort: 5432,
            isActive: false
        )
        let credentialVault = InMemoryCredentialVault()
        try credentialVault.savePassword("tunnel-secret", forHostID: host.id)
        let portForwardingClient = RecordingPortForwardingClient()
        let store = MobileShellStore(
            hosts: [host],
            portForwardRules: [rule],
            credentialVault: credentialVault,
            portForwardingClient: portForwardingClient
        )

        await store.togglePortForwardRule(rule)

        XCTAssertTrue(try XCTUnwrap(store.portForwardRules.first { $0.id == rule.id }).isActive)
        XCTAssertEqual(portForwardingClient.startedRules, [rule])
        XCTAssertEqual(portForwardingClient.requests.first?.hostname, "bastion.example.com")
        XCTAssertNil(store.portForwardErrorMessage)
    }

    @MainActor
    func testStartingPortForwardWithoutResolvableHostLeavesRuleInactive() async throws {
        let rule = PortForwardRule(
            id: UUID(uuidString: "F7F7F7F7-1111-2222-3333-F7F7F7F7F7F7")!,
            name: "Missing Host Tunnel",
            sshHostID: nil,
            localPort: 15432,
            remoteHost: "missing.example.com",
            remotePort: 5432,
            isActive: false
        )
        let portForwardingClient = RecordingPortForwardingClient()
        let store = MobileShellStore(
            hosts: [],
            portForwardRules: [rule],
            portForwardingClient: portForwardingClient
        )

        await store.togglePortForwardRule(rule)

        XCTAssertFalse(try XCTUnwrap(store.portForwardRules.first { $0.id == rule.id }).isActive)
        XCTAssertTrue(portForwardingClient.startedRules.isEmpty)
        XCTAssertEqual(store.portForwardErrorMessage, "Port forward error: No SSH host is linked to Missing Host Tunnel")
    }
}

enum RecordingPortForwardingError: LocalizedError {
    case refused

    var errorDescription: String? {
        switch self {
        case .refused:
            "Tunnel fixture refused"
        }
    }
}

final class RecordingPortForwardingSession: PortForwardingSession, @unchecked Sendable {
    private(set) var stopCount = 0

    func stop() async {
        stopCount += 1
    }
}

final class RecordingPortForwardingClient: PortForwardingClient, @unchecked Sendable {
    let results: [Result<Void, Error>]
    private var nextResultIndex = 0
    var startedRules: [PortForwardRule] = []
    var requests: [SSHConnectionRequest] = []
    var createdSessions: [RecordingPortForwardingSession] = []

    init(result: Result<Void, Error> = .success(()), results: [Result<Void, Error>]? = nil) {
        self.results = results ?? [result]
    }

    func start(rule: PortForwardRule, using request: SSHConnectionRequest) async throws -> any PortForwardingSession {
        startedRules.append(rule)
        requests.append(request)
        let result = results[min(nextResultIndex, results.count - 1)]
        nextResultIndex += 1
        switch result {
        case .success:
            let session = RecordingPortForwardingSession()
            createdSessions.append(session)
            return session
        case .failure(let error):
            throw error
        }
    }
}
