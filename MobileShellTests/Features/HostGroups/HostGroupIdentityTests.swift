import XCTest
@testable import MobileShell

final class HostGroupIdentityTests: XCTestCase {
    func testAddingHostGroupProfileTrimsNameAndStoresIdentityReference() throws {
        let identityID = UUID(uuidString: "51515151-1111-2222-3333-515151515151")!
        let store = MobileShellStore()

        let group = try XCTUnwrap(store.upsertHostGroupProfile(name: " Production ", identityID: identityID))

        XCTAssertEqual(group.name, "Production")
        XCTAssertEqual(group.identityID, identityID)
        XCTAssertEqual(store.hostGroupProfiles, [group])
        XCTAssertEqual(store.history.first, "Updated group Production")
    }

    func testStorePersistsHostGroupProfiles() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repository = JSONHostRepository(fileURL: tempDirectory.appendingPathComponent("hosts.json"))
        let identityID = UUID(uuidString: "52525252-1111-2222-3333-525252525252")!
        let store = try MobileShellStore(repository: repository, credentialVault: InMemoryCredentialVault())

        _ = try XCTUnwrap(store.upsertHostGroupProfile(name: "Production", identityID: identityID))

        let reloaded = try MobileShellStore(repository: repository, credentialVault: InMemoryCredentialVault())
        XCTAssertEqual(reloaded.hostGroupProfiles, [
            HostGroupProfile(name: "Production", identityID: identityID)
        ])
    }

    func testConnectionRequestUsesGroupIdentityWhenHostHasNoIdentity() throws {
        let hostID = UUID(uuidString: "53535353-1111-2222-3333-535353535353")!
        let identityID = UUID(uuidString: "54545454-1111-2222-3333-545454545454")!
        let keyID = UUID(uuidString: "55555555-1111-2222-3333-555555555555")!
        let host = ShellHost(
            id: hostID,
            name: "group-host",
            address: "group.example.com",
            username: "host-user",
            group: "Production",
            tags: ["ssh"],
            status: .idle
        )
        let identity = SSHIdentity(
            id: identityID,
            name: "Production Deploy",
            username: "deploy",
            sshKeyID: keyID
        )
        let credentialVault = InMemoryCredentialVault()
        try credentialVault.savePassword("group-secret", forIdentityID: identityID)
        try credentialVault.savePrivateKey("group-private-key", forKeyID: keyID)

        let request = try SSHConnectionRequestBuilder(
            credentialVault: credentialVault,
            identities: [identity],
            hostGroupProfiles: [HostGroupProfile(name: "Production", identityID: identityID)]
        ).request(for: host)

        XCTAssertEqual(request.username, "deploy")
        XCTAssertEqual(request.password, "group-secret")
        XCTAssertEqual(request.privateKey, "group-private-key")
    }

    func testHostIdentityOverridesGroupIdentity() throws {
        let hostIdentityID = UUID(uuidString: "56565656-1111-2222-3333-565656565656")!
        let groupIdentityID = UUID(uuidString: "57575757-1111-2222-3333-575757575757")!
        let host = ShellHost(
            id: UUID(uuidString: "58585858-1111-2222-3333-585858585858")!,
            name: "override-host",
            address: "override.example.com",
            username: "host-user",
            group: "Production",
            tags: ["ssh"],
            status: .idle,
            identityID: hostIdentityID
        )
        let hostIdentity = SSHIdentity(
            id: hostIdentityID,
            name: "Host Identity",
            username: "host-identity",
            sshKeyID: nil
        )
        let groupIdentity = SSHIdentity(
            id: groupIdentityID,
            name: "Group Identity",
            username: "group-identity",
            sshKeyID: nil
        )

        let request = try SSHConnectionRequestBuilder(
            identities: [hostIdentity, groupIdentity],
            hostGroupProfiles: [HostGroupProfile(name: "Production", identityID: groupIdentityID)]
        ).request(for: host)

        XCTAssertEqual(request.username, "host-identity")
    }

    func testAuthenticationSummaryDescribesInheritedGroupIdentity() throws {
        let identityID = UUID(uuidString: "59595959-1111-2222-3333-595959595959")!
        let keyID = UUID(uuidString: "5A5A5A5A-1111-2222-3333-5A5A5A5A5A5A")!
        let host = ShellHost(
            id: UUID(uuidString: "5B5B5B5B-1111-2222-3333-5B5B5B5B5B5B")!,
            name: "summary-host",
            address: "summary.example.com",
            username: "host-user",
            group: "Production",
            tags: ["ssh"],
            status: .idle
        )
        let identity = SSHIdentity(
            id: identityID,
            name: "Production Deploy",
            username: "deploy",
            sshKeyID: keyID
        )
        let key = SSHKey(
            id: keyID,
            name: "Device Key",
            fingerprint: "SHA256:test",
            kind: "ed25519"
        )
        let credentialVault = InMemoryCredentialVault()
        try credentialVault.savePassword("group-secret", forIdentityID: identityID)
        try credentialVault.savePrivateKey("private-key", forKeyID: keyID)
        let store = MobileShellStore(
            hosts: [host],
            keys: [key],
            identities: [identity],
            hostGroupProfiles: [HostGroupProfile(name: "Production", identityID: identityID)],
            credentialVault: credentialVault
        )

        XCTAssertEqual(
            store.authenticationSummary(for: host),
            HostAuthenticationSummary(
                text: "Group Identity: Production Deploy (Password + SSH key: Device Key)",
                symbolName: "person.text.rectangle.fill",
                isReady: true
            )
        )
    }
}
