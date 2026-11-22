import XCTest
@testable import MobileShell

final class SnippetMultiExecutionTests: XCTestCase {
    @MainActor
    func testRunningSnippetInVisibleTerminalsTargetsAllSessionsWhenNoWorkspaceSelected() async throws {
        let firstHost = makeHost(name: "api", address: "api.example.com")
        let secondHost = makeHost(name: "db", address: "db.example.com")
        let snippet = makeSnippet(title: "Disk Usage", command: "df -h")
        let store = MobileShellStore(hosts: [firstHost, secondHost], snippets: [snippet])

        store.connect(to: firstHost)
        store.connect(to: secondHost)

        let count = await store.runSnippetInVisibleTerminals(snippet)

        XCTAssertEqual(count, 2)
        XCTAssertTrue(store.terminalSessions.allSatisfy { $0.lines.contains("$ df -h") })
        XCTAssertEqual(store.history.first, "Ran snippet Disk Usage on 2 terminals")
    }

    @MainActor
    func testRunningSnippetInSelectedWorkspaceTargetsOnlyVisibleSessions() async throws {
        let firstHost = makeHost(name: "api", address: "api.example.com")
        let secondHost = makeHost(name: "db", address: "db.example.com")
        let outsideHost = makeHost(name: "cache", address: "cache.example.com")
        let snippet = makeSnippet(title: "Uptime", command: "uptime")
        let store = MobileShellStore(hosts: [firstHost, secondHost, outsideHost], snippets: [snippet])
        let workspace = try XCTUnwrap(store.createTerminalWorkspace(name: "Production"))

        store.connect(to: firstHost)
        store.connect(to: secondHost)
        store.selectTerminalWorkspace(nil)
        store.connect(to: outsideHost)
        store.selectTerminalWorkspace(workspace.id)

        let count = await store.runSnippetInVisibleTerminals(snippet)

        XCTAssertEqual(count, 2)
        XCTAssertTrue(store.visibleTerminalSessions().allSatisfy { $0.lines.contains("$ uptime") })
        XCTAssertFalse(
            try XCTUnwrap(store.terminalSessions.first { $0.hostName == "cache" })
                .lines
                .contains("$ uptime")
        )
        XCTAssertEqual(store.history.first, "Ran snippet Uptime on 2 terminals")
    }

    @MainActor
    func testRunningSnippetWithNoVisibleTerminalsReturnsZeroAndDoesNotRecordHistory() async {
        let snippet = makeSnippet(title: "Disk Usage", command: "df -h")
        let store = MobileShellStore(snippets: [snippet])

        let count = await store.runSnippetInVisibleTerminals(snippet)

        XCTAssertEqual(count, 0)
        XCTAssertTrue(store.history.isEmpty)
    }

    @MainActor
    func testRunningStaleSnippetReturnsZero() async {
        let host = makeHost(name: "api", address: "api.example.com")
        let storedSnippet = makeSnippet(title: "Disk Usage", command: "df -h")
        let staleSnippet = makeSnippet(title: "Stale", command: "whoami")
        let store = MobileShellStore(hosts: [host], snippets: [storedSnippet])
        store.connect(to: host)

        let count = await store.runSnippetInVisibleTerminals(staleSnippet)

        XCTAssertEqual(count, 0)
        XCTAssertFalse(try XCTUnwrap(store.selectedTerminalSession).lines.contains("$ whoami"))
        XCTAssertEqual(store.history.first, "Connected to api")
    }

    private func makeSnippet(title: String, command: String) -> ShellSnippet {
        ShellSnippet(id: UUID(), title: title, command: command)
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
