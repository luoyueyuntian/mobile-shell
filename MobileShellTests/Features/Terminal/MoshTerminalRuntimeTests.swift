import XCTest
@testable import MobileShell

final class MoshTerminalRuntimeTests: XCTestCase {
    @MainActor
    func testOpeningMoshHostRunsPreparationThenRuntimeAndCreatesSession() async throws {
        let host = ShellHost(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            name: "lab-mosh",
            address: "lab.example.com",
            username: "ops",
            group: "Lab",
            tags: ["mosh"],
            status: .idle,
            protocol: .mosh,
            moshConfiguration: .default
        )
        let preparationClient = RecordingMoshPreparationClient(
            result: .success(
                MoshServerLaunchResult(
                    port: 60004,
                    key: "4NeCCgvZFe2RnPgrcU1PQw",
                    serverOutput: "MOSH CONNECT 60004 4NeCCgvZFe2RnPgrcU1PQw"
                )
            )
        )
        let runtimeSession = RecordingMoshRuntimeSession(outputs: ["mosh-ready", "ops@lab:~$"])
        let runtimeClient = RecordingMoshRuntimeClient(result: .success(runtimeSession))
        let store = MobileShellStore(
            hosts: [host],
            moshPreparationClient: preparationClient,
            moshRuntimeClient: runtimeClient
        )

        await store.openInteractiveTerminal(for: host)
        try await Task.sleep(nanoseconds: 10_000_000)

        XCTAssertEqual(preparationClient.preparedHostIDs, [host.id])
        XCTAssertEqual(runtimeClient.startedHostIDs, [host.id])
        XCTAssertEqual(store.terminalSessions.count, 1)
        XCTAssertEqual(store.selectedTerminalSession?.hostName, "lab-mosh")
        XCTAssertEqual(store.selectedTerminalSession?.state, .connected)
        XCTAssertTrue(store.selectedTerminalSession?.lines.contains("mosh-ready") == true)
    }

    @MainActor
    func testMissingMoshServerShowsInstallGuidanceAndCreatesNoSession() async {
        let host = ShellHost(
            id: UUID(),
            name: "lab-mosh",
            address: "lab.example.com",
            username: "ops",
            group: "Lab",
            tags: ["mosh"],
            status: .idle,
            protocol: .mosh,
            moshConfiguration: .default
        )
        let preparationClient = RecordingMoshPreparationClient(
            result: .failure(MoshPreparationError.moshServerMissing)
        )
        let runtimeClient = RecordingMoshRuntimeClient(
            result: .failure(MoshRuntimeError.connectFailed("unused"))
        )
        let store = MobileShellStore(
            hosts: [host],
            moshPreparationClient: preparationClient,
            moshRuntimeClient: runtimeClient
        )

        await store.openInteractiveTerminal(for: host)

        XCTAssertTrue(store.terminalSessions.isEmpty)
        XCTAssertEqual(
            store.terminalUnavailableMessage,
            "Mosh is configured for this host, but `mosh-server` is not installed on the remote machine. Install `mosh` on the server and try again."
        )
        XCTAssertTrue(runtimeClient.startedHostIDs.isEmpty)
    }

    @MainActor
    func testMoshRuntimeFailureShowsErrorAndCreatesNoSession() async {
        let host = ShellHost(
            id: UUID(),
            name: "lab-mosh",
            address: "lab.example.com",
            username: "ops",
            group: "Lab",
            tags: ["mosh"],
            status: .idle,
            protocol: .mosh,
            moshConfiguration: .default
        )
        let preparationClient = RecordingMoshPreparationClient(
            result: .success(
                MoshServerLaunchResult(
                    port: 60004,
                    key: "4NeCCgvZFe2RnPgrcU1PQw",
                    serverOutput: "MOSH CONNECT 60004 4NeCCgvZFe2RnPgrcU1PQw"
                )
            )
        )
        let runtimeClient = RecordingMoshRuntimeClient(
            result: .failure(MoshRuntimeError.connectFailed("UDP handshake failed"))
        )
        let store = MobileShellStore(
            hosts: [host],
            moshPreparationClient: preparationClient,
            moshRuntimeClient: runtimeClient
        )

        await store.openInteractiveTerminal(for: host)

        XCTAssertTrue(store.terminalSessions.isEmpty)
        XCTAssertEqual(store.terminalUnavailableMessage, "Mosh connection failed: UDP handshake failed")
    }

    @MainActor
    func testReconnectingDisconnectedMoshSessionRunsPreparationThenRuntimeAndReconnectsSession() async throws {
        let host = ShellHost(
            id: UUID(uuidString: "66666666-2222-3333-4444-555555555555")!,
            name: "lab-mosh",
            address: "lab.example.com",
            username: "ops",
            group: "Lab",
            tags: ["mosh"],
            status: .idle,
            protocol: .mosh,
            moshConfiguration: .default
        )
        let preparationClient = RecordingMoshPreparationClient(
            result: .success(
                MoshServerLaunchResult(
                    port: 60004,
                    key: "4NeCCgvZFe2RnPgrcU1PQw",
                    serverOutput: "MOSH CONNECT 60004 4NeCCgvZFe2RnPgrcU1PQw"
                )
            )
        )
        let runtimeSession = RecordingMoshRuntimeSession(outputs: ["mosh-reconnected"])
        let runtimeClient = RecordingMoshRuntimeClient(result: .success(runtimeSession))
        let store = MobileShellStore(
            hosts: [host],
            moshPreparationClient: preparationClient,
            moshRuntimeClient: runtimeClient
        )
        let disconnectedSession = TerminalSession(
            id: UUID(uuidString: "77777777-2222-3333-4444-555555555555")!,
            hostID: host.id,
            hostName: host.name,
            prompt: "ops@lab-mosh:~$",
            lines: ["Disconnected: network lost"],
            state: .disconnected
        )
        store.terminalSessions = [disconnectedSession]

        store.reconnectTerminalSession(disconnectedSession.id)
        try await Task.sleep(nanoseconds: 10_000_000)

        XCTAssertEqual(preparationClient.preparedHostIDs, [host.id])
        XCTAssertEqual(runtimeClient.startedHostIDs, [host.id])
        XCTAssertEqual(store.terminalSessions.count, 1)
        XCTAssertEqual(store.selectedTerminalSession?.id, disconnectedSession.id)
        XCTAssertEqual(store.selectedTerminalSession?.state, .connected)
        XCTAssertTrue(store.selectedTerminalSession?.lines.contains("mosh-reconnected") == true)
        XCTAssertNil(store.terminalUnavailableMessage)
    }

