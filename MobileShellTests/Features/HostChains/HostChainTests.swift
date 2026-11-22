import XCTest
@testable import MobileShell

final class HostChainTests: XCTestCase {
    func testConnectionRequestIncludesHostJumpHostRequest() throws {
        let targetID = UUID(uuidString: "61616161-1111-2222-3333-616161616161")!
        let jumpID = UUID(uuidString: "62626262-1111-2222-3333-626262626262")!
        let target = ShellHost(
            id: targetID,
            name: "private-api",
            address: "10.0.0.12",
            username: "app",
            group: "Production",
            tags: ["ssh"],
            status: .idle,
            jumpHostID: jumpID
        )
        let jump = ShellHost(
            id: jumpID,
            name: "bastion",
            address: "bastion.example.com",
            username: "deploy",
            group: "Production",
            tags: ["ssh"],
            status: .idle
        )
        let vault = InMemoryCredentialVault()
        try vault.savePassword("target-secret", forHostID: targetID)
        try vault.savePassword("jump-secret", forHostID: jumpID)

        let request = try SSHConnectionRequestBuilder(
            credentialVault: vault,
            hosts: [target, jump]
        ).request(for: target)

        XCTAssertEqual(request.hostname, "10.0.0.12")
        XCTAssertEqual(request.jumpChain.map(\.hostname), ["bastion.example.com"])
        XCTAssertEqual(request.jumpChain.first?.username, "deploy")
        XCTAssertEqual(request.jumpChain.first?.password, "jump-secret")
    }

    func testConnectionRequestInheritsGroupJumpHostWhenHostHasNone() throws {
        let target = ShellHost(
            id: UUID(uuidString: "63636363-1111-2222-3333-636363636363")!,
            name: "db",
            address: "10.0.0.20",
            username: "postgres",
            group: "Databases",
            tags: ["ssh"],
            status: .idle
        )
        let groupJumpID = UUID(uuidString: "64646464-1111-2222-3333-646464646464")!
        let jump = ShellHost(
            id: groupJumpID,
            name: "db-bastion",
            address: "db-bastion.example.com",
            username: "deploy",
            group: "Production",
            tags: ["ssh"],
            status: .idle
        )

        let request = try SSHConnectionRequestBuilder(
            hosts: [target, jump],
            hostGroupProfiles: [HostGroupProfile(name: "Databases", identityID: nil, jumpHostID: groupJumpID)]
        ).request(for: target)

        XCTAssertEqual(request.jumpChain.map(\.displayName), ["db-bastion"])
    }

    func testHostJumpHostOverridesGroupJumpHost() throws {
        let hostJumpID = UUID(uuidString: "65656565-1111-2222-3333-656565656565")!
        let groupJumpID = UUID(uuidString: "66666666-1111-2222-3333-666666666666")!
        let target = ShellHost(
            id: UUID(uuidString: "67676767-1111-2222-3333-676767676767")!,
            name: "api",
            address: "10.0.0.30",
            username: "deploy",
            group: "Production",
            tags: ["ssh"],
            status: .idle,
            jumpHostID: hostJumpID
        )
        let hostJump = ShellHost(
            id: hostJumpID,
            name: "host-bastion",
            address: "host-bastion.example.com",
            username: "deploy",
            group: "Production",
            tags: ["ssh"],
            status: .idle
        )
        let groupJump = ShellHost(
            id: groupJumpID,
            name: "group-bastion",
            address: "group-bastion.example.com",
            username: "deploy",
            group: "Production",
            tags: ["ssh"],
            status: .idle
        )

        let request = try SSHConnectionRequestBuilder(
            hosts: [target, hostJump, groupJump],
            hostGroupProfiles: [HostGroupProfile(name: "Production", identityID: nil, jumpHostID: groupJumpID)]
        ).request(for: target)

        XCTAssertEqual(request.jumpChain.map(\.displayName), ["host-bastion"])
    }

