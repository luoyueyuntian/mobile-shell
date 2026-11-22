import XCTest
@testable import MobileShell

final class TerminalFontSizeInheritanceTests: XCTestCase {
    func testTerminalFontSizeDefaultsToStandard() {
        let host = makeHost(name: "api")
        let store = MobileShellStore(hosts: [host])

        XCTAssertEqual(store.terminalFontSize(for: host), .standard)
        XCTAssertEqual(store.terminalFontSize(for: host).pointSize, 13)
    }

    func testTerminalFontSizeFallsBackToGroupFontSize() {
        let host = makeHost(name: "api", group: "Production")
        let store = MobileShellStore(
            hosts: [host],
            hostGroupProfiles: [
                HostGroupProfile(name: "Production", identityID: nil, terminalFontSize: .large)
            ]
        )

        XCTAssertEqual(store.terminalFontSize(for: host), .large)
    }

    func testHostTerminalFontSizeOverridesGroupFontSize() {
        let host = makeHost(name: "api", group: "Production", terminalFontSize: .extraLarge)
        let store = MobileShellStore(
            hosts: [host],
            hostGroupProfiles: [
                HostGroupProfile(name: "Production", identityID: nil, terminalFontSize: .small)
            ]
        )

        XCTAssertEqual(store.terminalFontSize(for: host), .extraLarge)
    }

    func testHostAndGroupTerminalFontSizesPersist() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = JSONHostRepository(fileURL: directory.appendingPathComponent("vault.json"))
        let host = makeHost(name: "api", group: "Production", terminalFontSize: .extraLarge)
        let profile = HostGroupProfile(name: "Production", identityID: nil, terminalFontSize: .large)

        try repository.save(HostPersistenceSnapshot(hosts: [host], hostGroupProfiles: [profile]))
        let loaded = try repository.load()

        XCTAssertEqual(loaded.hosts.first?.terminalFontSize, .extraLarge)
        XCTAssertEqual(loaded.hostGroupProfiles.first?.terminalFontSize, .large)
    }

    func testUpsertingGroupProfileStoresTerminalFontSize() throws {
        let store = MobileShellStore()

        let profile = try XCTUnwrap(store.upsertHostGroupProfile(
            name: "Production",
            identityID: nil,
            terminalFontSize: .large
        ))

        XCTAssertEqual(profile.terminalFontSize, .large)
        XCTAssertEqual(store.hostGroupProfiles.first?.terminalFontSize, .large)
    }

    private func makeHost(
        name: String,
        group: String = "Production",
        terminalFontSize: TerminalFontSize? = nil
    ) -> ShellHost {
        ShellHost(
            id: UUID(),
            name: name,
            address: "\(name).example.com",
            username: "deploy",
            group: group,
            tags: ["ssh"],
            status: .idle,
            terminalFontSize: terminalFontSize
        )
    }
}
