import XCTest
@testable import MobileShell

final class KnownHostStoreTests: XCTestCase {
    func testTrustingKnownHostTrimsFieldsAndUpsertsByHostAndKeyType() throws {
        let store = MobileShellStore()

        let first = try XCTUnwrap(store.trustKnownHost(
            host: " api.example.com ",
            keyType: " ssh-ed25519 ",
            fingerprint: " SHA256:old "
        ))
        let updated = try XCTUnwrap(store.trustKnownHost(
            host: "api.example.com",
            keyType: "ssh-ed25519",
            fingerprint: "SHA256:new"
        ))

        XCTAssertEqual(first.host, "api.example.com")
        XCTAssertEqual(first.keyType, "ssh-ed25519")
        XCTAssertEqual(first.fingerprint, "SHA256:old")
        XCTAssertEqual(updated.id, first.id)
        XCTAssertEqual(store.knownHosts, [
            KnownHost(
                id: first.id,
                host: "api.example.com",
                keyType: "ssh-ed25519",
                fingerprint: "SHA256:new"
            )
        ])
        XCTAssertEqual(store.history.first, "Updated known host api.example.com")
    }

    func testDeletingKnownHostRemovesItAndRecordsHistory() throws {
        let store = MobileShellStore()
        let knownHost = try XCTUnwrap(store.trustKnownHost(
            host: "api.example.com",
            keyType: "ssh-ed25519",
            fingerprint: "SHA256:test"
        ))

        store.deleteKnownHost(knownHost)

        XCTAssertTrue(store.knownHosts.isEmpty)
        XCTAssertEqual(store.history.first, "Deleted known host api.example.com")
    }

    func testKnownHostMatchesDefaultAndCustomPortHostnames() {
        let defaultPortKnownHost = KnownHost(
            host: "api.example.com",
            keyType: "ssh-ed25519",
            fingerprint: "SHA256:api"
        )
        let customPortKnownHost = KnownHost(
            host: "[api.example.com]:2201",
            keyType: "ssh-ed25519",
            fingerprint: "SHA256:api-custom"
        )

        XCTAssertTrue(defaultPortKnownHost.matches(hostname: "API.example.com", port: 22))
        XCTAssertFalse(defaultPortKnownHost.matches(hostname: "api.example.com", port: 2201))
        XCTAssertTrue(customPortKnownHost.matches(hostname: "api.example.com", port: 2201))
        XCTAssertFalse(customPortKnownHost.matches(hostname: "api.example.com", port: 22))
    }
}
