import XCTest
import Crypto
import NIOSSH
@testable import MobileShell

final class MobileShellStoreTests: XCTestCase {
    func testConnectingHostCreatesAndSelectsTerminalSession() throws {
        let store = MobileShellStore.preview()
        let host = try XCTUnwrap(store.hosts.first { $0.name == "acme-api-prod" })

        store.connect(to: host)

        XCTAssertEqual(store.selectedSection, .terminals)
        XCTAssertEqual(store.terminalSessions.count, 1)
        XCTAssertEqual(store.selectedSessionID, store.terminalSessions.first?.id)
        XCTAssertTrue(store.terminalSessions[0].lines.contains { $0.contains("Connected to acme-api-prod") })
    }

    @MainActor
    func testOpeningMoshHostDoesNotCreateTerminalSessionAndShowsUnavailableMessage() async throws {
        let host = ShellHost(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            name: "lab-mosh",
            address: "lab.example.com",
            username: "ops",
            group: "Lab",
            tags: ["mosh"],
            status: .idle,
            protocol: .mosh,
            moshConfiguration: .default
        )
        let shellClient = RecordingTerminalShellClient(result: .success(RecordingTerminalShellSession(outputs: [])))
        let store = MobileShellStore(
            hosts: [host],
            terminalShellClient: shellClient
        )

        await store.openInteractiveTerminal(for: host)

        XCTAssertTrue(store.terminalSessions.isEmpty)
        XCTAssertTrue(shellClient.requests.isEmpty)
        XCTAssertEqual(store.terminalUnavailableMessage, "Mosh configuration is saved for this host, but real Mosh sessions are not available in this version yet.")
    }

    @MainActor
    func testOpeningSSHHostStillCreatesTerminalSession() async throws {
        let host = ShellHost(
            id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
            name: "api-prod",
            address: "api.example.com",
            username: "deploy",
            group: "Production",
            tags: ["ssh"],
            status: .idle
        )
        let shellClient = RecordingTerminalShellClient(result: .success(RecordingTerminalShellSession(outputs: [])))
        let store = MobileShellStore(
            hosts: [host],
            terminalShellClient: shellClient
        )

        await store.openInteractiveTerminal(for: host)

        XCTAssertEqual(store.terminalSessions.count, 1)
        XCTAssertNil(store.terminalUnavailableMessage)
        XCTAssertEqual(shellClient.requests.count, 1)
    }

    func testConnectingToMoshHostReturnsNilCreatesNoSessionAndShowsUnavailableMessage() throws {
        let host = ShellHost(
            id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
            name: "lab-mosh",
            address: "lab.example.com",
            username: "ops",
            group: "Lab",
            tags: ["mosh"],
            status: .idle,
            protocol: .mosh,
            moshConfiguration: .default
        )
        let connectionClient = RecordingShellConnectionClient()
        let store = MobileShellStore(
            hosts: [host],
            connectionClient: connectionClient
        )

        let sessionID = store.connect(to: host)

        XCTAssertNil(sessionID)
        XCTAssertTrue(store.terminalSessions.isEmpty)
        XCTAssertTrue(connectionClient.openedHostNames.isEmpty)
        XCTAssertEqual(store.terminalUnavailableMessage, "Mosh configuration is saved for this host, but real Mosh sessions are not available in this version yet.")
    }

    func testRunningCommandAppendsPromptOutputAndClearsInput() throws {
        let store = MobileShellStore.preview()
        let host = try XCTUnwrap(store.hosts.first { $0.name == "acme-api-prod" })
        store.connect(to: host)
        store.commandInput = "uptime"

        store.runCommand(store.commandInput)

        XCTAssertEqual(store.commandInput, "")
        XCTAssertTrue(store.terminalSessions[0].lines.contains("$ uptime"))
        XCTAssertTrue(store.terminalSessions[0].lines.contains { $0.contains("load average") })
    }

    func testTerminalDraftsAreScopedToSelectedSession() throws {
        let store = MobileShellStore.preview()
        let firstHost = try XCTUnwrap(store.hosts.first { $0.name == "acme-api-prod" })
        let secondHost = try XCTUnwrap(store.hosts.first { $0.name == "db-replica-eu" })

        store.connect(to: firstHost)
        let firstSessionID = try XCTUnwrap(store.selectedSessionID)
        store.updateCommandDraft("uptime", for: firstSessionID)

        store.connect(to: secondHost)
        let secondSessionID = try XCTUnwrap(store.selectedSessionID)
        store.updateCommandDraft("whoami", for: secondSessionID)

        store.selectTerminalSession(firstSessionID)
        XCTAssertEqual(store.selectedTerminalSession?.commandDraft, "uptime")

        store.selectTerminalSession(secondSessionID)
        XCTAssertEqual(store.selectedTerminalSession?.commandDraft, "whoami")

        store.runCommand(store.selectedTerminalSession?.commandDraft ?? "")

        XCTAssertEqual(store.selectedTerminalSession?.commandDraft, "")
        XCTAssertEqual(store.terminalSessions.first { $0.id == firstSessionID }?.commandDraft, "uptime")
    }

