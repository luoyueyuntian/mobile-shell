import XCTest
@testable import MobileShell

final class SSHCertificateTests: XCTestCase {
    private let certificateMaterial = "ssh-ed25519-cert-v01@openssh.com AAAATEST prod"

    func testAddingSSHCertificateStoresMetadataAndMaterialSeparately() throws {
        let vault = InMemoryCredentialVault()
        let keyID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-000000000001")!
        let key = SSHKey(
            id: keyID,
            name: "Device Key",
            fingerprint: "SHA256:key",
            kind: "ed25519"
        )
        let store = MobileShellStore(keys: [key], credentialVault: vault)

        let certificate = try XCTUnwrap(try store.addSSHCertificate(
            name: "  Prod User Cert  ",
            kind: " user-cert ",
            certificate: "  \(certificateMaterial)  ",
            sshKeyID: keyID
        ))

        XCTAssertEqual(certificate.name, "Prod User Cert")
        XCTAssertEqual(certificate.kind, "user-cert")
        XCTAssertTrue(certificate.fingerprint.hasPrefix("SHA256:"))
        XCTAssertEqual(store.certificates, [certificate])
        XCTAssertEqual(store.keys.first?.certificateID, certificate.id)
        XCTAssertEqual(try vault.certificate(forCertificateID: certificate.id), certificateMaterial)
        XCTAssertEqual(store.history.first, "Added SSH certificate Prod User Cert")
    }

    func testConnectionRequestIncludesCertificateForLinkedHostKey() throws {
        let vault = InMemoryCredentialVault()
        let hostID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-000000000002")!
        let keyID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-000000000003")!
        let key = SSHKey(
            id: keyID,
            name: "Device Key",
            fingerprint: "SHA256:key",
            kind: "ed25519"
        )
        let host = ShellHost(
            id: hostID,
            name: "prod-api",
            address: "api.example.com",
            username: "deploy",
            group: "Production",
            tags: ["ssh"],
            status: .idle,
            sshKeyID: keyID
        )
        let store = MobileShellStore(hosts: [host], keys: [key], credentialVault: vault)
        let certificate = try XCTUnwrap(try store.addSSHCertificate(
            name: "Prod User Cert",
            kind: "user-cert",
            certificate: certificateMaterial,
            sshKeyID: keyID
        ))
        try vault.savePrivateKey("host-private-key", forKeyID: keyID)

        let request = try SSHConnectionRequestBuilder(
            credentialVault: vault,
            hosts: store.hosts,
            keys: store.keys,
            certificates: store.certificates
        ).request(for: host)

        XCTAssertEqual(request.privateKey, "host-private-key")
        XCTAssertEqual(request.certificate, certificateMaterial)
        XCTAssertEqual(store.keys.first?.certificateID, certificate.id)
    }

    func testConnectionRequestIncludesCertificateForLinkedIdentityKey() throws {
        let vault = InMemoryCredentialVault()
        let hostID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-000000000004")!
        let identityID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-000000000005")!
        let keyID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-000000000006")!
        let key = SSHKey(
            id: keyID,
            name: "Identity Key",
            fingerprint: "SHA256:key",
            kind: "ed25519"
        )
        let host = ShellHost(
            id: hostID,
            name: "identity-api",
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
            sshKeyID: keyID
        )
        let store = MobileShellStore(
            hosts: [host],
            keys: [key],
            identities: [identity],
            credentialVault: vault
        )
        try store.addSSHCertificate(
            name: "Identity User Cert",
            kind: "user-cert",
            certificate: certificateMaterial,
            sshKeyID: keyID
        )
        try vault.savePassword("identity-secret", forIdentityID: identityID)
        try vault.savePrivateKey("identity-private-key", forKeyID: keyID)

        let request = try SSHConnectionRequestBuilder(
            credentialVault: vault,
            hosts: store.hosts,
            identities: store.identities,
            keys: store.keys,
            certificates: store.certificates
        ).request(for: host)

        XCTAssertEqual(request.username, "deploy")
        XCTAssertEqual(request.password, "identity-secret")
        XCTAssertEqual(request.privateKey, "identity-private-key")
        XCTAssertEqual(request.certificate, certificateMaterial)
    }

