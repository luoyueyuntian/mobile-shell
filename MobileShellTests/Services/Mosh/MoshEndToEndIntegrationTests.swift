import Foundation
import XCTest
@testable import MobileShell

final class MoshEndToEndIntegrationTests: XCTestCase {
    func testMoshPreparationCanLaunchRealServer() async throws {
        let config = try MoshEndToEndConfiguration.load(udpPortOverride: 60011)
        ProgressLog.write("prepare-only:loaded-config")

        let preparationClient = CitadelMoshPreparationClient()
        let launchResult = try await preparationClient.prepare(
            using: config.request,
            configuration: config.configuration
        )
        ProgressLog.write("prepare-only:prepared-launch-result")

        XCTAssertGreaterThan(launchResult.port, 0)
        XCTAssertFalse(launchResult.key.isEmpty)
        XCTAssertTrue(launchResult.serverOutput.contains("MOSH CONNECT"))

        await cleanupPreparedServer(using: config)
    }

    func testMoshSessionCanRunVerificationCommandAgainstRealHost() async throws {
        let config = try MoshEndToEndConfiguration.load(udpPortOverride: 60012)
        ProgressLog.write("loaded-config")

        let preparationClient = CitadelMoshPreparationClient()
        let launchResult = try await preparationClient.prepare(
            using: config.request,
            configuration: config.configuration
        )
        ProgressLog.write("prepared-launch-result")

        let runtimeClient = MoshRuntimeClientBridge()
        let session = try await runtimeClient.connect(host: config.host, launchResult: launchResult)
        ProgressLog.write("connected-runtime")
        let collector = StreamCollector(stream: session.outputStream)

        do {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            ProgressLog.write("sending-command")
            try await session.send(config.verificationCommand)
            let output = try await collector.waitForMarker(
                config.endMarker,
                timeoutNanoseconds: 20_000_000_000
            )
            ProgressLog.write("received-end-marker")

            XCTAssertTrue(output.contains(config.beginMarker))
            XCTAssertTrue(output.contains(config.expectedSubstring))
            XCTAssertTrue(output.contains(config.endMarker))
        } catch {
            ProgressLog.write("caught-error:\(error.localizedDescription)")
            await session.close()
            throw error
        }

        await session.close()
        ProgressLog.write("closed-session")
    }
}

private func cleanupPreparedServer(using configuration: MoshEndToEndConfiguration) async {
    let command = "pkill -f 'mosh-server.*-p \(configuration.configuration.udpPort)' || true"
    do {
        _ = try await CitadelCommandExecutor().run(command, using: configuration.request)
        ProgressLog.write("prepare-only:cleaned-up-server")
    } catch {
        ProgressLog.write("prepare-only:cleanup-error:\(error.localizedDescription)")
    }
}

private struct MoshEndToEndConfiguration {
    let host: ShellHost
    let request: SSHConnectionRequest
    let configuration: MoshHostConfiguration
    let verificationCommand: String
    let expectedSubstring: String
    let beginMarker: String
    let endMarker: String
    let knownHosts: [KnownHost]

