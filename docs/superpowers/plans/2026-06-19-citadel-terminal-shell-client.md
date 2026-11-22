# Citadel Terminal Shell Client Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Connect MobileShell's interactive terminal abstraction to a real Citadel SSH TTY session while preserving host-key trust prompts.

**Architecture:** `MobileShellStore` already owns a `TerminalShellClient` abstraction. Add a Citadel-backed implementation in `MobileShell/ShellConnection.swift`, inject it for live/persistent stores, and extend pending host-key retry actions so interactive shell startup can be retried after trust.

**Tech Stack:** Swift, SwiftUI observable store, XCTest, Citadel, NIO, NIOSSH.

---

### Task 1: Protect Interactive Shell Host-Key Retry

**Files:**
- Modify: `MobileShellTests/MobileShellStoreTests.swift`
- Modify: `MobileShell/Models.swift`

- [ ] **Step 1: Write the failing test**

Add this test near the existing interactive terminal tests:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/MobileShellStoreTests/testTrustingInteractiveShellHostKeyChallengeStoresFingerprintAndRetriesShellStart
```

Expected: FAIL because `RecordingTerminalShellClient(results:)` and shell pending host-key retry do not exist yet.

- [ ] **Step 3: Implement minimal retry support**

Change `PendingHostKeyAction`:

```swift
case terminalShell(sessionID: TerminalSession.ID)
```

In `startTerminalShell` catch host-key challenges before marking disconnected:

```swift
if recordHostKeyChallenge(error, action: .terminalShell(sessionID: sessionID)) {
    return
}
markTerminalSessionDisconnected(sessionID, reason: error.localizedDescription)
```

In `retryPendingHostKeyAction`:

```swift
case let .terminalShell(sessionID):
    await startTerminalShell(for: sessionID)
```

Update `RecordingTerminalShellClient` to accept a result queue.

- [ ] **Step 4: Run test to verify it passes**

Run the same targeted `xcodebuild test` command. Expected: PASS.

### Task 2: Add Citadel TTY Shell Client

**Files:**
- Modify: `MobileShellTests/MobileShellStoreTests.swift`
- Modify: `MobileShell/ShellConnection.swift`
- Modify: `MobileShell/Models.swift`

- [ ] **Step 1: Write the failing construction test**

Add this test near the interactive terminal tests:

```swift
func testCitadelTerminalShellClientCanBeCreatedForLiveShellSessions() {
    let client: any TerminalShellClient = CitadelTerminalShellClient()

    XCTAssertTrue(client is CitadelTerminalShellClient)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/MobileShellStoreTests/testCitadelTerminalShellClientCanBeCreatedForLiveShellSessions
```

Expected: FAIL because `CitadelTerminalShellClient` is undefined.

- [ ] **Step 3: Implement Citadel-backed shell session**

Add a `CitadelTerminalShellClient` that opens `makeSSHClient(using:)`, starts `SSHClient.withTTY`, yields stdout/stderr text into `AsyncStream<String>`, writes user input through `TTYStdinWriter`, and closes both the TTY task and SSH client from `close()`.

- [ ] **Step 4: Inject the real shell client for live stores**

Set `terminalShellClient = CitadelTerminalShellClient()` in:

```swift
static func persistent(repository: JSONHostRepository, credentialVault: CredentialVault) throws -> MobileShellStore
convenience init(repository: JSONHostRepository, credentialVault: CredentialVault) throws
```

- [ ] **Step 5: Run test to verify it passes**

Run the same targeted `xcodebuild test` command. Expected: PASS.

### Task 3: Verify Integration

**Files:**
- Verify: `MobileShellTests/MobileShellStoreTests.swift`
- Verify: entire iOS app target

- [ ] **Step 1: Run targeted store tests**

```bash
xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/MobileShellStoreTests
```

Expected: all `MobileShellStoreTests` pass.

- [ ] **Step 2: Run full tests**

```bash
xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'
```

Expected: all tests pass.

- [ ] **Step 3: Run app build**

```bash
xcodebuild build -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'
```

Expected: build exits 0.

---

## Self-Review

Spec coverage: The plan covers real interactive shell startup, input/output bridging, close behavior, live store injection, and host-key trust retry for shell startup.

Placeholder scan: No placeholders or deferred implementation steps remain.

Type consistency: The plan uses existing `TerminalShellClient`, `TerminalShellSession`, `HostKeyChallenge`, `PendingHostKeyAction`, and `MobileShellStore` names consistently.
