# Session Logs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add personal Termius-style session logs that automatically capture terminal activity per host, persist locally, and expose a Logs section for review.

**Architecture:** Add a focused `SessionLog` model under `MobileShell/Features/Logs`, persist logs through `HostPersistenceSnapshot`, and have `MobileShellStore` mirror terminal line mutations into the active log for each terminal session. The UI gets a lightweight Logs section that lists local logs newest-first and shows captured command/output previews, intentionally excluding team sync/sharing.

**Tech Stack:** Swift, SwiftUI Observation, XCTest, existing JSON snapshot persistence.

---

### Task 1: Session Log Behavior Tests

**Files:**
- Create: `MobileShellTests/Features/Logs/SessionLogTests.swift`
- Modify: `MobileShell.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
@testable import MobileShell

final class SessionLogTests: XCTestCase {
    func testConnectingHostCreatesSessionLogWithInitialTerminalLines() throws {
        let host = makeHost()
        let store = MobileShellStore(hosts: [host])

        store.connect(to: host)

        let log = try XCTUnwrap(store.sessionLogs.first)
        XCTAssertEqual(log.hostID, host.id)
        XCTAssertEqual(log.hostName, "api-prod")
        XCTAssertEqual(log.lines, store.selectedTerminalSession?.lines)
        XCTAssertNil(log.endedAt)
    }

    func testRunningPreviewCommandAppendsPromptAndOutputToSessionLog() throws {
        let host = makeHost()
        let store = MobileShellStore(hosts: [host])

        store.connect(to: host)
        store.runCommand("uptime")

        let log = try XCTUnwrap(store.sessionLogs.first)
        XCTAssertTrue(log.lines.contains("$ uptime"))
        XCTAssertTrue(log.lines.contains { $0.contains("load average") })
    }

    func testClosingTerminalSessionMarksSessionLogEnded() throws {
        let host = makeHost()
        let store = MobileShellStore(hosts: [host])

        store.connect(to: host)
        let sessionID = try XCTUnwrap(store.selectedSessionID)
        store.closeTerminalSession(sessionID)

        XCTAssertNotNil(store.sessionLogs.first?.endedAt)
    }

    func testStorePersistsSessionLogs() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repository = JSONHostRepository(fileURL: tempDirectory.appendingPathComponent("hosts.json"))
        let log = SessionLog(
            id: UUID(uuidString: "71717171-1111-2222-3333-717171717171")!,
            hostID: UUID(uuidString: "72727272-1111-2222-3333-727272727272")!,
            hostName: "api-prod",
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200),
            lines: ["connected", "$ uptime", "load average: 0.12"]
        )

        try repository.save(HostPersistenceSnapshot(sessionLogs: [log]))
        let reloaded = try repository.load()

        XCTAssertEqual(reloaded.sessionLogs, [log])
    }

    private func makeHost() -> ShellHost {
        ShellHost(
            id: UUID(uuidString: "73737373-1111-2222-3333-737373737373")!,
            name: "api-prod",
            address: "api.example.com",
            username: "deploy",
            group: "Production",
            tags: ["ssh"],
            status: .idle
        )
    }
}
```

- [ ] **Step 2: Run the targeted test and verify RED**

Run: `xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/SessionLogTests`

Expected: FAIL because `sessionLogs` / `SessionLog` do not exist yet.

### Task 2: Model, Store Capture, and Persistence

**Files:**
- Create: `MobileShell/Features/Logs/SessionLog.swift`
- Modify: `MobileShell/Models.swift`
- Modify: `MobileShell/Persistence.swift`
- Modify: `MobileShell.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add `SessionLog`**

```swift
import Foundation

struct SessionLog: Identifiable, Equatable, Codable {
    let id: UUID
    var hostID: ShellHost.ID
    var hostName: String
    var startedAt: Date
    var endedAt: Date?
    var lines: [String]

    init(
        id: UUID = UUID(),
        hostID: ShellHost.ID,
        hostName: String,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        lines: [String] = []
    ) {
        self.id = id
        self.hostID = hostID
        self.hostName = hostName
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.lines = lines
    }

    var lineCount: Int { lines.count }

    var preview: String {
        lines.suffix(3).joined(separator: "\n")
    }
}
```

- [ ] **Step 2: Persist logs in snapshots**

Add `sessionLogs: [SessionLog]` to `HostPersistenceSnapshot`, constructor, coding keys, and decoding with `decodeIfPresent(... ) ?? []`.

- [ ] **Step 3: Mirror terminal activity to logs**

Add `var sessionLogs: [SessionLog] = []` and private `terminalSessionLogIDs: [TerminalSession.ID: SessionLog.ID] = [:]` to `MobileShellStore`. Start a log when a new terminal session is opened, append the exact same prompt/output/disconnect lines whenever terminal lines are appended, close the log when the terminal session is closed, and update log host names when hosts are edited.

- [ ] **Step 4: Run targeted tests and verify GREEN**

Run: `xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/SessionLogTests`

Expected: PASS.

### Task 3: Logs Navigation and UI

**Files:**
- Create: `MobileShell/Features/Logs/SessionLogsView.swift`
- Modify: `MobileShell/Models.swift`
- Modify: `MobileShell/ShellRootView.swift`
- Modify: `MobileShell.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add Logs section**

Add `.logs` to `ShellSection`, with title `Logs`, symbol `doc.text.magnifyingglass`, compact title `Logs`, and sidebar count `store.sessionLogs.count`.

- [ ] **Step 2: Add `SessionLogsView`**

Create a SwiftUI view that shows a clear empty state when no logs exist, otherwise lists logs sorted newest-first with host name, open/ended state, line count, start time, and a monospaced preview.

- [ ] **Step 3: Wire `ActiveSectionView`**

Render `SessionLogsView(store: store)` for `.logs`.

- [ ] **Step 4: Build and run full verification**

Run: `xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'`

Run: `xcodebuild build -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'`

Expected: both commands pass without new warnings.
