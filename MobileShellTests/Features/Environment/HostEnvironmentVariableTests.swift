import XCTest
@testable import MobileShell

final class HostEnvironmentVariableTests: XCTestCase {
    func testEnvironmentVariablesFallBackToGroupProfile() {
        let host = makeHost(name: "api", group: "Production")
        let store = MobileShellStore(
            hosts: [host],
            hostGroupProfiles: [
                HostGroupProfile(
                    name: "Production",
                    identityID: nil,
                    environmentVariables: [
                        ShellEnvironmentVariable(key: "APP_ENV", value: "production")
                    ]
                )
            ]
        )

        XCTAssertEqual(store.environmentVariables(for: host), [
            ShellEnvironmentVariable(key: "APP_ENV", value: "production")
        ])
    }

    func testHostEnvironmentVariablesOverrideGroupVariables() {
        let host = makeHost(
            name: "api",
            group: "Production",
            environmentVariables: [
                ShellEnvironmentVariable(key: "APP_ENV", value: "staging"),
                ShellEnvironmentVariable(key: "REGION", value: "us-east-1")
            ]
        )
        let store = MobileShellStore(
            hosts: [host],
            hostGroupProfiles: [
                HostGroupProfile(
                    name: "Production",
                    identityID: nil,
                    environmentVariables: [
                        ShellEnvironmentVariable(key: "APP_ENV", value: "production"),
                        ShellEnvironmentVariable(key: "TEAM", value: "platform")
                    ]
                )
            ]
        )

        XCTAssertEqual(store.environmentVariables(for: host), [
            ShellEnvironmentVariable(key: "APP_ENV", value: "staging"),
            ShellEnvironmentVariable(key: "REGION", value: "us-east-1"),
            ShellEnvironmentVariable(key: "TEAM", value: "platform")
        ])
    }

    func testEnvironmentVariableTextParserIgnoresInvalidLines() {
        XCTAssertEqual(
            ShellEnvironmentVariable.parseLines("""
              APP_ENV = production
              1INVALID=value
              EMPTY=
              REGION= us-east-1
              _TOKEN= abc=123
              NO_EQUALS
              ÅINVALID=value
            """),
            [
                ShellEnvironmentVariable(key: "APP_ENV", value: "production"),
                ShellEnvironmentVariable(key: "REGION", value: "us-east-1"),
                ShellEnvironmentVariable(key: "_TOKEN", value: "abc=123")
            ]
        )
    }

    func testHostAndGroupEnvironmentVariablesPersist() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = JSONHostRepository(fileURL: directory.appendingPathComponent("vault.json"))
        let host = makeHost(
            name: "api",
            group: "Production",
            environmentVariables: [ShellEnvironmentVariable(key: "REGION", value: "us-east-1")]
        )
        let profile = HostGroupProfile(
            name: "Production",
            identityID: nil,
            environmentVariables: [ShellEnvironmentVariable(key: "APP_ENV", value: "production")]
        )

        try repository.save(HostPersistenceSnapshot(hosts: [host], hostGroupProfiles: [profile]))
        let loaded = try repository.load()

