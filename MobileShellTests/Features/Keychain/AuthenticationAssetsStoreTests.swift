import XCTest
@testable import MobileShell

final class AuthenticationAssetsStoreTests: XCTestCase {
    func testAddingSSHKeyStoresMetadataAndPrivateMaterialSeparately() throws {
        let credentialVault = InMemoryCredentialVault()
        let store = MobileShellStore(credentialVault: credentialVault)
        let privateKey = """
        -----BEGIN OPENSSH PRIVATE KEY-----
        fixture-private-key
        -----END OPENSSH PRIVATE KEY-----
        """

        let key = try XCTUnwrap(try store.addSSHKey(
            name: "  iPhone Device Key  ",
            kind: " ed25519 ",
            privateKey: "  \(privateKey)  "
        ))

        XCTAssertEqual(key.name, "iPhone Device Key")
        XCTAssertEqual(key.kind, "ed25519")
        XCTAssertTrue(key.fingerprint.hasPrefix("SHA256:"))
        XCTAssertEqual(store.keys, [key])
        XCTAssertEqual(try credentialVault.privateKey(forKeyID: key.id), privateKey)
        XCTAssertEqual(store.history.first, "Added SSH key iPhone Device Key")
    }

    func testUpdatingSSHKeyKeepsIDAndRotatesPrivateMaterial() throws {
        let credentialVault = InMemoryCredentialVault()
        let store = MobileShellStore(credentialVault: credentialVault)
        let original = try XCTUnwrap(try store.addSSHKey(
            name: "Device Key",
            kind: "ed25519",
            privateKey: "old-private-key"
        ))

        let updated = try XCTUnwrap(try store.updateSSHKey(
            original,
            name: "  Production Key  ",
            kind: " rsa ",
            privateKey: "  new-private-key  "
        ))

        XCTAssertEqual(updated.id, original.id)
        XCTAssertEqual(updated.name, "Production Key")
        XCTAssertEqual(updated.kind, "rsa")
        XCTAssertNotEqual(updated.fingerprint, original.fingerprint)
        XCTAssertEqual(store.keys, [updated])
        XCTAssertEqual(try credentialVault.privateKey(forKeyID: updated.id), "new-private-key")
        XCTAssertEqual(store.history.first, "Updated SSH key Production Key")
    }

    func testDeletingSSHKeyRemovesMetadataAndPrivateMaterial() throws {
        let credentialVault = InMemoryCredentialVault()
        let store = MobileShellStore(credentialVault: credentialVault)
        let key = try XCTUnwrap(try store.addSSHKey(
            name: "Device Key",
            kind: "ed25519",
            privateKey: "private-key"
        ))

        try store.deleteSSHKey(key)

        XCTAssertTrue(store.keys.isEmpty)
        XCTAssertNil(try credentialVault.privateKey(forKeyID: key.id))
        XCTAssertEqual(store.history.first, "Deleted SSH key Device Key")
    }

    func testDeletingSSHKeyDetachesLinkedHostsIdentitiesAndCertificate() throws {
        let keyID = UUID(uuidString: "41414141-4242-4343-4444-454545454545")!
        let certificateID = UUID(uuidString: "45454545-5555-6666-7777-888888888888")!
        let identityID = UUID(uuidString: "56565656-6767-7878-8989-909090909090")!
        let host = ShellHost(
            id: UUID(uuidString: "51515151-5252-5353-5454-555555555555")!,
            name: "keyed-host",
            address: "keyed.example.com",
            username: "deploy",
            group: "Production",
            tags: ["ssh"],
            status: .idle,
            sshKeyID: keyID,
            identityID: identityID
        )
        let identity = SSHIdentity(
            id: identityID,
            name: "Deploy Identity",
            username: "deploy",
            sshKeyID: keyID
        )
        let certificate = SSHCertificate(
            id: certificateID,
            name: "Prod Cert",
            fingerprint: "SHA256:cert",
            kind: "user-cert"
        )
        let credentialVault = InMemoryCredentialVault()
        try credentialVault.savePrivateKey("private-key", forKeyID: keyID)
        try credentialVault.saveCertificate("cert-material", forCertificateID: certificateID)
        let key = SSHKey(
            id: keyID,
            name: "Device Key",
            fingerprint: "SHA256:test",
            kind: "ed25519",
            certificateID: certificateID
        )
        let store = MobileShellStore(
            hosts: [host],
            keys: [key],
            certificates: [certificate],
            identities: [identity],
            credentialVault: credentialVault
        )

        try store.deleteSSHKey(key)

        XCTAssertNil(store.hosts.first?.sshKeyID)
        XCTAssertNil(store.identities.first?.sshKeyID)
        XCTAssertTrue(store.certificates.isEmpty)
        XCTAssertNil(try credentialVault.privateKey(forKeyID: keyID))
        XCTAssertNil(try credentialVault.certificate(forCertificateID: certificateID))
    }

