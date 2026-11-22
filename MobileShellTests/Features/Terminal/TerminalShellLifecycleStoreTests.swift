import XCTest
@testable import MobileShell

final class TerminalShellLifecycleStoreTests: XCTestCase {
    @MainActor
    func testOpeningInteractiveTerminalStartsShellSessionAndAppendsOutput() async throws {
        let hostID = UUID(uuidString: "A1A1A1A1-2222-3333-4444-A1A1A1A1A1A1")!
        let host = ShellHost(
            id: hostID,
            name: "shell-prod",
            address: "shell.example.com",
            port: 2202,
            username: "deploy",
            group: "Production",
            tags: ["ssh"],
            status: .idle
        )
        let credentialVault = InMemoryCredentialVault()
        try credentialVault.savePassword("shell-secret", forHostID: hostID)
        let shellSession = RecordingTerminalShellSession(outputs: ["welcome", "deploy@shell-prod:~$"])
        let shellClient = RecordingTerminalShellClient(result: .success(shellSession))
        let store = MobileShellStore(
            hosts: [host],
            credentialVault: credentialVault,
            terminalShellClient: shellClient
        )

        await store.openInteractiveTerminal(for: host)
        try await Task.sleep(nanoseconds: 1_000_000)

        XCTAssertEqual(shellClient.requests.first?.hostname, "shell.example.com")
        XCTAssertEqual(shellClient.requests.first?.port, 2202)
        XCTAssertEqual(shellClient.requests.first?.password, "shell-secret")
        XCTAssertEqual(store.selectedTerminalSession?.state, .connected)
        XCTAssertTrue(store.selectedTerminalSession?.lines.contains("welcome") == true)
        XCTAssertTrue(store.selectedTerminalSession?.lines.contains("deploy@shell-prod:~$") == true)
    }

    @MainActor
    func testRemoteCommandSendsInputToActiveShellSession() async throws {
        let host = ShellHost(
            id: UUID(uuidString: "A2A2A2A2-2222-3333-4444-A2A2A2A2A2A2")!,
            name: "interactive",
            address: "interactive.example.com",
            username: "deploy",
            group: "Production",
            tags: ["ssh"],
            status: .idle
        )
        let shellSession = RecordingTerminalShellSession(outputs: [])
        let store = MobileShellStore(
            hosts: [host],
            terminalShellClient: RecordingTerminalShellClient(result: .success(shellSession))
        )

        await store.openInteractiveTerminal(for: host)
        let sessionID = try XCTUnwrap(store.selectedSessionID)
        store.updateCommandDraft("uptime", for: sessionID)
        await store.runRemoteCommand(store.selectedTerminalSession?.commandDraft ?? "")

        XCTAssertEqual(shellSession.sentInputs, ["uptime\n"])
        XCTAssertEqual(store.selectedTerminalSession?.commandDraft, "")
        XCTAssertTrue(store.selectedTerminalSession?.lines.contains("$ uptime") == true)
    }

    @MainActor
    func testClosingTerminalSessionClosesActiveShellSession() async throws {
        let host = ShellHost(
            id: UUID(uuidString: "A3A3A3A3-2222-3333-4444-A3A3A3A3A3A3")!,
            name: "closable",
            address: "closable.example.com",
            username: "deploy",
            group: "Production",
            tags: ["ssh"],
            status: .idle
        )
        let shellSession = RecordingTerminalShellSession(outputs: [])
        let store = MobileShellStore(
            hosts: [host],
            terminalShellClient: RecordingTerminalShellClient(result: .success(shellSession))
        )

        await store.openInteractiveTerminal(for: host)
        let sessionID = try XCTUnwrap(store.selectedSessionID)
        store.closeTerminalSession(sessionID)
        await Task.yield()

        XCTAssertEqual(shellSession.closeCount, 1)
        XCTAssertNil(store.selectedSessionID)
    }