        XCTAssertEqual(loaded.hosts.first?.environmentVariables, host.environmentVariables)
        XCTAssertEqual(loaded.hostGroupProfiles.first?.environmentVariables, profile.environmentVariables)
    }

    func testAddingAndUpdatingHostStoresSanitizedEnvironmentVariables() throws {
        let store = MobileShellStore()

        let host = try store.addHost(
            name: "api",
            address: "api.example.com",
            port: 22,
            username: "deploy",
            group: "Production",
            tags: "ssh",
            password: "",
            environmentVariables: ShellEnvironmentVariable.parseLines("""
            APP_ENV=production
            INVALID KEY=value
            REGION=us-east-1
            """)
        )

        XCTAssertEqual(host.environmentVariables, [
            ShellEnvironmentVariable(key: "APP_ENV", value: "production"),
            ShellEnvironmentVariable(key: "REGION", value: "us-east-1")
        ])

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
                environmentVariables: [ShellEnvironmentVariable(key: "APP_ENV", value: "staging")]
            )
        )

        XCTAssertEqual(updated.environmentVariables, [
            ShellEnvironmentVariable(key: "APP_ENV", value: "staging")
        ])
    }

    func testConnectingNewPreviewSessionExportsEnvironmentBeforeStartupSnippet() throws {
        let snippet = ShellSnippet(id: UUID(), title: "Print env", command: "echo $APP_ENV")
        let host = makeHost(
            name: "api",
            group: "Production",
            startupSnippetID: snippet.id,
            environmentVariables: [ShellEnvironmentVariable(key: "APP_ENV", value: "prod's")]
        )
        let store = MobileShellStore(
            hosts: [host],
            snippets: [snippet],
            connectionClient: RecordingEnvironmentConnectionClient()
        )

        store.connect(to: host)

        let session = try XCTUnwrap(store.selectedTerminalSession)
        let exportPromptIndex = try XCTUnwrap(session.lines.firstIndex(of: "$ export APP_ENV='prod'\\''s'"))
        let snippetPromptIndex = try XCTUnwrap(session.lines.firstIndex(of: "$ echo $APP_ENV"))
        XCTAssertLessThan(exportPromptIndex, snippetPromptIndex)
        XCTAssertTrue(session.lines.contains("preview: export APP_ENV='prod'\\''s'"))
        XCTAssertTrue(session.lines.contains("preview: echo $APP_ENV"))
    }

    @MainActor
    func testInteractiveShellExportsEnvironmentBeforeStartupSnippet() async throws {
        let snippet = ShellSnippet(id: UUID(), title: "Print env", command: "echo $APP_ENV")
        let host = makeHost(
            name: "api",
            group: "Production",
            startupSnippetID: snippet.id,
            environmentVariables: [ShellEnvironmentVariable(key: "APP_ENV", value: "production")]
        )
        let shellSession = RecordingEnvironmentShellSession()
        let store = MobileShellStore(
            hosts: [host],
            snippets: [snippet],
            terminalShellClient: RecordingEnvironmentShellClient(session: shellSession)
        )

        await store.openInteractiveTerminal(for: host)

        XCTAssertEqual(shellSession.sentInputs, [
            "export APP_ENV='production'\n",
            "echo $APP_ENV\n"
        ])
    }

    private func makeHost(
        name: String,
        group: String = "Production",
        startupSnippetID: ShellSnippet.ID? = nil,
        environmentVariables: [ShellEnvironmentVariable] = []
    ) -> ShellHost {
        ShellHost(
            id: UUID(),
            name: name,
            address: "\(name).example.com",
            username: "deploy",
            group: group,
            tags: ["ssh"],
            status: .idle,
            startupSnippetID: startupSnippetID,
            environmentVariables: environmentVariables
        )
    }
}

private final class RecordingEnvironmentConnectionClient: ShellConnectionClient {
    func openSession(for host: ShellHost) -> TerminalSession {
        TerminalSession(
            id: UUID(),
            hostID: host.id,
            hostName: host.name,
            prompt: "\(host.username)@\(host.name):~$",
            lines: ["connected \(host.name)"]
        )
    }

    func output(for command: String, in session: TerminalSession) -> [String] {
        ["preview: \(command)"]
    }
}

private final class RecordingEnvironmentShellClient: TerminalShellClient, @unchecked Sendable {
    let session: RecordingEnvironmentShellSession

    init(session: RecordingEnvironmentShellSession) {
        self.session = session
    }

    func openShell(using request: SSHConnectionRequest) async throws -> any TerminalShellSession {
        session
    }
}

private final class RecordingEnvironmentShellSession: TerminalShellSession, @unchecked Sendable {
    let outputStream: AsyncStream<String>
    var sentInputs: [String] = []

    init() {
        outputStream = AsyncStream { continuation in
            continuation.finish()
        }
    }

    func send(_ input: String) async throws {
        sentInputs.append(input)
    }

    func close() async {}
}
