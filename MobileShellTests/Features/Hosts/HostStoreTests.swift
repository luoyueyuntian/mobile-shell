import XCTest
import Crypto
import NIOSSH
@testable import MobileShell

final class HostStoreTests: XCTestCase {
    func testPreviewHostsCanBeFilteredByNameAddressAndTags() throws {
        let store = MobileShellStore.preview()

        store.searchText = "prod"
        XCTAssertEqual(store.filteredHosts().map(\.name), ["acme-api-prod"])

        store.searchText = "10.24"
        XCTAssertEqual(store.filteredHosts().map(\.name), ["db-replica-eu"])

        store.searchText = "cache"
        XCTAssertEqual(store.filteredHosts().map(\.name), ["redis-cache-dev"])
    }

    func testAddHostStoresMoshProtocolAndConfiguration() throws {
        let store = MobileShellStore()

        try store.addHost(
            name: "lab-mosh",
            address: "lab.example.com",
            port: 22,
            username: "ops",
            group: "Lab",
            tags: "mosh,lab",
            password: "",
            protocol: .mosh,
            moshConfiguration: MoshHostConfiguration(
                udpPort: 60010,
                serverCommand: "mosh-server new -s",
                predictiveEcho: false,
                useExperimentalConnection: true
            )
        )

        let host = try XCTUnwrap(store.hosts.last)
        XCTAssertEqual(host.protocol, .mosh)
        XCTAssertEqual(host.moshConfiguration?.udpPort, 60010)
        XCTAssertEqual(host.moshConfiguration?.serverCommand, "mosh-server new -s")
        XCTAssertEqual(host.moshConfiguration?.predictiveEcho, false)
        XCTAssertEqual(host.moshConfiguration?.useExperimentalConnection, true)
    }

    func testAddMoshHostWithBlankTagsDefaultsToMoshTag() throws {
        let store = MobileShellStore()

        try store.addHost(
            name: "lab-mosh",
            address: "lab.example.com",
            port: 22,
            username: "ops",
            group: "Lab",
            tags: "",
            password: "",
            protocol: .mosh,
            moshConfiguration: .default
        )

        let host = try XCTUnwrap(store.hosts.last)
        XCTAssertEqual(host.protocol, .mosh)
        XCTAssertEqual(host.tags, ["mosh"])
    }

    func testUpdateHostCanSwitchBetweenSSHAndMoshProtocols() throws {
        let host = ShellHost(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            name: "api",
            address: "api.example.com",
            username: "deploy",
            group: "Production",
            tags: ["ssh"],
            status: .idle
        )
        let store = MobileShellStore(hosts: [host])

        let updated = try XCTUnwrap(store.updateHost(
            host,
            name: host.name,
            address: host.address,
            port: host.port,
            username: host.username,
            group: host.group,
            tags: host.tags.joined(separator: ","),
            password: "",
            protocol: .mosh,
            moshConfiguration: .default
        ))

        XCTAssertEqual(updated.protocol, .mosh)
        XCTAssertEqual(updated.moshConfiguration, .default)

        let switchedBack = try XCTUnwrap(store.updateHost(
            updated,
            name: updated.name,
            address: updated.address,
            port: updated.port,
            username: updated.username,
            group: updated.group,
            tags: updated.tags.joined(separator: ","),
            password: "",
            protocol: .ssh,
            moshConfiguration: nil
        ))

        XCTAssertEqual(switchedBack.protocol, .ssh)
        XCTAssertNil(switchedBack.moshConfiguration)
    }

    @MainActor
    func testUpdatingOpenSSHHostToMoshClosesTerminalSession() async throws {
        let hostID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let host = ShellHost(
            id: hostID,
            name: "edge",
            address: "edge.example.com",
            username: "deploy",
            group: "Production",
            tags: ["ssh"],
            status: .idle
        )
        let shellSession = RecordingTerminalShellSession(outputs: [])
        let store = MobileShellStore(
            hosts: [host],
            terminalShellClient: RecordingTerminalShellClient(result: .success(shellSession))
        )

        await store.openInteractiveTerminal(for: host)
        XCTAssertEqual(store.terminalSessions.count, 1)

        let updated = try XCTUnwrap(store.updateHost(
            host,
            name: host.name,
            address: host.address,
            port: host.port,
            username: host.username,
            group: host.group,
            tags: host.tags.joined(separator: ","),
            password: "",
            protocol: .mosh,
            moshConfiguration: .default
        ))

        XCTAssertEqual(updated.protocol, .mosh)
        XCTAssertTrue(store.terminalSessions.isEmpty)
        XCTAssertNil(store.selectedSessionID)

        await Task.yield()

        XCTAssertEqual(shellSession.closeCount, 1)
    }