    @MainActor
    func testTrustingInteractiveShellHostKeyChallengeStoresFingerprintAndRetriesShellStart() async throws {
        let hostID = UUID(uuidString: "A4A4A4A4-2222-3333-4444-A4A4A4A4A4A4")!
        let host = ShellHost(
            id: hostID,
            name: "interactive-new",
            address: "new-shell.example.com",
            port: 2202,
            username: "deploy",
            group: "Production",
            tags: ["ssh"],
            status: .idle
        )
        let challenge = HostKeyChallenge(
            id: UUID(uuidString: "EFEFEFEF-1111-2222-3333-EFEFEFEFEFEF")!,
            hostname: "new-shell.example.com",
            port: 2202,
            keyType: "ssh-ed25519",
            fingerprint: "SHA256:newshell"
        )
        let credentialVault = InMemoryCredentialVault()
        try credentialVault.savePassword("shell-secret", forHostID: hostID)
        let shellSession = RecordingTerminalShellSession(outputs: ["trusted shell"])
        let shellClient = RecordingTerminalShellClient(results: [
            .failure(challenge),
            .success(shellSession)
        ])
        let store = MobileShellStore(
            hosts: [host],
            credentialVault: credentialVault,
            terminalShellClient: shellClient
        )

        await store.openInteractiveTerminal(for: host)

        XCTAssertEqual(shellClient.requests.count, 1)
        XCTAssertEqual(store.pendingHostKeyChallenge, challenge)
        XCTAssertTrue(store.knownHosts.isEmpty)
        XCTAssertFalse(store.terminalSessions[0].lines.contains { $0.hasPrefix("Disconnected:") })

        await store.trustPendingHostKey()
        try await Task.sleep(nanoseconds: 1_000_000)

        XCTAssertNil(store.pendingHostKeyChallenge)
        XCTAssertEqual(shellClient.requests.count, 2)
        XCTAssertEqual(shellClient.requests.last?.knownHosts.first?.host, "[new-shell.example.com]:2202")
        XCTAssertEqual(store.knownHosts.first?.knownHostLine, "[new-shell.example.com]:2202 ssh-ed25519 SHA256:newshell")
        XCTAssertEqual(store.selectedTerminalSession?.state, .connected)
        XCTAssertTrue(store.terminalSessions[0].lines.contains("trusted shell"))
    }

    @MainActor
    func testTerminalShortcutSendsRawControlInputToActiveShellSession() async throws {
        let host = ShellHost(
            id: UUID(uuidString: "A5A5A5A5-2222-3333-4444-A5A5A5A5A5A5")!,
            name: "control",
            address: "control.example.com",
            username: "deploy",
            group: "Production",
            tags: ["ssh"],
            status: .idle
        )
        let shellSession = RecordingTerminalShellSession(outputs: [])
        let store = MobileShellStore(
            hosts: [host],
            terminalShellClient: RecordingTerminalShellClient(result: .success(shellSession))
        )

        await store.openInteractiveTerminal(for: host)
        let historyBeforeShortcuts = store.history
        await store.sendTerminalKeyboardShortcut(.controlC)
        await store.sendTerminalKeyboardShortcut(.tab)

        XCTAssertEqual(shellSession.sentInputs, ["\u{03}", "\t"])
        XCTAssertEqual(store.history, historyBeforeShortcuts)
    }

    @MainActor
    func testPrintableTerminalShortcutAppendsToDraftWhenNoLiveShellIsActive() async throws {
        let host = ShellHost(
            id: UUID(uuidString: "A6A6A6A6-2222-3333-4444-A6A6A6A6A6A6")!,
            name: "draft",
            address: "draft.example.com",
            username: "deploy",
            group: "Production",
            tags: ["ssh"],
            status: .idle
        )
        let store = MobileShellStore(hosts: [host])

        store.connect(to: host)
        let sessionID = try XCTUnwrap(store.selectedSessionID)
        store.updateCommandDraft("cat ", for: sessionID)
        await store.sendTerminalKeyboardShortcut(.slash)
        await store.sendTerminalKeyboardShortcut(.tilde)
        await store.sendTerminalKeyboardShortcut(.controlD)

        XCTAssertEqual(store.selectedTerminalSession?.commandDraft, "cat /~")
        XCTAssertEqual(store.commandInput, "cat /~")
    }

