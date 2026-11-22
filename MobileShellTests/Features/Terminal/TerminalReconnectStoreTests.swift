import XCTest
@testable import MobileShell

final class TerminalReconnectStoreTests: XCTestCase {
    @MainActor
    func testReconnectingTerminalSessionMarksItConnectedAndRefreshesPrompt() throws {
        let hostID = UUID(uuidString: "91919191-2222-3333-4444-919191919191")!
        let host = ShellHost(
            id: hostID,
            name: "edge-prod",
            address: "edge.example.com",
            username: "deploy",
            group: "Production",
            tags: ["ssh"],
            status: .idle
        )
        let store = MobileShellStore(hosts: [host])

        store.connect(to: host)
        let sessionID = try XCTUnwrap(store.selectedSessionID)
        store.markTerminalSessionDisconnected(sessionID, reason: "Network lost")

        XCTAssertEqual(store.selectedTerminalSession?.state, .disconnected)
        XCTAssertTrue(store.selectedTerminalSession?.lines.contains("Disconnected: Network lost") == true)

        store.reconnectTerminalSession(sessionID)

        XCTAssertEqual(store.selectedTerminalSession?.state, .connected)
        XCTAssertEqual(store.selectedTerminalSession?.prompt, "deploy@edge-prod:~$")
        XCTAssertTrue(store.selectedTerminalSession?.lines.contains("Reconnected to edge-prod") == true)
        XCTAssertEqual(store.history.first, "Reconnected terminal edge-prod")
    }

    @MainActor
    func testReconnectingMoshTerminalSessionDoesNotReconnectAndShowsUnavailableMessage() throws {
        let hostID = UUID(uuidString: "81818181-8181-8181-8181-818181818181")!
        let sessionID = UUID(uuidString: "82828282-8282-8282-8282-828282828282")!
        let host = ShellHost(
            id: hostID,
            name: "lab-mosh",
            address: "lab.example.com",
            username: "ops",
            group: "Lab",
            tags: ["mosh"],
            status: .idle,
            protocol: .mosh,
            moshConfiguration: .default
        )
        let store = MobileShellStore(hosts: [host])
        store.terminalSessions = [
            TerminalSession(
                id: sessionID,
                hostID: hostID,
                hostName: host.name,
                prompt: "ops@lab-mosh:~$",
                lines: ["Disconnected: Network lost"],
                state: .disconnected
            )
        ]

        store.reconnectTerminalSession(sessionID)

        XCTAssertEqual(store.selectedTerminalSession?.state, .disconnected)
        XCTAssertEqual(store.selectedTerminalSession?.prompt, "ops@lab-mosh:~$")
        XCTAssertEqual(store.selectedTerminalSession?.lines, ["Disconnected: Network lost"])
        XCTAssertEqual(store.terminalUnavailableMessage, "Mosh configuration is saved for this host, but real Mosh sessions are not available in this version yet.")
        XCTAssertTrue(store.history.isEmpty)
    }
}
