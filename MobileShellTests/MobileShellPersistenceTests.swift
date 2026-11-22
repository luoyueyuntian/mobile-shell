import XCTest
@testable import MobileShell

final class MobileShellPersistenceTests: XCTestCase {
    func testHostRepositoryRoundTripsHostConfigurationWithoutCredentials() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = JSONHostRepository(fileURL: directory.appendingPathComponent("vault.json"))
        let host = ShellHost(
            id: UUID(uuidString: "12345678-1234-1234-1234-123456789ABC")!,
            name: "edge-prod",
            address: "edge.example.com",
            username: "deploy",
            group: "Production",
            tags: ["ssh", "edge"],
            status: .locked
        )
        let snapshot = HostPersistenceSnapshot(hosts: [host])

        try repository.save(snapshot)
        let loaded = try repository.load()

        XCTAssertEqual(loaded.hosts, [host])
        let rawJSON = try String(contentsOf: repository.fileURL, encoding: .utf8)
        XCTAssertFalse(rawJSON.localizedCaseInsensitiveContains("password"))
        XCTAssertFalse(rawJSON.localizedCaseInsensitiveContains("secret"))
    }

    func testCredentialVaultStoresPasswordSeparatelyFromHostJSON() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = JSONHostRepository(fileURL: directory.appendingPathComponent("vault.json"))
        let credentialVault = InMemoryCredentialVault()
        let host = ShellHost(
            id: UUID(uuidString: "ABCDEFAB-CDEF-CDEF-CDEF-ABCDEFABCDEF")!,
            name: "jump-box",
            address: "jump.example.com",
            username: "ops",
            group: "Shared",
            tags: ["ssh", "jump"],
            status: .idle
        )

        try repository.save(HostPersistenceSnapshot(hosts: [host]))
        try credentialVault.savePassword("super-secret-password", forHostID: host.id)

        XCTAssertEqual(try credentialVault.password(forHostID: host.id), "super-secret-password")
        let rawJSON = try String(contentsOf: repository.fileURL, encoding: .utf8)
        XCTAssertFalse(rawJSON.contains("super-secret-password"))
    }

    func testStoreLoadsPersistedHostsWhenRepositoryHasData() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = JSONHostRepository(fileURL: directory.appendingPathComponent("vault.json"))
        let host = ShellHost(
            id: UUID(uuidString: "BBBBBBBB-1111-2222-3333-BBBBBBBBBBBB")!,
            name: "restored-host",
            address: "restored.internal",
            username: "root",
            group: "Restored",
            tags: ["ssh"],
            status: .idle
        )
        try repository.save(HostPersistenceSnapshot(hosts: [host]))

        let store = try MobileShellStore(repository: repository, credentialVault: InMemoryCredentialVault())

        XCTAssertEqual(store.hosts, [host])
    }

    func testStorePersistsAddedHostAndPasswordThroughSeparateStores() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = JSONHostRepository(fileURL: directory.appendingPathComponent("vault.json"))
        let credentialVault = InMemoryCredentialVault()
        let store = try MobileShellStore(repository: repository, credentialVault: credentialVault)

        try store.addHost(
            name: " secure-api ",
            address: " secure.example.com ",
            port: 2202,
            username: " deploy ",
            group: " Production ",
            tags: " ssh, api ",
            password: "not-in-json"
        )

        let restored = try repository.load().hosts.last
        XCTAssertEqual(restored?.name, "secure-api")
        XCTAssertEqual(restored?.address, "secure.example.com")
        XCTAssertEqual(restored?.port, 2202)
        XCTAssertEqual(restored?.username, "deploy")
        XCTAssertEqual(restored?.group, "Production")
        XCTAssertEqual(restored?.tags, ["ssh", "api"])

        let hostID = try XCTUnwrap(restored?.id)
        XCTAssertEqual(try credentialVault.password(forHostID: hostID), "not-in-json")
        let rawJSON = try String(contentsOf: repository.fileURL, encoding: .utf8)
        XCTAssertFalse(rawJSON.contains("not-in-json"))
    }

    func testStorePersistsAddedPortForwardRule() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = JSONHostRepository(fileURL: directory.appendingPathComponent("vault.json"))
        let hostID = UUID(uuidString: "EFEFEFEF-1111-2222-3333-EFEFEFEFEFEF")!
        let host = ShellHost(
            id: hostID,
            name: "jump-box",
            address: "jump.example.com",
            username: "deploy",
            group: "Production",
            tags: ["ssh"],
            status: .idle
        )
        try repository.save(HostPersistenceSnapshot(hosts: [host]))
        let store = try MobileShellStore(repository: repository, credentialVault: InMemoryCredentialVault())

        let rule = try XCTUnwrap(store.addPortForwardRule(
            name: "Postgres",
            sshHostID: hostID,
            localPort: 15432,
            remoteHost: "127.0.0.1",
            remotePort: 5432
        ))

        XCTAssertEqual(try repository.load().portForwardRules, [rule])
    }

    func testStorePersistsImportedOpenSSHHosts() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = JSONHostRepository(fileURL: directory.appendingPathComponent("vault.json"))
        let store = try MobileShellStore(repository: repository, credentialVault: InMemoryCredentialVault())

        let imported = store.importOpenSSHConfig("""
        Host bastion-prod
          HostName bastion.example.com
          User deploy
          Port 2201
        """)

        XCTAssertEqual(imported.count, 1)
        let restored = try XCTUnwrap(repository.load().hosts.first)
        XCTAssertEqual(restored.name, "bastion-prod")
        XCTAssertEqual(restored.address, "bastion.example.com")
        XCTAssertEqual(restored.port, 2201)
        XCTAssertEqual(restored.username, "deploy")
        XCTAssertEqual(restored.group, "Imported")
        XCTAssertEqual(restored.tags, ["ssh", "imported"])
    }

    func testStorePersistsUpdatedHostAndPassword() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = JSONHostRepository(fileURL: directory.appendingPathComponent("vault.json"))
        let hostID = UUID(uuidString: "DFDFDFDF-1111-2222-3333-DFDFDFDFDFDF")!
        let host = ShellHost(
            id: hostID,
            name: "old-api",
            address: "old.example.com",
            username: "deploy",
            group: "Production",
            tags: ["ssh"],
            status: .idle
        )
        try repository.save(HostPersistenceSnapshot(hosts: [host]))
        let credentialVault = InMemoryCredentialVault()
        try credentialVault.savePassword("old-secret", forHostID: hostID)
        let store = try MobileShellStore(repository: repository, credentialVault: credentialVault)

        let updated = try XCTUnwrap(store.updateHost(
            host,
            name: "new-api",
            address: "new.example.com",
            port: 2202,
            username: "admin",
            group: "Staging",
            tags: "ssh, staging",
            password: "new-secret"
        ))

        XCTAssertEqual(try repository.load().hosts, [updated])
        XCTAssertEqual(try credentialVault.password(forHostID: hostID), "new-secret")
    }

    func testStorePersistsMoshHostConfiguration() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = JSONHostRepository(fileURL: directory.appendingPathComponent("vault.json"))
        let store = try MobileShellStore(repository: repository, credentialVault: InMemoryCredentialVault())

        try store.addHost(
            name: "lab-mosh",
            address: "lab.example.com",
            port: 22,
            username: "ops",
            group: "Lab",
            tags: "mosh",
            password: "",
            protocol: .mosh,
            moshConfiguration: MoshHostConfiguration(
                udpPort: 60010,
                serverCommand: "mosh-server new -s",
                predictiveEcho: false,
                useExperimentalConnection: true
            )
        )

        let restored = try XCTUnwrap(repository.load().hosts.first)
        XCTAssertEqual(restored.protocol, .mosh)
        XCTAssertEqual(restored.moshConfiguration?.udpPort, 60010)
        XCTAssertEqual(restored.moshConfiguration?.serverCommand, "mosh-server new -s")
    }

    @MainActor
    func testStorePersistsDeletedHostAndRemovesPasswordAndLinkedPortForwards() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = JSONHostRepository(fileURL: directory.appendingPathComponent("vault.json"))
        let hostID = UUID(uuidString: "EFEF1234-1111-2222-3333-EFEF1234EFEF")!
        let host = ShellHost(
            id: hostID,
            name: "old-db",
            address: "db.example.com",
            username: "deploy",
            group: "Production",
            tags: ["ssh"],
            status: .idle
        )
        let rule = PortForwardRule(
            id: UUID(uuidString: "AFAF1234-1111-2222-3333-AFAF1234AFAF")!,
            name: "DB Tunnel",
            sshHostID: hostID,
            localPort: 15432,
            remoteHost: "127.0.0.1",
            remotePort: 5432,
            isActive: false
        )
        try repository.save(HostPersistenceSnapshot(hosts: [host], portForwardRules: [rule]))
        let credentialVault = InMemoryCredentialVault()
        try credentialVault.savePassword("db-secret", forHostID: hostID)
        let store = try MobileShellStore(repository: repository, credentialVault: credentialVault)

        await store.deleteHost(host)

        let snapshot = try repository.load()
        XCTAssertTrue(snapshot.hosts.isEmpty)
        XCTAssertTrue(snapshot.portForwardRules.isEmpty)
        XCTAssertNil(try credentialVault.password(forHostID: hostID))
    }

    func testStorePersistsSnippetCRUD() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = JSONHostRepository(fileURL: directory.appendingPathComponent("vault.json"))
        let store = try MobileShellStore(repository: repository, credentialVault: InMemoryCredentialVault())

        let added = try XCTUnwrap(store.addSnippet(
            title: "Health",
            command: "systemctl status api.service"
        ))
        XCTAssertEqual(try repository.load().snippets, [added])

        let updated = try XCTUnwrap(store.updateSnippet(
            added,
            title: "Logs",
            command: "tail -n 100 /var/log/app.log"
        ))
        XCTAssertEqual(try repository.load().snippets, [updated])

        store.deleteSnippet(updated)
        XCTAssertTrue(try repository.load().snippets.isEmpty)
    }

    func testStorePersistsSSHKeyMetadataWithoutPrivateMaterial() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = JSONHostRepository(fileURL: directory.appendingPathComponent("vault.json"))
        let credentialVault = InMemoryCredentialVault()
        let store = try MobileShellStore(repository: repository, credentialVault: credentialVault)
        let privateKey = "super-secret-private-key"

        let key = try XCTUnwrap(try store.addSSHKey(
            name: "Device Key",
            kind: "ed25519",
            privateKey: privateKey
        ))

        XCTAssertEqual(try repository.load().keys, [key])
        XCTAssertEqual(try credentialVault.privateKey(forKeyID: key.id), privateKey)
        let rawJSON = try String(contentsOf: repository.fileURL, encoding: .utf8)
        XCTAssertFalse(rawJSON.contains(privateKey))

        try store.deleteSSHKey(key)
        XCTAssertTrue(try repository.load().keys.isEmpty)
        XCTAssertNil(try credentialVault.privateKey(forKeyID: key.id))
    }

    func testStorePersistsIdentityMetadataWithoutPassword() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = JSONHostRepository(fileURL: directory.appendingPathComponent("vault.json"))
        let credentialVault = InMemoryCredentialVault()
        let store = try MobileShellStore(repository: repository, credentialVault: credentialVault)
        let keyID = UUID(uuidString: "71717171-7272-7373-7474-757575757575")!

        let identity = try XCTUnwrap(try store.addIdentity(
            name: "Production Deploy",
            username: "deploy",
            password: "identity-secret",
            sshKeyID: keyID
        ))

        XCTAssertEqual(try repository.load().identities, [identity])
        XCTAssertEqual(try credentialVault.password(forIdentityID: identity.id), "identity-secret")
        let rawJSON = try String(contentsOf: repository.fileURL, encoding: .utf8)
        XCTAssertFalse(rawJSON.contains("identity-secret"))
    }

    func testStorePersistsHostSSHKeyReferenceWithoutPrivateMaterial() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = JSONHostRepository(fileURL: directory.appendingPathComponent("vault.json"))
        let credentialVault = InMemoryCredentialVault()
        let keyID = UUID(uuidString: "61616161-6262-6363-6464-656565656565")!
        let privateKey = "linked-secret-private-key"
        try credentialVault.savePrivateKey(privateKey, forKeyID: keyID)
        let store = try MobileShellStore(repository: repository, credentialVault: credentialVault)

        try store.addHost(
            name: "linked-host",
            address: "linked.example.com",
            username: "deploy",
            group: "Production",
            tags: "ssh",
            password: "",
            sshKeyID: keyID
        )

        let persistedHost = try XCTUnwrap(repository.load().hosts.first { $0.name == "linked-host" })
        let rawJSON = try String(contentsOf: repository.fileURL, encoding: .utf8)
        XCTAssertEqual(persistedHost.sshKeyID, keyID)
        XCTAssertFalse(rawJSON.contains(privateKey))
    }

    func testStorePersistsKnownHostCRUD() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = JSONHostRepository(fileURL: directory.appendingPathComponent("vault.json"))
        let store = try MobileShellStore(repository: repository, credentialVault: InMemoryCredentialVault())

        let knownHost = try XCTUnwrap(store.trustKnownHost(
            host: "api.example.com",
            keyType: "ssh-ed25519",
            fingerprint: "SHA256:test"
        ))

        XCTAssertEqual(try repository.load().knownHosts, [knownHost])

        store.deleteKnownHost(knownHost)

        XCTAssertTrue(try repository.load().knownHosts.isEmpty)
    }

    func testRepositoryMigratesLegacyKnownHostStrings() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = JSONHostRepository(fileURL: directory.appendingPathComponent("vault.json"))
        let legacyJSON = """
        {
          "history" : [],
          "hosts" : [],
          "keys" : [],
          "knownHosts" : [
            "legacy.example.com ssh-ed25519 SHA256:legacy"
          ],
          "portForwardRules" : [],
          "sftpItems" : [],
          "snippets" : []
        }
        """
        try legacyJSON.write(to: repository.fileURL, atomically: true, encoding: .utf8)

        let knownHost = try XCTUnwrap(repository.load().knownHosts.first)

        XCTAssertEqual(knownHost.host, "legacy.example.com")
        XCTAssertEqual(knownHost.keyType, "ssh-ed25519")
        XCTAssertEqual(knownHost.fingerprint, "SHA256:legacy")
    }

    func testPersistentStoreFactorySeedsPreviewHostsWhenRepositoryIsEmpty() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = JSONHostRepository(fileURL: directory.appendingPathComponent("vault.json"))

        let store = try MobileShellStore.persistent(repository: repository, credentialVault: InMemoryCredentialVault())

        XCTAssertTrue(store.hosts.contains { $0.name == "acme-api-prod" })
        try store.addHost(
            name: "persisted-after-seed",
            address: "seed.example.com",
            username: "seed",
            group: "Seeded",
            tags: "ssh",
            password: ""
        )
        XCTAssertTrue(try repository.load().hosts.contains { $0.name == "persisted-after-seed" })
    }
}