    func testStorePersistsHostAndGroupJumpHostReferences() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repository = JSONHostRepository(fileURL: tempDirectory.appendingPathComponent("hosts.json"))
        let jumpID = UUID(uuidString: "68686868-1111-2222-3333-686868686868")!
        let host = ShellHost(
            id: UUID(uuidString: "69696969-1111-2222-3333-696969696969")!,
            name: "api",
            address: "api.internal",
            username: "deploy",
            group: "Production",
            tags: ["ssh"],
            status: .idle,
            jumpHostID: jumpID
        )
        let snapshot = HostPersistenceSnapshot(
            hosts: [host],
            hostGroupProfiles: [HostGroupProfile(name: "Production", identityID: nil, jumpHostID: jumpID)]
        )

        try repository.save(snapshot)
        let reloaded = try repository.load()

        XCTAssertEqual(reloaded.hosts.first?.jumpHostID, jumpID)
        XCTAssertEqual(reloaded.hostGroupProfiles.first?.jumpHostID, jumpID)
    }

    func testRouteSummaryDescribesDirectHostAndInheritedJumpHosts() throws {
        let hostJumpID = UUID(uuidString: "6A6A6A6A-1111-2222-3333-6A6A6A6A6A6A")!
        let groupJumpID = UUID(uuidString: "6B6B6B6B-1111-2222-3333-6B6B6B6B6B6B")!
        let direct = ShellHost(
            id: UUID(uuidString: "6C6C6C6C-1111-2222-3333-6C6C6C6C6C6C")!,
            name: "direct",
            address: "direct.example.com",
            username: "deploy",
            group: "Direct",
            tags: ["ssh"],
            status: .idle
        )
        let hostRouted = ShellHost(
            id: UUID(uuidString: "6D6D6D6D-1111-2222-3333-6D6D6D6D6D6D")!,
            name: "host-routed",
            address: "host-routed.example.com",
            username: "deploy",
            group: "Production",
            tags: ["ssh"],
            status: .idle,
            jumpHostID: hostJumpID
        )
        let groupRouted = ShellHost(
            id: UUID(uuidString: "6E6E6E6E-1111-2222-3333-6E6E6E6E6E6E")!,
            name: "group-routed",
            address: "group-routed.example.com",
            username: "deploy",
            group: "Databases",
            tags: ["ssh"],
            status: .idle
        )
        let staleRouted = ShellHost(
            id: UUID(uuidString: "6F6F6F6F-1111-2222-3333-6F6F6F6F6F6F")!,
            name: "stale-routed",
            address: "stale.example.com",
            username: "deploy",
            group: "Stale",
            tags: ["ssh"],
            status: .idle,
            jumpHostID: UUID(uuidString: "70707070-1111-2222-3333-707070707070")!
        )
        let hostJump = ShellHost(
            id: hostJumpID,
            name: "Host Bastion",
            address: "host-bastion.example.com",
            username: "deploy",
            group: "Production",
            tags: ["ssh"],
            status: .idle
        )
        let groupJump = ShellHost(
            id: groupJumpID,
            name: "DB Bastion",
            address: "db-bastion.example.com",
            username: "deploy",
            group: "Production",
            tags: ["ssh"],
            status: .idle
        )
        let store = MobileShellStore(
            hosts: [direct, hostRouted, groupRouted, staleRouted, hostJump, groupJump],
            hostGroupProfiles: [HostGroupProfile(name: "Databases", identityID: nil, jumpHostID: groupJumpID)]
        )

        XCTAssertNil(store.routeSummary(for: direct))
        XCTAssertEqual(store.routeSummary(for: hostRouted), "Via Host Bastion")
        XCTAssertEqual(store.routeSummary(for: groupRouted), "Via DB Bastion")
        XCTAssertEqual(store.routeSummary(for: staleRouted), "Missing jump host")
    }
}