    @MainActor
    func testRemoteCommandUsesExecutorRequestAndAppendsOutput() async throws {
        let hostID = UUID(uuidString: "FEEDFEED-1111-2222-3333-FEEDFEEDFEED")!
        let knownHost = KnownHost(
            host: "[remote.example.com]:2222",
            keyType: "ssh-ed25519",
            fingerprint: "SHA256:remote"
        )
        let host = ShellHost(
            id: hostID,
            name: "remote-prod",
            address: "remote.example.com",
            port: 2222,
            username: "deploy",
            group: "Production",
            tags: ["ssh"],
            status: .idle
        )
        let credentialVault = InMemoryCredentialVault()
        try credentialVault.savePassword("remote-secret", forHostID: hostID)
        let executor = RecordingSSHCommandExecutor()
        let store = MobileShellStore(
            hosts: [host],
            knownHosts: [knownHost],
            credentialVault: credentialVault,
            commandExecutor: executor
        )

        store.connect(to: host)
        await store.runRemoteCommand("hostname")

        XCTAssertEqual(executor.commands, ["hostname"])
        XCTAssertEqual(executor.requests.first?.hostname, "remote.example.com")
        XCTAssertEqual(executor.requests.first?.port, 2222)
        XCTAssertEqual(executor.requests.first?.password, "remote-secret")
        XCTAssertEqual(executor.requests.first?.knownHosts, [knownHost])
        XCTAssertTrue(store.terminalSessions[0].lines.contains("$ hostname"))
        XCTAssertTrue(store.terminalSessions[0].lines.contains("remote-prod"))
        XCTAssertTrue(store.terminalSessions[0].lines.contains("ok"))
    }

    @MainActor
    func testTrustingRemoteCommandHostKeyChallengeStoresFingerprintAndRetriesCommand() async throws {
        let hostID = UUID(uuidString: "FEEDFEED-4444-5555-6666-FEEDFEEDFEED")!
        let host = ShellHost(
            id: hostID,
            name: "remote-new",
            address: "new-remote.example.com",
            port: 2222,
            username: "deploy",
            group: "Production",
            tags: ["ssh"],
            status: .idle
        )
        let challenge = HostKeyChallenge(
            id: UUID(uuidString: "ABABABAB-1111-2222-3333-ABABABABABAB")!,
            hostname: "new-remote.example.com",
            port: 2222,
            keyType: "ssh-ed25519",
            fingerprint: "SHA256:newremote"
        )
        let credentialVault = InMemoryCredentialVault()
        try credentialVault.savePassword("remote-secret", forHostID: hostID)
        let executor = RecordingSSHCommandExecutor(results: [
            .failure(challenge),
            .success("trusted\nok")
        ])
        let store = MobileShellStore(
            hosts: [host],
            credentialVault: credentialVault,
            commandExecutor: executor
        )

        store.connect(to: host)
        await store.runRemoteCommand("hostname")

        XCTAssertEqual(executor.commands, ["hostname"])
        XCTAssertEqual(store.pendingHostKeyChallenge, challenge)
        XCTAssertTrue(store.knownHosts.isEmpty)
        XCTAssertFalse(store.terminalSessions[0].lines.contains { $0.hasPrefix("SSH error:") })

        await store.trustPendingHostKey()
        XCTAssertNil(store.pendingHostKeyChallenge)
        XCTAssertEqual(executor.requests.count, 2)
        XCTAssertEqual(executor.requests.last?.knownHosts.first?.host, "[new-remote.example.com]:2222")
        XCTAssertEqual(store.knownHosts.first?.knownHostLine, "[new-remote.example.com]:2222 ssh-ed25519 SHA256:newremote")
        XCTAssertTrue(store.terminalSessions[0].lines.contains("trusted"))
        XCTAssertTrue(store.terminalSessions[0].lines.contains("ok"))
    }
}
