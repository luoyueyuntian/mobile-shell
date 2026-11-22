# Terminal Workspaces Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add personal terminal workspaces that group active terminal sessions and allow switching terminal views.

**Architecture:** Add `TerminalWorkspace` under `MobileShell/Features/Workspaces`, persist workspaces in `HostPersistenceSnapshot`, coordinate membership and filtering through `MobileShellStore`, and render a lightweight workspace switcher above terminal tabs.

**Tech Stack:** Swift 6, SwiftUI Observation, XCTest, JSON snapshot persistence.

---

### Task 1: Workspace Behavior Tests

**Files:**
- Create: `MobileShellTests/Features/Workspaces/TerminalWorkspaceTests.swift`
- Modify: `MobileShell.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
@testable import MobileShell

final class TerminalWorkspaceTests: XCTestCase {
    func testCreatingWorkspaceTrimsNameSelectsItAndRecordsHistory() throws {
        let store = MobileShellStore()

        let workspace = try XCTUnwrap(store.createTerminalWorkspace(name: "  Production  "))

        XCTAssertEqual(workspace.name, "Production")
        XCTAssertEqual(store.terminalWorkspaces, [workspace])
        XCTAssertEqual(store.selectedWorkspaceID, workspace.id)
        XCTAssertEqual(store.history.first, "Created workspace Production")
    }

    func testConnectingHostWhileWorkspaceSelectedAddsSessionToWorkspaceAndFiltersVisibleSessions() throws {
        let firstHost = makeHost(name: "api", address: "api.example.com")
        let secondHost = makeHost(name: "db", address: "db.example.com")
        let store = MobileShellStore(hosts: [firstHost, secondHost])
        let workspace = try XCTUnwrap(store.createTerminalWorkspace(name: "Production"))

        store.connect(to: firstHost)
        store.selectTerminalWorkspace(nil)
        store.connect(to: secondHost)
        store.selectTerminalWorkspace(workspace.id)

        XCTAssertEqual(store.visibleTerminalSessions().map(\.hostName), ["api"])
        XCTAssertEqual(store.selectedTerminalSession?.hostName, "api")
    }

    func testConnectingExistingSessionAddsItToSelectedWorkspace() throws {
        let host = makeHost(name: "api", address: "api.example.com")
        let store = MobileShellStore(hosts: [host])

        store.connect(to: host)
        let workspace = try XCTUnwrap(store.createTerminalWorkspace(name: "Incident"))
        store.connect(to: host)

        XCTAssertEqual(store.terminalWorkspaces.first(where: { $0.id == workspace.id })?.sessionIDs, [try XCTUnwrap(store.selectedSessionID)])
        XCTAssertEqual(store.visibleTerminalSessions().map(\.hostName), ["api"])
    }

    func testClosingSessionRemovesItFromWorkspaceAndClearsEmptyWorkspaceSelection() throws {
        let host = makeHost(name: "api", address: "api.example.com")
        let store = MobileShellStore(hosts: [host])
        _ = try XCTUnwrap(store.createTerminalWorkspace(name: "Production"))
        store.connect(to: host)
        let sessionID = try XCTUnwrap(store.selectedSessionID)

        store.closeTerminalSession(sessionID)

        XCTAssertTrue(store.visibleTerminalSessions().isEmpty)
        XCTAssertNil(store.selectedSessionID)
        XCTAssertEqual(store.terminalWorkspaces.first?.sessionIDs, [])
    }

    func testWorkspacePersistenceRoundTrips() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repository = JSONHostRepository(fileURL: tempDirectory.appendingPathComponent("hosts.json"))
        let workspace = TerminalWorkspace(
            id: UUID(uuidString: "81818181-1111-2222-3333-818181818181")!,
            name: "Production",
            sessionIDs: [UUID(uuidString: "82828282-1111-2222-3333-828282828282")!],
            isBroadcastEnabled: true
        )

        try repository.save(HostPersistenceSnapshot(terminalWorkspaces: [workspace]))
        let reloaded = try repository.load()

        XCTAssertEqual(reloaded.terminalWorkspaces, [workspace])
    }

    private func makeHost(name: String, address: String) -> ShellHost {
        ShellHost(
            id: UUID(),
            name: name,
            address: address,
            username: "deploy",
            group: "Production",
            tags: ["ssh"],
            status: .idle
        )
    }
}
```

- [ ] **Step 2: Run and verify RED**

Run: `xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/TerminalWorkspaceTests`

Expected: FAIL because `TerminalWorkspace`, `terminalWorkspaces`, and workspace Store APIs do not exist.

### Task 2: Model, Persistence, And Store

**Files:**
- Create: `MobileShell/Features/Workspaces/TerminalWorkspace.swift`
- Modify: `MobileShell/Persistence.swift`
- Modify: `MobileShell/Models.swift`
- Modify: `MobileShell.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add `TerminalWorkspace` model**
- [ ] **Step 2: Add `terminalWorkspaces` to `HostPersistenceSnapshot` with `decodeIfPresent` fallback**
- [ ] **Step 3: Add Store workspace state and APIs**
- [ ] **Step 4: Update terminal connect/close lifecycle to maintain membership**
- [ ] **Step 5: Run targeted tests and verify GREEN**

### Task 3: Terminal UI Switcher

**Files:**
- Create: `MobileShell/Features/Workspaces/TerminalWorkspaceSwitcher.swift`
- Modify: `MobileShell/ShellRootView.swift`
- Modify: `MobileShell.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add `TerminalWorkspaceSwitcher` above terminal tabs**
- [ ] **Step 2: Change terminal tab list to `store.visibleTerminalSessions()`**
- [ ] **Step 3: Run full tests and app build**
