import XCTest
@testable import MobileShell

final class TerminalWorkspaceTests: XCTestCase {
    func testCreatingWorkspaceTrimsNameSelectsItAndRecordsHistory() throws {
        let store = MobileShellStore()

        let workspace = try XCTUnwrap(store.createTerminalWorkspace(name: "  Production  "))

        XCTAssertEqual(workspace.name, "Production")
        XCTAssertEqual(store.terminalWorkspaces, [workspace])
        XCTAssertEqual(store.selectedWorkspaceID, workspace.id)
        XCTAssertEqual(store.history.first, "Created workspace Production")
    }

    func testConnectingHostWhileWorkspaceSelectedAddsSessionToWorkspaceAndFiltersVisibleSessions() throws {
        let firstHost = makeHost(name: "api", address: "api.example.com")
        let secondHost = makeHost(name: "db", address: "db.example.com")
        let store = MobileShellStore(hosts: [firstHost, secondHost])
        let workspace = try XCTUnwrap(store.createTerminalWorkspace(name: "Production"))

        store.connect(to: firstHost)
        store.selectTerminalWorkspace(nil)
        store.connect(to: secondHost)
        store.selectTerminalWorkspace(workspace.id)

        XCTAssertEqual(store.visibleTerminalSessions().map(\.hostName), ["api"])
        XCTAssertEqual(store.selectedTerminalSession?.hostName, "api")
    }

    func testConnectingExistingSessionAddsItToSelectedWorkspace() throws {
        let host = makeHost(name: "api", address: "api.example.com")
        let store = MobileShellStore(hosts: [host])

        store.connect(to: host)
        let workspace = try XCTUnwrap(store.createTerminalWorkspace(name: "Incident"))
        store.connect(to: host)

        XCTAssertEqual(
            store.terminalWorkspaces.first(where: { $0.id == workspace.id })?.sessionIDs,
            [try XCTUnwrap(store.selectedSessionID)]
        )
        XCTAssertEqual(store.visibleTerminalSessions().map(\.hostName), ["api"])
    }

    func testClosingSessionRemovesItFromWorkspaceAndClearsEmptyWorkspaceSelection() throws {
        let host = makeHost(name: "api", address: "api.example.com")
        let store = MobileShellStore(hosts: [host])
        _ = try XCTUnwrap(store.createTerminalWorkspace(name: "Production"))
        store.connect(to: host)
        let sessionID = try XCTUnwrap(store.selectedSessionID)

        store.closeTerminalSession(sessionID)

        XCTAssertTrue(store.visibleTerminalSessions().isEmpty)
        XCTAssertNil(store.selectedSessionID)
        XCTAssertEqual(store.terminalWorkspaces.first?.sessionIDs, [])
    }

    func testWorkspacePersistenceRoundTrips() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repository = JSONHostRepository(fileURL: tempDirectory.appendingPathComponent("hosts.json"))
        let workspace = TerminalWorkspace(
            id: UUID(uuidString: "81818181-1111-2222-3333-818181818181")!,
            name: "Production",
            sessionIDs: [UUID(uuidString: "82828282-1111-2222-3333-828282828282")!],
            isBroadcastEnabled: true
        )

        try repository.save(HostPersistenceSnapshot(terminalWorkspaces: [workspace]))
        let reloaded = try repository.load()

        XCTAssertEqual(reloaded.terminalWorkspaces, [workspace])
    }

    @MainActor
    func testBroadcastCommandRunsOnlyInVisibleWorkspaceSessions() async throws {
        let firstHost = makeHost(name: "api", address: "api.example.com")
        let secondHost = makeHost(name: "db", address: "db.example.com")
        let outsideHost = makeHost(name: "cache", address: "cache.example.com")
        let store = MobileShellStore(hosts: [firstHost, secondHost, outsideHost])
        let workspace = try XCTUnwrap(store.createTerminalWorkspace(name: "Production"))

        store.connect(to: firstHost)
        store.connect(to: secondHost)
        store.selectTerminalWorkspace(nil)
        store.connect(to: outsideHost)
        store.selectTerminalWorkspace(workspace.id)

        await store.broadcastCommand("uptime")

        let visibleSessions = store.visibleTerminalSessions()
        XCTAssertEqual(visibleSessions.map(\.hostName), ["api", "db"])
        XCTAssertTrue(visibleSessions.allSatisfy { $0.lines.contains("$ uptime") })
        XCTAssertFalse(
            try XCTUnwrap(store.terminalSessions.first { $0.hostName == "cache" })
                .lines
                .contains("$ uptime")
        )
        XCTAssertEqual(store.history.first, "Broadcast uptime to Production")
    }

    @MainActor
    func testBroadcastCommandIgnoresBlankInput() async throws {
        let host = makeHost(name: "api", address: "api.example.com")
        let store = MobileShellStore(hosts: [host])
        let workspace = try XCTUnwrap(store.createTerminalWorkspace(name: "Production"))
        store.connect(to: host)
        let linesBeforeBroadcast = store.selectedTerminalSession?.lines

        await store.broadcastCommand("   ")

        XCTAssertEqual(store.selectedWorkspaceID, workspace.id)
        XCTAssertEqual(store.selectedTerminalSession?.lines, linesBeforeBroadcast)
        XCTAssertEqual(store.history.first, "Connected to api")
    }

    func testTogglingBroadcastModePersistsWorkspaceSetting() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repository = JSONHostRepository(fileURL: tempDirectory.appendingPathComponent("hosts.json"))
        let workspace = TerminalWorkspace(
            id: UUID(uuidString: "83838383-1111-2222-3333-838383838383")!,
            name: "Production"
        )
        try repository.save(HostPersistenceSnapshot(terminalWorkspaces: [workspace]))
        let store = try MobileShellStore(repository: repository, credentialVault: InMemoryCredentialVault())

        store.setBroadcastEnabled(true, for: workspace.id)

        XCTAssertEqual(store.terminalWorkspaces.first?.isBroadcastEnabled, true)
        XCTAssertEqual(try repository.load().terminalWorkspaces.first?.isBroadcastEnabled, true)
    }

    private func makeHost(name: String, address: String) -> ShellHost {
        ShellHost(
            id: UUID(),
            name: name,
            address: address,
            username: "deploy",
            group: "Production",
            tags: ["ssh"],
            status: .idle
        )
    }
}
