import XCTest
@testable import MobileShell

final class TerminalThemeInheritanceTests: XCTestCase {
    func testTerminalThemeDefaultsToObsidianNeon() {
        let host = makeHost(name: "api")
        let store = MobileShellStore(hosts: [host])

        XCTAssertEqual(store.terminalTheme(for: host), .obsidianNeon)
    }

    func testTerminalThemeFallsBackToGroupTheme() {
        let host = makeHost(name: "api", group: "Production")
        let store = MobileShellStore(
            hosts: [host],
            hostGroupProfiles: [
                HostGroupProfile(name: "Production", identityID: nil, terminalTheme: .solarizedDark)
            ]
        )

        XCTAssertEqual(store.terminalTheme(for: host), .solarizedDark)
    }

    func testHostTerminalThemeOverridesGroupTheme() {
        let host = makeHost(name: "api", group: "Production", terminalTheme: .everforestDark)
        let store = MobileShellStore(
            hosts: [host],
            hostGroupProfiles: [
                HostGroupProfile(name: "Production", identityID: nil, terminalTheme: .solarizedDark)
            ]
        )

        XCTAssertEqual(store.terminalTheme(for: host), .everforestDark)
    }

    func testHostAndGroupTerminalThemesPersist() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = JSONHostRepository(fileURL: directory.appendingPathComponent("vault.json"))
        let host = makeHost(name: "api", group: "Production", terminalTheme: .everforestDark)
        let profile = HostGroupProfile(name: "Production", identityID: nil, terminalTheme: .solarizedDark)

        try repository.save(HostPersistenceSnapshot(hosts: [host], hostGroupProfiles: [profile]))
        let loaded = try repository.load()

        XCTAssertEqual(loaded.hosts.first?.terminalTheme, .everforestDark)
        XCTAssertEqual(loaded.hostGroupProfiles.first?.terminalTheme, .solarizedDark)
    }

    func testUpsertingGroupProfileStoresTerminalTheme() throws {
        let store = MobileShellStore()

        let profile = try XCTUnwrap(store.upsertHostGroupProfile(
            name: "Production",
            identityID: nil,
            terminalTheme: .solarizedDark
        ))

        XCTAssertEqual(profile.terminalTheme, .solarizedDark)
        XCTAssertEqual(store.hostGroupProfiles.first?.terminalTheme, .solarizedDark)
    }

    private func makeHost(
        name: String,
        group: String = "Production",
        terminalTheme: TerminalTheme? = nil
    ) -> ShellHost {
        ShellHost(
            id: UUID(),
            name: name,
            address: "\(name).example.com",
            username: "deploy",
            group: group,
            tags: ["ssh"],
            status: .idle,
            terminalTheme: terminalTheme
        )
    }
}