    func testAuthenticationSummaryMentionsAvailableLinkedCertificate() throws {
        let vault = InMemoryCredentialVault()
        let hostID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-000000000007")!
        let keyID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-000000000008")!
        let host = ShellHost(
            id: hostID,
            name: "certified-host",
            address: "certified.example.com",
            username: "deploy",
            group: "Production",
            tags: ["ssh"],
            status: .idle,
            sshKeyID: keyID
        )
        let key = SSHKey(
            id: keyID,
            name: "Device Key",
            fingerprint: "SHA256:key",
            kind: "ed25519"
        )
        let store = MobileShellStore(hosts: [host], keys: [key], credentialVault: vault)
        try store.addSSHCertificate(
            name: "Prod User Cert",
            kind: "user-cert",
            certificate: certificateMaterial,
            sshKeyID: keyID
        )
        try vault.savePrivateKey("private-key", forKeyID: keyID)

        XCTAssertEqual(
            store.authenticationSummary(for: host),
            HostAuthenticationSummary(
                text: "SSH key: Device Key + certificate: Prod User Cert",
                symbolName: "key.fill",
                isReady: true
            )
        )
    }

    func testAuthenticationSummaryMentionsIdentityCertificate() throws {
        let vault = InMemoryCredentialVault()
        let hostID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-000000000009")!
        let identityID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-00000000000A")!
        let keyID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-00000000000B")!
        let host = ShellHost(
            id: hostID,
            name: "identity-cert-host",
            address: "identity-cert.example.com",
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
            sshKeyID: keyID
        )
        let key = SSHKey(
            id: keyID,
            name: "Identity Key",
            fingerprint: "SHA256:key",
            kind: "ed25519"
        )
        let store = MobileShellStore(
            hosts: [host],
            keys: [key],
            identities: [identity],
            credentialVault: vault
        )
        try store.addSSHCertificate(
            name: "Identity User Cert",
            kind: "user-cert",
            certificate: certificateMaterial,
            sshKeyID: keyID
        )
        try vault.savePassword("identity-secret", forIdentityID: identityID)
        try vault.savePrivateKey("identity-private-key", forKeyID: keyID)

        XCTAssertEqual(
            store.authenticationSummary(for: host),
            HostAuthenticationSummary(
                text: "Identity: Production Deploy (Password + SSH key: Identity Key + certificate: Identity User Cert)",
                symbolName: "person.text.rectangle.fill",
                isReady: true
            )
        )
    }

    func testUpdatingSSHCertificateKeepsIDAndRotatesMaterial() throws {
        let vault = InMemoryCredentialVault()
        let store = MobileShellStore(credentialVault: vault)
        let certificate = try XCTUnwrap(try store.addSSHCertificate(
            name: "Old Cert",
            kind: "user-cert",
            certificate: "old-certificate-material"
        ))

        let updated = try XCTUnwrap(try store.updateSSHCertificate(
            certificate,
            name: "  Prod User Cert  ",
            kind: " ed25519-cert ",
            certificate: "  \(certificateMaterial)  "
        ))

        XCTAssertEqual(updated.id, certificate.id)
        XCTAssertEqual(updated.name, "Prod User Cert")
        XCTAssertEqual(updated.kind, "ed25519-cert")
        XCTAssertNotEqual(updated.fingerprint, certificate.fingerprint)
        XCTAssertEqual(try vault.certificate(forCertificateID: certificate.id), certificateMaterial)
        XCTAssertEqual(store.history.first, "Updated SSH certificate Prod User Cert")
    }

    func testDeletingSSHCertificateRemovesMaterialAndClearsKeyLink() throws {
        let vault = InMemoryCredentialVault()
        let keyID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-00000000000C")!
        let key = SSHKey(
            id: keyID,
            name: "Device Key",
            fingerprint: "SHA256:key",
            kind: "ed25519"
        )
        let store = MobileShellStore(keys: [key], credentialVault: vault)
        let certificate = try XCTUnwrap(try store.addSSHCertificate(
            name: "Prod User Cert",
            kind: "user-cert",
            certificate: certificateMaterial,
            sshKeyID: keyID
        ))

        try store.deleteSSHCertificate(certificate)

        XCTAssertTrue(store.certificates.isEmpty)
        XCTAssertNil(store.keys.first?.certificateID)
        XCTAssertNil(try vault.certificate(forCertificateID: certificate.id))
        XCTAssertEqual(store.history.first, "Deleted SSH certificate Prod User Cert")
    }

    func testStorePersistsCertificateMetadataWithoutMaterial() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = JSONHostRepository(fileURL: directory.appendingPathComponent("vault.json"))
        let vault = InMemoryCredentialVault()
        let store = try MobileShellStore(repository: repository, credentialVault: vault)

        let certificate = try XCTUnwrap(try store.addSSHCertificate(
            name: "Prod User Cert",
            kind: "user-cert",
            certificate: certificateMaterial
        ))

        XCTAssertEqual(try repository.load().certificates, [certificate])
        XCTAssertEqual(try vault.certificate(forCertificateID: certificate.id), certificateMaterial)
        let rawJSON = try String(contentsOf: repository.fileURL, encoding: .utf8)
        XCTAssertFalse(rawJSON.contains(certificateMaterial))
    }
}