    @MainActor
    func testAddHostTrimsFieldsAndSplitsTags() {
        let store = MobileShellStore.preview()

        store.addHost(
            name: "  staging-api  ",
            address: "  staging.internal  ",
            username: " deploy ",
            group: " Staging ",
            tags: " ssh, staging, api "
        )

        let added = store.hosts.last
        XCTAssertEqual(added?.name, "staging-api")
        XCTAssertEqual(added?.address, "staging.internal")
        XCTAssertEqual(added?.username, "deploy")
        XCTAssertEqual(added?.group, "Staging")
        XCTAssertEqual(added?.tags, ["ssh", "staging", "api"])
    }

    func testAddHostDefaultsToSSHPortAndParsesCustomPortFromAddress() {
        let store = MobileShellStore.preview()

        store.addHost(
            name: " staging-api ",
            address: " staging.internal:2222 ",
            username: " deploy ",
            group: " Staging ",
            tags: " ssh "
        )

        let customPortHost = store.hosts.last
        XCTAssertEqual(customPortHost?.address, "staging.internal")
        XCTAssertEqual(customPortHost?.port, 2222)
        XCTAssertEqual(customPortHost?.subtitle, "deploy, staging.internal:2222, ssh")

        store.addHost(
            name: " default-api ",
            address: " default.internal ",
            username: " deploy ",
            group: " Staging ",
            tags: " ssh "
        )

        XCTAssertEqual(store.hosts.last?.port, 22)
    }

    func testImportOpenSSHConfigCreatesHostsAndSkipsWildcardBlocks() throws {
        let existingHost = ShellHost(
            id: UUID(uuidString: "C0C0C0C0-1111-2222-3333-C0C0C0C0C0C0")!,
            name: "prod-api",
            address: "old.example.com",
            username: "deploy",
            group: "Production",
            tags: ["ssh"],
            status: .idle
        )
        let store = MobileShellStore(hosts: [existingHost])
        let config = """
        Host *
          User ignored
          Port 2200

        Host prod-api
          HostName api.example.com
          User deploy
          Port 2222

        Host db-replica db-report
          HostName db.internal
          User postgres

        Host *.internal
          User nobody
        """

        let imported = store.importOpenSSHConfig(config)

        XCTAssertEqual(imported.map(\.name), ["db-replica", "db-report"])
        XCTAssertEqual(imported.map(\.address), ["db.internal", "db.internal"])
        XCTAssertEqual(imported.map(\.username), ["postgres", "postgres"])
        XCTAssertEqual(imported.map(\.port), [22, 22])
        XCTAssertEqual(imported.map(\.group), ["Imported", "Imported"])
        XCTAssertEqual(imported.map(\.tags), [["ssh", "imported"], ["ssh", "imported"]])
        XCTAssertEqual(store.hosts.map(\.name), ["prod-api", "db-replica", "db-report"])
        XCTAssertEqual(store.history.first, "Imported 2 OpenSSH hosts")
    }

    func testUpdatingHostTrimsFieldsKeepsIDUpdatesPasswordAndOpenSession() throws {
        let hostID = UUID(uuidString: "C1C1C1C1-1111-2222-3333-C1C1C1C1C1C1")!
        let host = ShellHost(
            id: hostID,
            name: "old-api",
            address: "old.example.com",
            username: "deploy",
            group: "Production",
            tags: ["ssh"],
            status: .idle
        )
        let credentialVault = InMemoryCredentialVault()
        try credentialVault.savePassword("old-secret", forHostID: hostID)
        let store = MobileShellStore(hosts: [host], credentialVault: credentialVault)
        store.connect(to: host)

        let updated = try XCTUnwrap(store.updateHost(
            host,
            name: "  new-api  ",
            address: "  new.example.com  ",
            port: 2202,
            username: " admin ",
            group: " Staging ",
            tags: " ssh, staging ",
            password: "new-secret"
        ))

        XCTAssertEqual(updated.id, hostID)
        XCTAssertEqual(updated.name, "new-api")
        XCTAssertEqual(updated.address, "new.example.com")
        XCTAssertEqual(updated.port, 2202)
        XCTAssertEqual(updated.username, "admin")
        XCTAssertEqual(updated.group, "Staging")
        XCTAssertEqual(updated.tags, ["ssh", "staging"])
        XCTAssertEqual(store.hosts, [updated])
        XCTAssertEqual(try credentialVault.password(forHostID: hostID), "new-secret")
        XCTAssertEqual(store.terminalSessions.first?.hostName, "new-api")
        XCTAssertEqual(store.terminalSessions.first?.prompt, "admin@new-api:~$")
        XCTAssertEqual(store.history.first, "Updated host new-api")
    }

