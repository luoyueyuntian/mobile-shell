import XCTest
@testable import MobileShell

final class StartupSnippetTests: XCTestCase {
    func testHostStartupSnippetReferencePersists() throws {
        let snippetID = UUID(uuidString: "A1A1A1A1-1111-2222-3333-A1A1A1A1A1A1")!
        let host = makeHost(name: "api", startupSnippetID: snippetID)
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repository = JSONHostRepository(fileURL: tempDirectory.appendingPathComponent("hosts.json"))

        try repository.save(HostPersistenceSnapshot(hosts: [host]))
        let reloaded = try repository.load()

        XCTAssertEqual(reloaded.hosts.first?.startupSnippetID, snippetID)
    }

    func testAddingAndUpdatingHostCanAttachStartupSnippet() throws {
        let snippet = ShellSnippet(
            id: UUID(uuidString: "A2A2A2A2-1111-2222-3333-A2A2A2A2A2A2")!,
            title: "Attach tmux",
            command: "tmux attach -t work"
        )
        let store = MobileShellStore(snippets: [snippet])

        let host = try XCTUnwrap(
            try store.addHost(
                name: " api ",
                address: " api.example.com ",
                port: 22,
                username: " deploy ",
                group: " Production ",
                tags: "ssh,prod",
                password: "",
                startupSnippetID: snippet.id
            )
        )

        XCTAssertEqual(host.startupSnippetID, snippet.id)
        XCTAssertEqual(store.startupSnippetTitle(for: host), "Attach tmux")

        let updated = try XCTUnwrap(
            try store.updateHost(
                host,
                name: "api",
                address: "api.example.com",
                port: 22,
                username: "deploy",
                group: "Production",
                tags: "ssh",
                password: "",
                startupSnippetID: nil
            )
        )

        XCTAssertNil(updated.startupSnippetID)
        XCTAssertNil(store.startupSnippetTitle(for: updated))
    }

    func testConnectingNewSessionRunsStartupSnippetOnce() throws {
        let snippet = ShellSnippet(
            id: UUID(uuidString: "A3A3A3A3-1111-2222-3333-A3A3A3A3A3A3")!,
            title: "Attach tmux",
            command: "tmux attach -t work"
        )
        let host = makeHost(name: "api", startupSnippetID: snippet.id)
        let store = MobileShellStore(hosts: [host], snippets: [snippet])

        store.connect(to: host)
        store.connect(to: host)

        let session = try XCTUnwrap(store.selectedTerminalSession)
        XCTAssertEqual(session.lines.filter { $0 == "$ tmux attach -t work" }.count, 1)
        XCTAssertTrue(session.lines.contains("Command queued in preview terminal: tmux attach -t work"))
        XCTAssertEqual(store.history.first, "Ran startup snippet Attach tmux on api")
    }

    func testStartupSnippetIsWrittenToSessionLog() throws {
        let snippet = ShellSnippet(
            id: UUID(uuidString: "A4A4A4A4-1111-2222-3333-A4A4A4A4A4A4")!,
            title: "Whoami",
            command: "whoami"
        )
        let host = makeHost(name: "api", startupSnippetID: snippet.id)
        let store = MobileShellStore(hosts: [host], snippets: [snippet])

        store.connect(to: host)

        let log = try XCTUnwrap(store.sessionLogs.first)
        XCTAssertTrue(log.lines.contains("$ whoami"))
        XCTAssertTrue(log.lines.contains("deploy"))
    }

    func testDeletingSnippetDetachesItFromHostsAndPersistsCleanup() throws {
        let snippet = ShellSnippet(
            id: UUID(uuidString: "A5A5A5A5-1111-2222-3333-A5A5A5A5A5A5")!,
            title: "Attach tmux",
            command: "tmux attach -t work"
        )
        let host = makeHost(name: "api", startupSnippetID: snippet.id)
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repository = JSONHostRepository(fileURL: tempDirectory.appendingPathComponent("hosts.json"))
        try repository.save(HostPersistenceSnapshot(hosts: [host], snippets: [snippet]))
        let store = try MobileShellStore(repository: repository, credentialVault: InMemoryCredentialVault())

        store.deleteSnippet(snippet)

        XCTAssertNil(store.hosts.first?.startupSnippetID)
        XCTAssertNil(try repository.load().hosts.first?.startupSnippetID)
    }

    private func makeHost(
        name: String,
        startupSnippetID: ShellSnippet.ID?
    ) -> ShellHost {
        ShellHost(
            id: UUID(),
            name: name,
            address: "\(name).example.com",
            username: "deploy",
            group: "Production",
            tags: ["ssh"],
            status: .idle,
            startupSnippetID: startupSnippetID
        )
    }
}
