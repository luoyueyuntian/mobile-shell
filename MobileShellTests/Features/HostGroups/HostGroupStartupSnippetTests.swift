import XCTest
@testable import MobileShell

final class HostGroupStartupSnippetTests: XCTestCase {
    func testUpsertingGroupProfileStoresStartupSnippetReference() throws {
        let snippetID = UUID(uuidString: "B1B1B1B1-1111-2222-3333-B1B1B1B1B1B1")!
        let store = MobileShellStore()

        let profile = try XCTUnwrap(
            store.upsertHostGroupProfile(
                name: " Production ",
                identityID: nil,
                startupSnippetID: snippetID
            )
        )

        XCTAssertEqual(profile.name, "Production")
        XCTAssertEqual(profile.startupSnippetID, snippetID)
        XCTAssertEqual(store.hostGroupProfiles, [profile])
        XCTAssertEqual(store.history.first, "Updated group Production")
    }

    func testStartupSnippetTitleFallsBackToGroupProfile() throws {
        let snippet = makeSnippet(title: "Attach tmux", command: "tmux attach -t work")
        let host = makeHost(name: "api", group: "Production")
        let store = MobileShellStore(
            hosts: [host],
            snippets: [snippet],
            hostGroupProfiles: [
                HostGroupProfile(name: "Production", identityID: nil, startupSnippetID: snippet.id)
            ]
        )

        XCTAssertEqual(store.startupSnippetTitle(for: host), "Attach tmux")
    }

    func testHostStartupSnippetOverridesGroupStartupSnippet() throws {
        let groupSnippet = makeSnippet(title: "Group Startup", command: "uptime")
        let hostSnippet = makeSnippet(title: "Host Startup", command: "whoami")
        let host = makeHost(name: "api", group: "Production", startupSnippetID: hostSnippet.id)
        let store = MobileShellStore(
            hosts: [host],
            snippets: [groupSnippet, hostSnippet],
            hostGroupProfiles: [
                HostGroupProfile(name: "Production", identityID: nil, startupSnippetID: groupSnippet.id)
            ]
        )

        XCTAssertEqual(store.startupSnippetTitle(for: host), "Host Startup")
    }

    func testConnectingHostRunsInheritedGroupStartupSnippet() throws {
        let snippet = makeSnippet(title: "Attach tmux", command: "tmux attach -t work")
        let host = makeHost(name: "api", group: "Production")
        let store = MobileShellStore(
            hosts: [host],
            snippets: [snippet],
            hostGroupProfiles: [
                HostGroupProfile(name: "Production", identityID: nil, startupSnippetID: snippet.id)
            ]
        )

        store.connect(to: host)

        let session = try XCTUnwrap(store.selectedTerminalSession)
        XCTAssertTrue(session.lines.contains("$ tmux attach -t work"))
        XCTAssertEqual(store.history.first, "Ran startup snippet Attach tmux on api")
    }

    func testDeletingSnippetDetachesGroupProfilesAndPersistsCleanup() throws {
        let snippet = makeSnippet(title: "Attach tmux", command: "tmux attach -t work")
        let profile = HostGroupProfile(name: "Production", identityID: nil, startupSnippetID: snippet.id)
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repository = JSONHostRepository(fileURL: tempDirectory.appendingPathComponent("hosts.json"))
        try repository.save(HostPersistenceSnapshot(snippets: [snippet], hostGroupProfiles: [profile]))
        let store = try MobileShellStore(repository: repository, credentialVault: InMemoryCredentialVault())

        store.deleteSnippet(snippet)

        XCTAssertNil(store.hostGroupProfiles.first?.startupSnippetID)
        XCTAssertNil(try repository.load().hostGroupProfiles.first?.startupSnippetID)
    }

    private func makeSnippet(title: String, command: String) -> ShellSnippet {
        ShellSnippet(id: UUID(), title: title, command: command)
    }

    private func makeHost(
        name: String,
        group: String,
        startupSnippetID: ShellSnippet.ID? = nil
    ) -> ShellHost {
        ShellHost(
            id: UUID(),
            name: name,
            address: "\(name).example.com",
            username: "deploy",
            group: group,
            tags: ["ssh"],
            status: .idle,
            startupSnippetID: startupSnippetID
        )
    }
}
