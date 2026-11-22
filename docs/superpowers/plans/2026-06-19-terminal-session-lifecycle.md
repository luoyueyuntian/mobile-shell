# Terminal Session Lifecycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Terminal tabs behave more like a Termius-style personal SSH workspace by adding per-session command drafts, explicit session selection/closing, and reconnectable session state.

**Architecture:** Keep the existing single-file model/view structure for this slice. Extend `TerminalSession` with lifecycle state and a per-session draft, add focused Store methods for select/close/update/reconnect, then bind `TerminalView` and `CommandBar` to those methods instead of the global `commandInput`.

**Tech Stack:** Swift 6, SwiftUI Observation, XCTest, existing `ShellConnectionClient` and `SSHConnectionRequestBuilder` abstractions.

---

### Task 1: Session Drafts And Selection

**Files:**
- Modify: `MobileShell/Models.swift`
- Modify: `MobileShell/ShellRootView.swift`
- Test: `MobileShellTests/MobileShellStoreTests.swift`

- [ ] **Step 1: Write failing tests**

Add tests that show a command draft belongs to the selected terminal session, switching sessions preserves each draft, and command submission clears only the active session draft.

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/MobileShellStoreTests/testTerminalDraftsAreScopedToSelectedSession`

Expected: build failure for missing `commandDraft`, `selectedTerminalSession`, `updateCommandDraft`, and `selectTerminalSession`.

- [ ] **Step 3: Write minimal implementation**

Add `commandDraft` to `TerminalSession`, expose `selectedTerminalSession`, and add draft/selection Store methods.

```swift
struct TerminalSession: Identifiable, Equatable, Codable {
    let id: UUID
    var hostID: ShellHost.ID
    var hostName: String
    var prompt: String
    var lines: [String]
    var commandDraft: String = ""
}

var selectedTerminalSession: TerminalSession? {
    guard let selectedSessionID else { return terminalSessions.first }
    return terminalSessions.first { $0.id == selectedSessionID }
}

func selectTerminalSession(_ sessionID: TerminalSession.ID) {
    guard terminalSessions.contains(where: { $0.id == sessionID }) else { return }
    selectedSessionID = sessionID
}

func updateCommandDraft(_ draft: String, for sessionID: TerminalSession.ID) {
    guard let index = terminalSessions.firstIndex(where: { $0.id == sessionID }) else { return }
    terminalSessions[index].commandDraft = draft
}
```

- [ ] **Step 4: Verify test passes**

Run the same targeted test command.

- [ ] **Step 5: Commit**

No git repository is present in this workspace, so record changes through the final response instead of committing.

### Task 2: Closing Sessions

**Files:**
- Modify: `MobileShell/Models.swift`
- Modify: `MobileShell/ShellRootView.swift`
- Test: `MobileShellTests/MobileShellStoreTests.swift`

- [ ] **Step 1: Write failing tests**

Add tests that close the selected session, select a sensible neighbor, remove cached connection requests, and leave the Terminal screen empty when the last session closes.

```swift
func testClosingSelectedTerminalSessionSelectsNeighborAndClearsRequest() throws {
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
    XCTAssertEqual(store.history.first, "Closed terminal db-replica-eu")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/MobileShellStoreTests/testClosingSelectedTerminalSessionSelectsNeighborAndClearsRequest`

Expected: build failure for missing `closeTerminalSession`.

- [ ] **Step 3: Write minimal implementation**

Add `closeTerminalSession(_:)` and update `TerminalView` tab pills with a small close button.

```swift
func closeTerminalSession(_ sessionID: TerminalSession.ID) {
    guard let index = terminalSessions.firstIndex(where: { $0.id == sessionID }) else { return }
    let closedSession = terminalSessions.remove(at: index)
    terminalConnectionRequests[closedSession.id] = nil
    history.insert("Closed terminal \(closedSession.hostName)", at: 0)

    guard selectedSessionID == sessionID else { return }
    if terminalSessions.isEmpty {
        selectedSessionID = nil
    } else {
        let replacementIndex = min(index, terminalSessions.count - 1)
        selectedSessionID = terminalSessions[replacementIndex].id
    }
}
```

- [ ] **Step 4: Verify test passes**

Run the same targeted test command.

- [ ] **Step 5: Commit**

No git repository is present in this workspace, so record changes through the final response instead of committing.

### Task 3: Reconnect Session State

**Files:**
- Modify: `MobileShell/Models.swift`
- Modify: `MobileShell/ShellRootView.swift`
- Test: `MobileShellTests/MobileShellStoreTests.swift`

- [ ] **Step 1: Write failing tests**

Add tests that mark a session disconnected, reconnect it, refresh the cached request, and append a visible reconnect line.

```swift
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
    store.reconnectTerminalSession(sessionID)

    XCTAssertEqual(store.selectedTerminalSession?.state, .connected)
    XCTAssertTrue(store.selectedTerminalSession?.lines.contains("Reconnected to edge-prod") == true)
    XCTAssertEqual(store.history.first, "Reconnected terminal edge-prod")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/MobileShellStoreTests/testReconnectingTerminalSessionMarksItConnectedAndRefreshesPrompt`

Expected: build failure for missing `TerminalSessionState`, `state`, `markTerminalSessionDisconnected`, and `reconnectTerminalSession`.

- [ ] **Step 3: Write minimal implementation**

Add a Codable session state enum and Store methods to mark disconnected/reconnected.

```swift
enum TerminalSessionState: String, Codable {
    case connected
    case disconnected
    case reconnecting
}

func markTerminalSessionDisconnected(_ sessionID: TerminalSession.ID, reason: String) {
    guard let index = terminalSessions.firstIndex(where: { $0.id == sessionID }) else { return }
    terminalSessions[index].state = .disconnected
    terminalSessions[index].lines.append("Disconnected: \(reason)")
}

func reconnectTerminalSession(_ sessionID: TerminalSession.ID) {
    guard let index = terminalSessions.firstIndex(where: { $0.id == sessionID }),
          let host = hosts.first(where: { $0.id == terminalSessions[index].hostID })
    else { return }
    terminalSessions[index].state = .connected
    terminalSessions[index].prompt = "\(host.username)@\(host.name):~$"
    terminalSessions[index].lines.append("Reconnected to \(host.name)")
    terminalConnectionRequests[sessionID] = try? SSHConnectionRequestBuilder(
        credentialVault: credentialVault,
        knownHosts: knownHosts
    ).request(for: host)
    history.insert("Reconnected terminal \(host.name)", at: 0)
}
```

- [ ] **Step 4: Verify test passes**

Run the same targeted test command.

- [ ] **Step 5: Commit**

No git repository is present in this workspace, so record changes through the final response instead of committing.

### Task 4: Full Verification

**Files:**
- Test: `MobileShellTests/MobileShellStoreTests.swift`
- Test: `MobileShellTests/MobileShellPersistenceTests.swift`

- [ ] **Step 1: Run focused Terminal tests**

Run: `xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/MobileShellStoreTests`

Expected: all `MobileShellStoreTests` pass.

- [ ] **Step 2: Run all tests**

Run: `xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'`

Expected: all test suites pass.

- [ ] **Step 3: Run app build**

Run: `xcodebuild build -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'`

Expected: exit code 0.

## Self-Review

- Spec coverage: The plan covers per-session draft state, selection, closing, reconnect state, UI affordances, and test/build verification.
- Placeholder scan: No placeholder terms are used for implementation work; commit steps explicitly note the absent git repository.
- Type consistency: `TerminalSessionState`, `commandDraft`, `selectedTerminalSession`, and Store method names are consistent across tasks.