    @MainActor
    func testClosingLiveMoshSessionClosesRuntimeSession() async throws {
        let host = ShellHost(
            id: UUID(uuidString: "88888888-2222-3333-4444-555555555555")!,
            name: "lab-mosh",
            address: "lab.example.com",
            username: "ops",
            group: "Lab",
            tags: ["mosh"],
            status: .idle,
            protocol: .mosh,
            moshConfiguration: .default
        )
        let preparationClient = RecordingMoshPreparationClient(
            result: .success(
                MoshServerLaunchResult(
                    port: 60004,
                    key: "4NeCCgvZFe2RnPgrcU1PQw",
                    serverOutput: "MOSH CONNECT 60004 4NeCCgvZFe2RnPgrcU1PQw"
                )
            )
        )
        let runtimeSession = RecordingMoshRuntimeSession(outputs: ["mosh-ready"])
        let runtimeClient = RecordingMoshRuntimeClient(result: .success(runtimeSession))
        let store = MobileShellStore(
            hosts: [host],
            moshPreparationClient: preparationClient,
            moshRuntimeClient: runtimeClient
        )

        await store.openInteractiveTerminal(for: host)
        try await Task.sleep(nanoseconds: 10_000_000)
        let sessionID = try XCTUnwrap(store.selectedTerminalSession?.id)

        store.closeTerminalSession(sessionID)
        try await Task.sleep(nanoseconds: 10_000_000)

        XCTAssertEqual(runtimeSession.closeCount, 1)
        XCTAssertTrue(store.terminalSessions.isEmpty)
    }

    @MainActor
    func testOpeningExistingLiveMoshSessionReusesRuntimeWithoutRepreparing() async throws {
        let host = ShellHost(
            id: UUID(uuidString: "99999999-3333-4444-5555-666666666666")!,
            name: "lab-mosh",
            address: "lab.example.com",
            username: "ops",
            group: "Lab",
            tags: ["mosh"],
            status: .idle,
            protocol: .mosh,
            moshConfiguration: .default
        )
        let preparationClient = RecordingMoshPreparationClient(
            result: .success(
                MoshServerLaunchResult(
                    port: 60004,
                    key: "4NeCCgvZFe2RnPgrcU1PQw",
                    serverOutput: "MOSH CONNECT 60004 4NeCCgvZFe2RnPgrcU1PQw"
                )
            )
        )
        let runtimeSession = RecordingMoshRuntimeSession(outputs: ["mosh-ready"])
        let runtimeClient = RecordingMoshRuntimeClient(result: .success(runtimeSession))
        let store = MobileShellStore(
            hosts: [host],
            moshPreparationClient: preparationClient,
            moshRuntimeClient: runtimeClient
        )

        await store.openInteractiveTerminal(for: host)
        try await Task.sleep(nanoseconds: 10_000_000)
        await store.openInteractiveTerminal(for: host)
        try await Task.sleep(nanoseconds: 10_000_000)

        XCTAssertEqual(preparationClient.preparedHostIDs, [host.id])
        XCTAssertEqual(runtimeClient.startedHostIDs, [host.id])
        XCTAssertEqual(store.terminalSessions.count, 1)
        XCTAssertEqual(store.selectedTerminalSession?.state, .connected)
    }
}

private final class RecordingMoshPreparationClient: MoshPreparationClient, @unchecked Sendable {
    var preparedHostIDs: [UUID] = []
    let result: Result<MoshServerLaunchResult, Error>

    init(result: Result<MoshServerLaunchResult, Error>) {
        self.result = result
    }

    func prepare(
        using request: SSHConnectionRequest,
        configuration: MoshHostConfiguration
    ) async throws -> MoshServerLaunchResult {
        preparedHostIDs.append(request.hostID)
        return try result.get()
    }
}

private final class RecordingMoshRuntimeSession: MoshRuntimeSession, @unchecked Sendable {
    let outputStream: AsyncStream<String>
    private let continuation: AsyncStream<String>.Continuation
    private(set) var sentInputs: [String] = []
    private(set) var closeCount = 0

    init(outputs: [String]) {
        var captured: AsyncStream<String>.Continuation!
        outputStream = AsyncStream { continuation in
            captured = continuation
        }
        continuation = captured
        for output in outputs {
            continuation.yield(output)
        }
    }

    func send(_ input: String) async throws {
        sentInputs.append(input)
    }

    func close() async {
        closeCount += 1
        continuation.finish()
    }
}

private final class RecordingMoshRuntimeClient: MoshRuntimeClient, @unchecked Sendable {
    var startedHostIDs: [UUID] = []
    let result: Result<any MoshRuntimeSession, Error>

    init(result: Result<any MoshRuntimeSession, Error>) {
        self.result = result
    }

    func connect(host: ShellHost, launchResult: MoshServerLaunchResult) async throws -> any MoshRuntimeSession {
        startedHostIDs.append(host.id)
        return try result.get()
    }
}