    func testAddingIdentityStoresMetadataAndPasswordSeparately() throws {
        let credentialVault = InMemoryCredentialVault()
        let keyID = UUID(uuidString: "A7A7A7A7-2222-3333-4444-A7A7A7A7A7A7")!
        let store = MobileShellStore(credentialVault: credentialVault)

        let identity = try XCTUnwrap(try store.addIdentity(
            name: "  Production Deploy  ",
            username: " deploy ",
            password: " identity-secret ",
            sshKeyID: keyID
        ))

        XCTAssertEqual(identity.name, "Production Deploy")
        XCTAssertEqual(identity.username, "deploy")
        XCTAssertEqual(identity.sshKeyID, keyID)
        XCTAssertEqual(store.identities, [identity])
        XCTAssertEqual(try credentialVault.password(forIdentityID: identity.id), "identity-secret")
        XCTAssertEqual(store.history.first, "Added identity Production Deploy")
    }

    func testUpdatingIdentityKeepsIDAndRefreshesOpenConnectionRequest() throws {
        let hostID = UUID(uuidString: "71717171-2222-3333-4444-555555555555")!
        let identityID = UUID(uuidString: "72727272-2222-3333-4444-555555555555")!
        let originalKeyID = UUID(uuidString: "73737373-2222-3333-4444-555555555555")!
        let updatedKeyID = UUID(uuidString: "74747474-2222-3333-4444-555555555555")!
        let host = ShellHost(
            id: hostID,
            name: "identity-host",
            address: "identity.example.com",
            username: "host-user",
            group: "Production",
            tags: ["ssh"],
            status: .idle,
            identityID: identityID
        )
        let identity = SSHIdentity(
            id: identityID,
            name: "Production Deploy",
            username: "deploy",
            sshKeyID: originalKeyID
        )
        let credentialVault = InMemoryCredentialVault()
        try credentialVault.savePassword("identity-secret", forIdentityID: identityID)
        try credentialVault.savePrivateKey("original-private-key", forKeyID: originalKeyID)
        try credentialVault.savePrivateKey("updated-private-key", forKeyID: updatedKeyID)
        let store = MobileShellStore(
            hosts: [host],
            identities: [identity],
            credentialVault: credentialVault
        )

        store.connect(to: host)
        let sessionID = try XCTUnwrap(store.selectedSessionID)

        let updatedIdentity = try XCTUnwrap(try store.updateIdentity(
            identity,
            name: "  Deploy Updated  ",
            username: " updated-user ",
            password: " updated-secret ",
            sshKeyID: updatedKeyID
        ))

        XCTAssertEqual(updatedIdentity.id, identityID)
        XCTAssertEqual(updatedIdentity.name, "Deploy Updated")
        XCTAssertEqual(updatedIdentity.username, "updated-user")
        XCTAssertEqual(updatedIdentity.sshKeyID, updatedKeyID)
        XCTAssertEqual(try credentialVault.password(forIdentityID: identityID), "updated-secret")
        XCTAssertEqual(store.terminalConnectionRequests[sessionID]?.username, "updated-user")
        XCTAssertEqual(store.terminalConnectionRequests[sessionID]?.password, "updated-secret")
        XCTAssertEqual(store.terminalConnectionRequests[sessionID]?.privateKey, "updated-private-key")
        XCTAssertEqual(store.history.first, "Updated identity Deploy Updated")
    }

