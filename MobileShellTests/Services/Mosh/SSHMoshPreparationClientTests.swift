import XCTest
@testable import MobileShell

final class SSHMoshPreparationClientTests: XCTestCase {
    func testPreparationRunsConfiguredServerCommandThroughExecutorAndParsesResult() async throws {
        let executor = RecordingMoshCommandExecutor(result: .success("""
        MOSH SSH_CONNECTION 203.0.113.10 54321 10.0.0.4 22
        MOSH CONNECT 60004 4NeCCgvZFe2RnPgrcU1PQw
        [mosh-server detached, pid = 30261]
        """))
        let client = SSHMoshPreparationClient(commandExecutor: executor)
        let request = SSHConnectionRequest(
            hostID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            displayName: "lab-mosh",
            hostname: "lab.example.com",
            port: 22,
            username: "ops",
            password: "secret"
        )
        let configuration = MoshHostConfiguration(
            udpPort: 60010,
            serverCommand: "mosh-server new -s",
            predictiveEcho: false,
            useExperimentalConnection: true
        )

        let result = try await client.prepare(using: request, configuration: configuration)

        XCTAssertEqual(result.port, 60004)
        XCTAssertEqual(result.key, "4NeCCgvZFe2RnPgrcU1PQw")
        XCTAssertEqual(result.remoteIPAddress, "203.0.113.10")
        XCTAssertEqual(executor.commands, ["echo \"MOSH SSH_CONNECTION $SSH_CONNECTION\" && mosh-server new -s -p 60010"])
    }

    func testPreparationMapsMissingServerFailure() async {
        let executor = RecordingMoshCommandExecutor(result: .success("bash: mosh-server: command not found"))
        let client = SSHMoshPreparationClient(commandExecutor: executor)
        let request = SSHConnectionRequest(
            hostID: UUID(),
            displayName: "lab-mosh",
            hostname: "lab.example.com",
            port: 22,
            username: "ops",
            password: "secret"
        )

        do {
            _ = try await client.prepare(using: request, configuration: .default)
            XCTFail("Expected moshServerMissing")
        } catch {
            XCTAssertEqual(error as? MoshPreparationError, .moshServerMissing)
        }
    }

    func testPreparationWithoutExperimentalConnectionUsesPlainServerCommand() async throws {
        let executor = RecordingMoshCommandExecutor(result: .success("""
        MOSH CONNECT 60004 4NeCCgvZFe2RnPgrcU1PQw
        [mosh-server detached, pid = 30261]
        """))
        let client = SSHMoshPreparationClient(commandExecutor: executor)
        let request = SSHConnectionRequest(
            hostID: UUID(),
            displayName: "lab-mosh",
            hostname: "lab.example.com",
            port: 22,
            username: "ops",
            password: "secret"
        )
        let configuration = MoshHostConfiguration(
            udpPort: 60010,
            serverCommand: "mosh-server new -s",
            predictiveEcho: true,
            useExperimentalConnection: false
        )

        _ = try await client.prepare(using: request, configuration: configuration)

        XCTAssertEqual(executor.commands, ["mosh-server new -s -p 60010"])
    }
}

private final class RecordingMoshCommandExecutor: SSHCommandExecuting, @unchecked Sendable {
    var commands: [String] = []
    let result: Result<String, Error>

    init(result: Result<String, Error>) {
        self.result = result
    }

    func run(_ command: String, using request: SSHConnectionRequest) async throws -> String {
        commands.append(command)
        return try result.get()
    }
}
