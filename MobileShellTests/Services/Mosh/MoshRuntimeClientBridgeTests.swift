import XCTest
@testable import MobileShell

final class MoshRuntimeClientBridgeTests: XCTestCase {
    func testConnectBuildsOptionsUsingLaunchResultRemoteIPAddressAndPredictionMode() async throws {
        let adapter = RecordingMoshBridgeSessionAdapter()
        let capturedOptions = CapturedMoshBridgeOptionsBox()
        let bridge = MoshRuntimeClientBridge(sessionFactory: { options in
            capturedOptions.value = options
            return adapter
        })
        let host = makeMoshHost(
            configuration: MoshHostConfiguration(
                udpPort: 60010,
                serverCommand: "mosh-server new -s",
                predictiveEcho: false,
                useExperimentalConnection: true
            )
        )

        _ = try await bridge.connect(
            host: host,
            launchResult: MoshServerLaunchResult(
                port: 60004,
                key: "key",
                serverOutput: "MOSH CONNECT 60004 key",
                remoteIPAddress: "203.0.113.10"
            )
        )

        XCTAssertEqual(capturedOptions.value?.host, "203.0.113.10")
        XCTAssertEqual(capturedOptions.value?.port, "60004")
        XCTAssertEqual(capturedOptions.value?.key, "key")
        XCTAssertEqual(capturedOptions.value?.predictionMode, "never")
    }

    func testConnectStartsAdapterAndStreamsOutput() async throws {
        let adapter = RecordingMoshBridgeSessionAdapter()
        let bridge = MoshRuntimeClientBridge(sessionFactory: { _ in adapter })

        let session = try await bridge.connect(
            host: makeMoshHost(),
            launchResult: MoshServerLaunchResult(
                port: 60004,
                key: "key",
                serverOutput: "MOSH CONNECT 60004 key"
            )
        )

        let firstOutputTask = Task {
            try await nextOutput(from: session.outputStream)
        }
        try adapter.emit("mosh-ready\r\n")

        let firstOutput = try await firstOutputTask.value
        XCTAssertEqual(firstOutput, "mosh-ready\r\n")
        XCTAssertEqual(adapter.startCount, 1)
    }

    func testSessionSendForwardsInputToAdapter() async throws {
        let adapter = RecordingMoshBridgeSessionAdapter()
        let bridge = MoshRuntimeClientBridge(sessionFactory: { _ in adapter })
        let session = try await bridge.connect(
            host: makeMoshHost(),
            launchResult: MoshServerLaunchResult(
                port: 60004,
                key: "key",
                serverOutput: "MOSH CONNECT 60004 key"
            )
        )

        try await session.send("ls\n")

        XCTAssertEqual(adapter.sentInputs, ["ls\n"])
    }

    func testSessionCloseClosesAdapter() async throws {
        let adapter = RecordingMoshBridgeSessionAdapter()
        let bridge = MoshRuntimeClientBridge(sessionFactory: { _ in adapter })
        let session = try await bridge.connect(
            host: makeMoshHost(),
            launchResult: MoshServerLaunchResult(
                port: 60004,
                key: "key",
                serverOutput: "MOSH CONNECT 60004 key"
            )
        )

        await session.close()

        XCTAssertEqual(adapter.closeCount, 1)
    }
}

private final class RecordingMoshBridgeSessionAdapter: MoshBridgeSessionControlling, @unchecked Sendable {
    private var outputHandler: (@Sendable (String) -> Void)?
    private var exitHandler: (@Sendable (String?) -> Void)?

    private(set) var startCount = 0
    private(set) var sentInputs: [String] = []
    private(set) var closeCount = 0

    func startSession(
        outputHandler: @escaping @Sendable (String) -> Void,
        exitHandler: @escaping @Sendable (String?) -> Void
    ) throws {
        startCount += 1
        self.outputHandler = outputHandler
        self.exitHandler = exitHandler
    }

    func sendBridgeInput(_ input: String) throws {
        sentInputs.append(input)
    }

    func closeBridgeSession() {
        closeCount += 1
        exitHandler?(nil)
    }

    func emit(_ output: String) throws {
        guard let outputHandler else {
            throw TestAdapterError.notStarted
        }
        outputHandler(output)
    }
}

private final class CapturedMoshBridgeOptionsBox: @unchecked Sendable {
    var value: MoshBridgeConnectionOptions?
}

private enum TestAdapterError: Error {
    case notStarted
}

private func nextOutput(from stream: AsyncStream<String>) async throws -> String {
    var iterator = stream.makeAsyncIterator()
    guard let output = await iterator.next() else {
        throw TestAdapterError.notStarted
    }
    return output
}

private func makeMoshHost(configuration: MoshHostConfiguration = .default) -> ShellHost {
    ShellHost(
        id: UUID(uuidString: "99999999-2222-3333-4444-555555555555")!,
        name: "lab-mosh",
        address: "lab.example.com",
        username: "ops",
        group: "Lab",
        tags: ["mosh"],
        status: .idle,
        protocol: .mosh,
        moshConfiguration: configuration
    )
}