    func testDeletingIdentityRemovesPasswordAndDetachesHostsAndGroupProfiles() throws {
        let identityID = UUID(uuidString: "A8A8A8A8-2222-3333-4444-A8A8A8A8A8A8")!
        let host = ShellHost(
            id: UUID(uuidString: "A9A9A9A9-2222-3333-4444-A9A9A9A9A9A9")!,
            name: "identity-host",
            address: "identity.example.com",
            username: "host-user",
            group: "Production",
            tags: ["ssh"],
            status: .idle,
            identityID: identityID
        )
        let identity = SSHIdentity(
            id: identityID,
            name: "Production Deploy",
            username: "deploy",
            sshKeyID: nil
        )
        let profile = HostGroupProfile(
            name: "Production",
            identityID: identityID
        )
        let credentialVault = InMemoryCredentialVault()
        try credentialVault.savePassword("identity-secret", forIdentityID: identityID)
        let store = MobileShellStore(
            hosts: [host],
            identities: [identity],
            hostGroupProfiles: [profile],
            credentialVault: credentialVault
        )

        try store.deleteIdentity(identity)

        XCTAssertTrue(store.identities.isEmpty)
        XCTAssertNil(store.hosts.first?.identityID)
        XCTAssertNil(store.hostGroupProfiles.first?.identityID)
        XCTAssertNil(try credentialVault.password(forIdentityID: identityID))
        XCTAssertEqual(store.history.first, "Deleted identity Production Deploy")
    }

    func testSSHConnectionRequestUsesLinkedIdentityCredentials() throws {
        let hostID = UUID(uuidString: "BBBBBBBB-2222-3333-4444-BBBBBBBBBBBB")!
        let identityID = UUID(uuidString: "BCBCBCBC-2222-3333-4444-BCBCBCBCBCBC")!
        let identityKeyID = UUID(uuidString: "BDBDBDBD-2222-3333-4444-BDBDBDBDBDBD")!
        let hostKeyID = UUID(uuidString: "BEBEBEBE-2222-3333-4444-BEBEBEBEBEBE")!
        let host = ShellHost(
            id: hostID,
            name: "identity-linked",
            address: "identity-linked.example.com",
            username: "host-user",
            group: "Production",
            tags: ["ssh"],
            status: .idle,
            sshKeyID: hostKeyID,
            identityID: identityID
        )
        let identity = SSHIdentity(
            id: identityID,
            name: "Production Deploy",
            username: "deploy",
            sshKeyID: identityKeyID
        )
        let credentialVault = InMemoryCredentialVault()
        try credentialVault.savePassword("host-secret", forHostID: hostID)
        try credentialVault.savePassword("identity-secret", forIdentityID: identityID)
        try credentialVault.savePrivateKey("host-private-key", forKeyID: hostKeyID)
        try credentialVault.savePrivateKey("identity-private-key", forKeyID: identityKeyID)

        let request = try SSHConnectionRequestBuilder(
            credentialVault: credentialVault,
            identities: [identity]
        ).request(for: host)

        XCTAssertEqual(request.username, "deploy")
        XCTAssertEqual(request.password, "identity-secret")
        XCTAssertEqual(request.privateKey, "identity-private-key")
    }