    @MainActor
    func testDeletingHostCleansCredentialsSessionsSFTPAndLinkedPortForwards() async throws {
        let hostID = UUID(uuidString: "C2C2C2C2-1111-2222-3333-C2C2C2C2C2C2")!
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
            id: UUID(uuidString: "D2D2D2D2-1111-2222-3333-D2D2D2D2D2D2")!,
            name: "DB Tunnel",
            sshHostID: hostID,
            localPort: 15432,
            remoteHost: "127.0.0.1",
            remotePort: 5432,
            isActive: false
        )
        let credentialVault = InMemoryCredentialVault()
        try credentialVault.savePassword("db-secret", forHostID: hostID)
        let portForwardingClient = RecordingPortForwardingClient()
        let store = MobileShellStore(
            hosts: [host],
            portForwardRules: [rule],
            credentialVault: credentialVault,
            portForwardingClient: portForwardingClient
        )
        store.connect(to: host)
        store.selectedSFTPHostID = hostID
        store.sftpItems = [SFTPItem(id: UUID(), name: "dump.sql", kind: "text", size: "12 KB")]

        await store.togglePortForwardRule(rule)
        await store.deleteHost(host)

        XCTAssertTrue(store.hosts.isEmpty)
        XCTAssertNil(try credentialVault.password(forHostID: hostID))
        XCTAssertTrue(store.terminalSessions.isEmpty)
        XCTAssertNil(store.selectedSessionID)
        XCTAssertNil(store.selectedSFTPHostID)
        XCTAssertTrue(store.sftpItems.isEmpty)
        XCTAssertTrue(store.portForwardRules.isEmpty)
        XCTAssertEqual(portForwardingClient.createdSessions.first?.stopCount, 1)
        XCTAssertEqual(store.history.first, "Deleted host db-prod")
    }

    func testHostKeyPolicyTrustsMatchingFingerprintAndRejectsMismatch() throws {
        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(repeating: 7, count: 32))
        let publicKey = NIOSSHPrivateKey(ed25519Key: privateKey).publicKey
        let fingerprint = sshSHA256Fingerprint(for: publicKey)
        let policy = SSHHostKeyPolicy(
            hostname: "api.example.com",
            port: 22,
            knownHosts: [
                KnownHost(host: "api.example.com", keyType: "ssh-ed25519", fingerprint: fingerprint)
            ]
        )

        XCTAssertEqual(sshKeyType(for: publicKey), "ssh-ed25519")
        XCTAssertTrue(policy.trusts(keyType: "ssh-ed25519", fingerprint: fingerprint))
        XCTAssertFalse(policy.trusts(keyType: "ssh-ed25519", fingerprint: "SHA256:mismatch"))
    }

    func testHostKeyPolicyChallengesFirstUseWhenNoKnownHostMatches() throws {
        let policy = SSHHostKeyPolicy(
            hostname: "new.example.com",
            port: 22,
            knownHosts: [
                KnownHost(host: "api.example.com", keyType: "ssh-ed25519", fingerprint: "SHA256:api")
            ]
        )

        let evaluation = policy.evaluate(keyType: "ssh-ed25519", fingerprint: "SHA256:new")
        let challenge = try XCTUnwrap(evaluation.hostKeyChallenge)
        XCTAssertEqual(challenge.hostname, "new.example.com")
        XCTAssertEqual(challenge.port, 22)
        XCTAssertEqual(challenge.keyType, "ssh-ed25519")
        XCTAssertEqual(challenge.fingerprint, "SHA256:new")
        XCTAssertEqual(challenge.knownHostLine, "new.example.com ssh-ed25519 SHA256:new")
    }

    func testUpdatingHostCanAttachSSHKeyAndConnectionRequestUsesIt() throws {
        let hostID = UUID(uuidString: "33333333-3434-5656-7878-909090909090")!
        let keyID = UUID(uuidString: "43434343-3434-5656-7878-909090909090")!
        let host = ShellHost(
            id: hostID,
            name: "api",
            address: "api.example.com",
            username: "deploy",
            group: "Production",
            tags: ["ssh"],
            status: .idle
        )
        let credentialVault = InMemoryCredentialVault()
        try credentialVault.savePrivateKey("attached-private-key", forKeyID: keyID)
        let key = SSHKey(
            id: keyID,
            name: "Device Key",
            fingerprint: "SHA256:test",
            kind: "ed25519"
        )
        let store = MobileShellStore(hosts: [host], keys: [key], credentialVault: credentialVault)

        let updated = try XCTUnwrap(store.updateHost(
            host,
            name: "api",
            address: "api.example.com",
            port: 22,
            username: "deploy",
            group: "Production",
            tags: "ssh",
            password: "",
            sshKeyID: keyID
        ))
        let request = try SSHConnectionRequestBuilder(credentialVault: credentialVault).request(for: updated)

        XCTAssertEqual(updated.sshKeyID, keyID)
        XCTAssertEqual(request.privateKey, "attached-private-key")
    }
}
