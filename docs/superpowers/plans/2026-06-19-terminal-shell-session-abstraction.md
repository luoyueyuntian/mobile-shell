# Terminal Shell Session Abstraction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a long-lived interactive terminal shell pipeline so MobileShell can evolve from single-command execution toward a Termius-style live SSH terminal.

**Architecture:** Introduce `TerminalShellClient` and `TerminalShellSession` protocols in `ShellConnection.swift`. `MobileShellStore` owns live shell sessions by terminal tab, listens to their output streams, sends command input to the active shell, and falls back to existing one-shot command execution only when no live shell exists.

**Tech Stack:** Swift 6, SwiftUI Observation, AsyncStream, XCTest, existing `SSHConnectionRequestBuilder`, `SSHCommandExecuting`, and terminal tab state.

---

### Task 1: Define A Testable Terminal Shell Client

**Files:**
- Modify: `MobileShell/ShellConnection.swift`
- Modify: `MobileShell/Models.swift`
- Test: `MobileShellTests/MobileShellStoreTests.swift`

- [ ] **Step 1: Write the failing test**

Add a test proving that opening an interactive terminal uses a shell client request and attaches the returned session.

```swift
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
    await Task.yield()

    XCTAssertEqual(shellClient.requests.first?.hostname, "shell.example.com")
    XCTAssertEqual(shellClient.requests.first?.port, 2202)
    XCTAssertEqual(shellClient.requests.first?.password, "shell-secret")
    XCTAssertEqual(store.selectedTerminalSession?.state, .connected)
    XCTAssertTrue(store.selectedTerminalSession?.lines.contains("welcome") == true)
    XCTAssertTrue(store.selectedTerminalSession?.lines.contains("deploy@shell-prod:~$") == true)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/MobileShellStoreTests/testOpeningInteractiveTerminalStartsShellSessionAndAppendsOutput`

Expected: build failure for missing `TerminalShellClient`, `TerminalShellSession`, `terminalShellClient`, and `openInteractiveTerminal`.

- [ ] **Step 3: Write minimal implementation**

Add protocols and Store plumbing.

```swift
protocol TerminalShellSession: Sendable {
    var outputStream: AsyncStream<String> { get }
    func send(_ input: String) async throws
    func close() async
}

protocol TerminalShellClient: Sendable {
    func openShell(using request: SSHConnectionRequest) async throws -> any TerminalShellSession
}
```

Store implementation should add:

```swift
private var terminalShellClient: (any TerminalShellClient)?
private var activeTerminalShellSessions: [TerminalSession.ID: any TerminalShellSession] = [:]
private var terminalShellOutputTasks: [TerminalSession.ID: Task<Void, Never>] = [:]
```

And:

```swift
@MainActor
func openInteractiveTerminal(for host: ShellHost) async {
    connect(to: host)
    guard let selectedSessionID else { return }
    await startTerminalShell(for: selectedSessionID)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run the same targeted test command.

### Task 2: Send Commands Through Live Shell Sessions

**Files:**
- Modify: `MobileShell/Models.swift`
- Test: `MobileShellTests/MobileShellStoreTests.swift`

- [ ] **Step 1: Write the failing test**

Add a test proving that command submission writes to the active live shell and clears only that tab draft.

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/MobileShellStoreTests/testRemoteCommandSendsInputToActiveShellSession`

Expected: failure because `runRemoteCommand` still uses the one-shot command executor path.

- [ ] **Step 3: Write minimal implementation**

In `runRemoteCommand`, after appending `$ command` and clearing draft, check `activeTerminalShellSessions[selectedSessionID]`. If present, send `trimmedCommand + "\n"` and return. If send fails, append the error and mark the session disconnected.

- [ ] **Step 4: Run test to verify it passes**

Run the same targeted test command.

### Task 3: Close Live Shell Sessions With Tabs

**Files:**
- Modify: `MobileShell/Models.swift`
- Test: `MobileShellTests/MobileShellStoreTests.swift`

- [ ] **Step 1: Write the failing test**

Add a test proving that closing a tab closes the live shell and cancels output listening.

```swift
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

    XCTAssertEqual(shellSession.closeCount, 1)
    XCTAssertNil(store.selectedSessionID)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/MobileShellStoreTests/testClosingTerminalSessionClosesActiveShellSession`

Expected: failure because `closeTerminalSession` does not close shell sessions yet.

- [ ] **Step 3: Write minimal implementation**

Extract `stopTerminalShell(for:)`:

```swift
private func stopTerminalShell(for sessionID: TerminalSession.ID) {
    terminalShellOutputTasks[sessionID]?.cancel()
    terminalShellOutputTasks[sessionID] = nil
    if let shell = activeTerminalShellSessions.removeValue(forKey: sessionID) {
        Task { await shell.close() }
    }
}
```

Call this from `closeTerminalSession` and host deletion cleanup.

- [ ] **Step 4: Run test to verify it passes**

Run the same targeted test command.

### Task 4: UI Uses Interactive Terminal Opening

**Files:**
- Modify: `MobileShell/ShellRootView.swift`
- Test: `MobileShellTests/MobileShellStoreTests.swift`

- [ ] **Step 1: Update host connect actions**

Change host row connect actions from `store.connect(to: host)` to:

```swift
Task { @MainActor in
    await store.openInteractiveTerminal(for: host)
}
```

The preview fallback should still work because `MobileShellStore.preview()` can use a preview shell client.

- [ ] **Step 2: Add preview shell client**

Add a `PreviewTerminalShellClient` and `PreviewTerminalShellSession` that emit a short welcome banner and echo sent commands.

- [ ] **Step 3: Run full verification**

Run:

```bash
xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/MobileShellStoreTests
xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'
xcodebuild build -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'
```

Expected: exit code 0 for all commands.

## Self-Review

- Spec coverage: This plan covers a live shell abstraction, opening sessions, stream output, command sending, tab cleanup, UI opening, and verification.
- Placeholder scan: No placeholder implementation language remains; every task names concrete files, APIs, tests, and expected failures.
- Type consistency: `TerminalShellClient`, `TerminalShellSession`, `openInteractiveTerminal`, and `activeTerminalShellSessions` are used consistently.