    func testAuthenticationSummaryDescribesIdentityCredentialStates() throws {
        let identityID = UUID(uuidString: "BFBFBFBF-2222-3333-4444-BFBFBFBFBFBF")!
        let keyID = UUID(uuidString: "C0C0C0C0-2222-3333-4444-C0C0C0C0C0C0")!
        let identityHost = ShellHost(
            id: UUID(uuidString: "C1C1C1C1-2222-3333-4444-C1C1C1C1C1C1")!,
            name: "identity-host",
            address: "identity.example.com",
            username: "host-user",
            group: "Production",
            tags: ["ssh"],
            status: .idle,
            identityID: identityID
        )
        let missingIdentityHost = ShellHost(
            id: UUID(uuidString: "C2C2C2C2-2222-3333-4444-C2C2C2C2C2C2")!,
            name: "missing-identity-host",
            address: "missing-identity.example.com",
            username: "host-user",
            group: "Production",
            tags: ["ssh"],
            status: .idle,
            identityID: UUID(uuidString: "C3C3C3C3-2222-3333-4444-C3C3C3C3C3C3")!
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
        try credentialVault.savePassword("identity-secret", forIdentityID: identityID)
        try credentialVault.savePrivateKey("private-key", forKeyID: keyID)
        let store = MobileShellStore(
            hosts: [identityHost, missingIdentityHost],
            keys: [key],
            identities: [identity],
            credentialVault: credentialVault
        )

        XCTAssertEqual(
            store.authenticationSummary(for: identityHost),
            HostAuthenticationSummary(
                text: "Identity: Production Deploy (Password + SSH key: Device Key)",
                symbolName: "person.text.rectangle.fill",
                isReady: true
            )
        )
        XCTAssertEqual(
            store.authenticationSummary(for: missingIdentityHost),
            HostAuthenticationSummary(
                text: "Missing identity",
                symbolName: "exclamationmark.triangle.fill",
                isReady: false
            )
        )
    }

    func testAuthenticationSummaryDescribesPasswordKeyAndMissingCredentialStates() throws {
        let passwordHostID = UUID(uuidString: "61616161-1111-2222-3333-616161616161")!
        let keyedHostID = UUID(uuidString: "62626262-1111-2222-3333-626262626262")!
        let combinedHostID = UUID(uuidString: "63636363-1111-2222-3333-636363636363")!
        let missingKeyHostID = UUID(uuidString: "64646464-1111-2222-3333-646464646464")!
        let emptyHostID = UUID(uuidString: "74747474-1111-2222-3333-747474747474")!
        let keyID = UUID(uuidString: "65656565-1111-2222-3333-656565656565")!
        let passwordHost = ShellHost(
            id: passwordHostID,
            name: "password-host",
            address: "password.example.com",
            username: "deploy",
            group: "Production",
            tags: ["ssh"],
            status: .idle
        )
        let keyedHost = ShellHost(
            id: keyedHostID,
            name: "keyed-host",
            address: "keyed.example.com",
            username: "deploy",
            group: "Production",
            tags: ["ssh"],
            status: .idle,
            sshKeyID: keyID
        )
        let combinedHost = ShellHost(
            id: combinedHostID,
            name: "combined-host",
            address: "combined.example.com",
            username: "deploy",
            group: "Production",
            tags: ["ssh"],
            status: .idle,
            sshKeyID: keyID
        )
        let missingKeyHost = ShellHost(
            id: missingKeyHostID,
            name: "missing-key-host",
            address: "missing.example.com",
            username: "deploy",
            group: "Production",
            tags: ["ssh"],
            status: .idle,
            sshKeyID: UUID(uuidString: "66666666-1111-2222-3333-666666666666")!
        )
        let emptyHost = ShellHost(
            id: emptyHostID,
            name: "empty-host",
            address: "empty.example.com",
            username: "deploy",
            group: "Production",
            tags: ["ssh"],
            status: .idle
        )
        let key = SSHKey(
            id: keyID,
            name: "Device Key",
            fingerprint: "SHA256:test",
            kind: "ed25519"
        )
        let credentialVault = InMemoryCredentialVault()
        try credentialVault.savePassword("password-secret", forHostID: passwordHostID)
        try credentialVault.savePassword("combined-secret", forHostID: combinedHostID)
        try credentialVault.savePrivateKey("private-key", forKeyID: keyID)
        let store = MobileShellStore(
            hosts: [passwordHost, keyedHost, combinedHost, missingKeyHost, emptyHost],
            keys: [key],
            credentialVault: credentialVault
        )

        XCTAssertEqual(
            store.authenticationSummary(for: passwordHost),
            HostAuthenticationSummary(text: "Password", symbolName: "lock.fill", isReady: true)
        )
        XCTAssertEqual(
            store.authenticationSummary(for: keyedHost),
            HostAuthenticationSummary(text: "SSH key: Device Key", symbolName: "key.fill", isReady: true)
        )
        XCTAssertEqual(
            store.authenticationSummary(for: combinedHost),
            HostAuthenticationSummary(text: "Password + SSH key: Device Key", symbolName: "key.horizontal.fill", isReady: true)
        )
        XCTAssertEqual(
            store.authenticationSummary(for: missingKeyHost),
            HostAuthenticationSummary(text: "Missing SSH key", symbolName: "exclamationmark.triangle.fill", isReady: false)
        )
        XCTAssertEqual(
            store.authenticationSummary(for: emptyHost),
            HostAuthenticationSummary(text: "No credential", symbolName: "exclamationmark.lock.fill", isReady: false)
        )
    }

    func testLinkedHostsForSSHKeyReturnsSortedHostNames() throws {
        let keyID = UUID(uuidString: "67676767-1111-2222-3333-676767676767")!
        let key = SSHKey(
            id: keyID,
            name: "Device Key",
            fingerprint: "SHA256:test",
            kind: "ed25519"
        )
        let zed = ShellHost(
            id: UUID(uuidString: "68686868-1111-2222-3333-686868686868")!,
            name: "zed-host",
            address: "zed.example.com",
            username: "deploy",
            group: "Production",
            tags: ["ssh"],
            status: .idle,
            sshKeyID: keyID
        )
        let api = ShellHost(
            id: UUID(uuidString: "69696969-1111-2222-3333-696969696969")!,
            name: "api-host",
            address: "api.example.com",
            username: "deploy",
            group: "Production",
            tags: ["ssh"],
            status: .idle,
            sshKeyID: keyID
        )
        let unrelated = ShellHost(
            id: UUID(uuidString: "70707070-1111-2222-3333-707070707070")!,
            name: "unrelated-host",
            address: "unrelated.example.com",
            username: "deploy",
            group: "Production",
            tags: ["ssh"],
            status: .idle
        )
        let store = MobileShellStore(hosts: [zed, unrelated, api], keys: [key])

        XCTAssertEqual(store.linkedHosts(for: key).map(\.name), ["api-host", "zed-host"])
    }

    func testLinkedHostsForIdentityReturnsSortedHostNames() throws {
        let identityID = UUID(uuidString: "80808080-1111-2222-3333-808080808080")!
        let identity = SSHIdentity(
            id: identityID,
            name: "Deploy Identity",
            username: "deploy",
            sshKeyID: nil
        )
        let zed = ShellHost(
            id: UUID(uuidString: "81818181-1111-2222-3333-818181818181")!,
            name: "zed-host",
            address: "zed.example.com",
            username: "deploy",
            group: "Production",
            tags: ["ssh"],
            status: .idle,
            identityID: identityID
        )
        let api = ShellHost(
            id: UUID(uuidString: "82828282-1111-2222-3333-828282828282")!,
            name: "api-host",
            address: "api.example.com",
            username: "deploy",
            group: "Production",
            tags: ["ssh"],
            status: .idle,
            identityID: identityID
        )
        let unrelated = ShellHost(
            id: UUID(uuidString: "83838383-1111-2222-3333-838383838383")!,
            name: "unrelated-host",
            address: "unrelated.example.com",
            username: "deploy",
            group: "Production",
            tags: ["ssh"],
            status: .idle
        )
        let store = MobileShellStore(
            hosts: [zed, unrelated, api],
            identities: [identity]
        )

        XCTAssertEqual(store.linkedHosts(for: identity).map(\.name), ["api-host", "zed-host"])
    }
}