    func testClosingSelectedTerminalSessionSelectsNeighbor() throws {
        let store = MobileShellStore.preview()
        let firstHost = try XCTUnwrap(store.hosts.first { $0.name == "acme-api-prod" })
        let secondHost = try XCTUnwrap(store.hosts.first { $0.name == "db-replica-eu" })

        store.connect(to: firstHost)
        let firstSessionID = try XCTUnwrap(store.selectedSessionID)
        store.connect(to: secondHost)
        let secondSessionID = try XCTUnwrap(store.selectedSessionID)

        store.closeTerminalSession(secondSessionID)

        XCTAssertEqual(store.terminalSessions.map(\.id), [firstSessionID])
        XCTAssertEqual(store.selectedSessionID, firstSessionID)
        XCTAssertEqual(store.selectedTerminalSession?.hostName, "acme-api-prod")
        XCTAssertEqual(store.history.first, "Closed terminal db-replica-eu")

        store.closeTerminalSession(firstSessionID)

        XCTAssertTrue(store.terminalSessions.isEmpty)
        XCTAssertNil(store.selectedSessionID)
    }

    func testCitadelTerminalShellClientCanBeCreatedForLiveShellSessions() {
        let client: any TerminalShellClient = CitadelTerminalShellClient()

        XCTAssertTrue(client is CitadelTerminalShellClient)
    }

    func testStoreUsesInjectedConnectionClientForSessionAndCommandOutput() throws {
        let host = ShellHost(
            id: UUID(uuidString: "ABABABAB-ABAB-ABAB-ABAB-ABABABABABAB")!,
            name: "custom-host",
            address: "custom.example.com",
            username: "ops",
            group: "Injected",
            tags: ["ssh"],
            status: .idle
        )
        let connectionClient = RecordingShellConnectionClient()
        let store = MobileShellStore(hosts: [host], connectionClient: connectionClient)

        store.connect(to: host)
        store.commandInput = "hostname"
        store.runCommand(store.commandInput)

        XCTAssertEqual(connectionClient.openedHostNames, ["custom-host"])
        XCTAssertEqual(connectionClient.commands, ["hostname"])
        XCTAssertTrue(store.terminalSessions[0].lines.contains("custom client connected"))
        XCTAssertTrue(store.terminalSessions[0].lines.contains("custom output"))
    }

    func testSSHConnectionRequestUsesHostPortAndVaultPassword() throws {
        let hostID = UUID(uuidString: "12121212-3434-5656-7878-909090909090")!
        let knownHost = KnownHost(
            host: "[edge.example.com]:2201",
            keyType: "ssh-ed25519",
            fingerprint: "SHA256:edge"
        )
        let host = ShellHost(
            id: hostID,
            name: "edge-prod",
            address: "edge.example.com",
            port: 2201,
            username: "deploy",
            group: "Production",
            tags: ["ssh", "edge"],
            status: .locked
        )
        let credentialVault = InMemoryCredentialVault()
        try credentialVault.savePassword("vault-password", forHostID: hostID)

        let request = try SSHConnectionRequestBuilder(
            credentialVault: credentialVault,
            knownHosts: [
                knownHost,
                KnownHost(host: "other.example.com", keyType: "ssh-ed25519", fingerprint: "SHA256:other")
            ]
        ).request(for: host)

        XCTAssertEqual(request.hostID, hostID)
        XCTAssertEqual(request.displayName, "edge-prod")
        XCTAssertEqual(request.hostname, "edge.example.com")
        XCTAssertEqual(request.port, 2201)
        XCTAssertEqual(request.username, "deploy")
        XCTAssertEqual(request.password, "vault-password")
        XCTAssertNil(request.privateKey)
        XCTAssertEqual(request.knownHosts, [knownHost])
    }

    func testSSHConnectionRequestUsesLinkedPrivateKeyFromVault() throws {
        let hostID = UUID(uuidString: "13131313-3434-5656-7878-909090909090")!
        let keyID = UUID(uuidString: "23232323-3434-5656-7878-909090909090")!
        let host = ShellHost(
            id: hostID,
            name: "keyed-prod",
            address: "keyed.example.com",
            port: 2201,
            username: "deploy",
            group: "Production",
            tags: ["ssh", "key"],
            status: .locked,
            sshKeyID: keyID
        )
        let credentialVault = InMemoryCredentialVault()
        try credentialVault.savePrivateKey("vault-private-key", forKeyID: keyID)

        let request = try SSHConnectionRequestBuilder(credentialVault: credentialVault).request(for: host)

        XCTAssertEqual(request.privateKey, "vault-private-key")
        XCTAssertNil(request.password)
    }

    func testCitadelCommandExecutorRequiresPasswordBeforeOpeningConnection() async {
        let request = SSHConnectionRequest(
            hostID: UUID(uuidString: "56565656-7878-9090-ABAB-CDCDCDCDCDCD")!,
            displayName: "passwordless",
            hostname: "example.com",
            port: 22,
            username: "deploy",
            password: nil
        )

        do {
            _ = try await CitadelCommandExecutor().run("whoami", using: request)
            XCTFail("Expected missing password to fail before connecting")
        } catch LiveShellConnectionError.missingPassword {
        } catch {
            XCTFail("Expected missing password, got \(error)")
        }
    }

    func testCitadelCommandExecutorAttemptsPrivateKeyBeforePasswordRequirement() async {
        let request = SSHConnectionRequest(
            hostID: UUID(uuidString: "67676767-7878-9090-ABAB-CDCDCDCDCDCD")!,
            displayName: "keyed",
            hostname: "example.com",
            port: 22,
            username: "deploy",
            password: nil,
            privateKey: "not-a-valid-openssh-private-key"
        )

        do {
            _ = try await CitadelCommandExecutor().run("whoami", using: request)
            XCTFail("Expected invalid private key to fail before connecting")
        } catch LiveShellConnectionError.missingPassword {
            XCTFail("Expected private key parsing before password fallback")
        } catch {
        }
    }

}