    static func load(udpPortOverride: Int? = nil) throws -> MoshEndToEndConfiguration {
        let env = ProcessInfo.processInfo.environment
        let fileConfiguration = try FileBackedMoshEndToEndConfiguration.loadIfPresent(
            at: env["MOBILESHELL_MOSH_E2E_CONFIG_PATH"] ?? "/private/tmp/mobile-shell-mosh-e2e-config.json"
        )

        func required(_ key: String) throws -> String {
            guard let value = env[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else {
                if let fileConfiguration {
                    switch key {
                    case "MOBILESHELL_MOSH_E2E_HOST":
                        return fileConfiguration.host
                    case "MOBILESHELL_MOSH_E2E_USERNAME":
                        return fileConfiguration.username
                    case "MOBILESHELL_MOSH_E2E_PASSWORD":
                        return fileConfiguration.password
                    case "MOBILESHELL_MOSH_E2E_VERIFY":
                        return fileConfiguration.verify ?? "uname -a"
                    case "MOBILESHELL_MOSH_E2E_EXPECTED":
                        return fileConfiguration.expected ?? "Linux"
                    default:
                        break
                    }
                }
                throw MoshEndToEndConfigurationError.missingConfigurationValue(key)
            }
            return value
        }

        let hostname = try required("MOBILESHELL_MOSH_E2E_HOST")
        let username = try required("MOBILESHELL_MOSH_E2E_USERNAME")
        let password = try required("MOBILESHELL_MOSH_E2E_PASSWORD")
        let port = Int(env["MOBILESHELL_MOSH_E2E_PORT"] ?? "") ?? fileConfiguration?.port ?? 22
        let mode = env["MOBILESHELL_MOSH_E2E_MODE"]?.lowercased() ?? fileConfiguration?.mode?.lowercased() ?? "normal"
        let verificationBase = try required("MOBILESHELL_MOSH_E2E_VERIFY")
        let expectedSubstring = try required("MOBILESHELL_MOSH_E2E_EXPECTED")
        let beginMarker = "__CODEX_BEGIN__"
        let endMarker = "__CODEX_END__"
        let verificationCommand = "printf '\(beginMarker)\\n'; \(verificationBase); printf '\(endMarker)\\n'; exit\n"
        let knownHosts: [KnownHost]
        if let fileConfiguration,
           let knownHostKeyType = fileConfiguration.knownHostKeyType,
           let knownHostFingerprint = fileConfiguration.knownHostFingerprint {
            knownHosts = [
                KnownHost(
                    host: KnownHost.hostToken(hostname: hostname, port: port),
                    keyType: knownHostKeyType,
                    fingerprint: knownHostFingerprint
                )
            ]
        } else {
            knownHosts = []
        }

        let configuration = MoshHostConfiguration(
            udpPort: udpPortOverride ?? fileConfiguration?.udpPort ?? 60001,
            serverCommand: fileConfiguration?.serverCommand ?? MoshHostConfiguration.default.serverCommand,
            predictiveEcho: true,
            useExperimentalConnection: mode == "experimental"
        )

        let host = ShellHost(
            id: UUID(uuidString: "A0A0A0A0-B1B1-C2C2-D3D3-E4E4E4E4E4E4")!,
            name: "mosh-e2e",
            address: hostname,
            port: port,
            username: username,
            group: "Integration",
            tags: ["mosh", "e2e"],
            status: .idle,
            protocol: .mosh,
            moshConfiguration: configuration
        )

        let request = SSHConnectionRequest(
            hostID: host.id,
            displayName: host.name,
            hostname: hostname,
            port: port,
            username: username,
            password: password,
            knownHosts: knownHosts
        )

        return MoshEndToEndConfiguration(
            host: host,
            request: request,
            configuration: configuration,
            verificationCommand: verificationCommand,
            expectedSubstring: expectedSubstring,
            beginMarker: beginMarker,
            endMarker: endMarker,
            knownHosts: knownHosts
        )
    }
}

private enum MoshEndToEndConfigurationError: Error, LocalizedError {
    case missingConfigurationValue(String)
    case invalidConfigurationFile(String)

    var errorDescription: String? {
        switch self {
        case let .missingConfigurationValue(key):
            "Missing required Mosh end-to-end configuration value: \(key)"
        case let .invalidConfigurationFile(message):
            "Invalid Mosh end-to-end configuration file: \(message)"
        }
    }
}

private struct FileBackedMoshEndToEndConfiguration: Decodable {
    let host: String
    let port: Int?
    let username: String
    let password: String
    let mode: String?
    let udpPort: Int?
    let verify: String?
    let expected: String?
    let serverCommand: String?
    let knownHostKeyType: String?
    let knownHostFingerprint: String?

    static func loadIfPresent(at path: String) throws -> FileBackedMoshEndToEndConfiguration? {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(FileBackedMoshEndToEndConfiguration.self, from: data)
        } catch {
            throw MoshEndToEndConfigurationError.invalidConfigurationFile(error.localizedDescription)
        }
    }
}

private final class StreamCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var output = ""
    private var task: Task<Void, Never>?

    init(stream: AsyncStream<String>) {
        task = Task { [weak self] in
            for await chunk in stream {
                self?.append(chunk)
            }
        }
    }

    deinit {
        task?.cancel()
    }

    private func append(_ chunk: String) {
        lock.withLock {
            output.append(chunk)
        }
    }

    func waitForMarker(
        _ marker: String,
        timeoutNanoseconds: UInt64
    ) async throws -> String {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds

        while DispatchTime.now().uptimeNanoseconds < deadline {
            let currentOutput = lock.withLock { output }

            if currentOutput.contains(marker) {
                return currentOutput
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }

        let finalOutput = lock.withLock { output }
        throw StreamCollectorError.timeout(marker: marker, output: finalOutput)
    }
}

private enum StreamCollectorError: Error, LocalizedError {
    case timeout(marker: String, output: String)

    var errorDescription: String? {
        switch self {
        case let .timeout(marker, output):
            "Timed out waiting for marker \(marker). Output so far: \(output)"
        }
    }
}

private enum ProgressLog {
    private static let url: URL = {
        let baseURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return baseURL.appendingPathComponent("mobile-shell-mosh-e2e-progress.log")
    }()

    static func write(_ line: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let entry = "__CODEX_STAGE__ [\(timestamp)] \(line)\n"

        fputs(entry, stderr)
        fflush(stderr)

        if let data = entry.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: url.path),
               let handle = try? FileHandle(forWritingTo: url) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }
}
