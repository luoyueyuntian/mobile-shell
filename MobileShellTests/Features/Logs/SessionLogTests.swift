import XCTest
@testable import MobileShell

final class SessionLogTests: XCTestCase {
    func testLogsSectionExposesNavigationMetadata() {
        XCTAssertEqual(ShellSection.logs.title, "Logs")
        XCTAssertEqual(ShellSection.logs.symbolName, "doc.text.magnifyingglass")
        XCTAssertEqual(ShellSection.logs.compactTitle, "Logs")
    }

    func testConnectingHostCreatesSessionLogWithInitialTerminalLines() throws {
        let host = makeHost()
        let store = MobileShellStore(hosts: [host])

        store.connect(to: host)

        let log = try XCTUnwrap(store.sessionLogs.first)
        XCTAssertEqual(log.hostID, host.id)
        XCTAssertEqual(log.hostName, "api-prod")
        XCTAssertEqual(log.lines, store.selectedTerminalSession?.lines)
        XCTAssertNil(log.endedAt)
    }

    func testRunningPreviewCommandAppendsPromptAndOutputToSessionLog() throws {
        let host = makeHost()
        let store = MobileShellStore(hosts: [host])

        store.connect(to: host)
        store.runCommand("uptime")

        let log = try XCTUnwrap(store.sessionLogs.first)
        XCTAssertTrue(log.lines.contains("$ uptime"))
        XCTAssertTrue(log.lines.contains { $0.contains("load average") })
    }

    func testClosingTerminalSessionMarksSessionLogEnded() throws {
        let host = makeHost()
        let store = MobileShellStore(hosts: [host])

        store.connect(to: host)
        let sessionID = try XCTUnwrap(store.selectedSessionID)
        store.closeTerminalSession(sessionID)

        XCTAssertNotNil(store.sessionLogs.first?.endedAt)
    }

    func testStorePersistsSessionLogs() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repository = JSONHostRepository(fileURL: tempDirectory.appendingPathComponent("hosts.json"))
        let log = SessionLog(
            id: UUID(uuidString: "71717171-1111-2222-3333-717171717171")!,
            hostID: UUID(uuidString: "72727272-1111-2222-3333-727272727272")!,
            hostName: "api-prod",
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200),
            lines: ["connected", "$ uptime", "load average: 0.12"]
        )

        try repository.save(HostPersistenceSnapshot(sessionLogs: [log]))
        let reloaded = try repository.load()

        XCTAssertEqual(reloaded.sessionLogs, [log])
    }

    private func makeHost() -> ShellHost {
        ShellHost(
            id: UUID(uuidString: "73737373-1111-2222-3333-737373737373")!,
            name: "api-prod",
            address: "api.example.com",
            username: "deploy",
            group: "Production",
            tags: ["ssh"],
            status: .idle
        )
    }
}
