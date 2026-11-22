# Host Environment Variables Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Termius-style host and group environment variables with inheritance and startup export injection.

**Architecture:** `ShellEnvironmentVariable` is a shared Codable model with parsing and export-command helpers. `ShellHost` and `HostGroupProfile` store sanitized variables, while `MobileShellStore.environmentVariables(for:)` resolves group defaults plus host overrides. Terminal startup paths export resolved variables before startup snippets, and SwiftUI editors use a focused environment-variable text editor component.

**Tech Stack:** Swift 6, SwiftUI Observation, XCTest, JSON Codable persistence.

---

### Task 1: Environment Variable Tests

**Files:**
- Create: `MobileShellTests/Features/Environment/HostEnvironmentVariableTests.swift`
- Modify: `MobileShell.xcodeproj/project.pbxproj`

- [x] **Step 1: Write failing tests**

Create tests for inheritance, host overrides, sanitization, persistence, preview startup ordering, and live shell startup ordering:

```swift
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

    func testConnectingNewPreviewSessionExportsEnvironmentBeforeStartupSnippet() throws {
        let snippet = ShellSnippet(id: UUID(), title: "Print env", command: "echo $APP_ENV")
        let host = makeHost(
            name: "api",
            group: "Production",
            startupSnippetID: snippet.id,
            environmentVariables: [ShellEnvironmentVariable(key: "APP_ENV", value: "prod's")]
        )
        let store = MobileShellStore(hosts: [host], snippets: [snippet])

        store.connect(to: host)

        let session = try XCTUnwrap(store.selectedTerminalSession)
        XCTAssertEqual(session.lines.prefix(3), [
            "Connected to api at deploy@api.example.com",
            "$ export APP_ENV='prod'\\''s'",
            "Command queued in preview terminal: export APP_ENV='prod'\\''s'"
        ])
        XCTAssertTrue(session.lines.firstIndex(of: "$ export APP_ENV='prod'\\''s'")! < session.lines.firstIndex(of: "$ echo $APP_ENV")!)
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
```

- [x] **Step 2: Run and verify RED**

Run:

```bash
xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/HostEnvironmentVariableTests
```

Expected: FAIL because `ShellEnvironmentVariable`, environment-variable model fields, and `environmentVariables(for:)` do not exist.

### Task 2: Shared Model And Store Resolution

**Files:**
- Create: `MobileShell/Shared/Models/ShellEnvironmentVariable.swift`
- Modify: `MobileShell.xcodeproj/project.pbxproj`
- Modify: `MobileShell/Models.swift`
- Modify: `MobileShell/Features/HostGroups/HostGroupProfile.swift`

- [x] **Step 1: Add `ShellEnvironmentVariable`**

Implement `ShellEnvironmentVariable` with key/value storage, `parseLines(_:)`, `text(from:)`, and `exportCommand`.

- [x] **Step 2: Add environment variables to host and group models**

Add `[ShellEnvironmentVariable]` to `ShellHost` and `HostGroupProfile`, defaulting to `[]` for legacy JSON.

- [x] **Step 3: Resolve inherited environment variables**

Add `MobileShellStore.environmentVariables(for:)` that merges group variables and host variables with host keys winning.

- [x] **Step 4: Thread variables through save APIs**

Add `environmentVariables: [ShellEnvironmentVariable] = []` to host add/update helpers and `upsertHostGroupProfile`, sanitized through the new model helper.

- [x] **Step 5: Run targeted tests**

Run the same targeted `xcodebuild test` command. Expected: remaining failures should only involve startup export injection or UI if not implemented yet.

### Task 3: Startup Export Injection

**Files:**
- Modify: `MobileShell/Models.swift`

- [x] **Step 1: Export environment variables for preview sessions**

Before `runStartupSnippetPreview`, run each resolved variable's export command through the existing preview command path.

- [x] **Step 2: Export environment variables for live shells**

After `startTerminalShell` succeeds and before `runStartupSnippetIfNeeded`, send each export command with `recordHistory: false` and `clearDraft: false`.

- [x] **Step 3: Run targeted tests and verify GREEN**

Run:

```bash
xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/HostEnvironmentVariableTests
```

Expected: PASS.

### Task 4: SwiftUI Editing

**Files:**
- Create: `MobileShell/Features/Environment/EnvironmentVariablesTextEditor.swift`
- Modify: `MobileShell.xcodeproj/project.pbxproj`
- Modify: `MobileShell/ShellRootView.swift`

- [x] **Step 1: Add reusable editor component**

Create `EnvironmentVariablesTextEditor`, a compact SwiftUI view wrapping a monospaced multiline `TextEditor` with helper text.

- [x] **Step 2: Add group editor state and save wiring**

Add `@State private var environmentVariablesText`, initialize it from the group profile, render the editor, and pass parsed variables to `upsertHostGroupProfile`.

- [x] **Step 3: Add host editor state and save wiring**

Add environment variable text state to Add Host and Edit Host, render the editor, and pass parsed variables to add/update host APIs.

- [x] **Step 4: Run full verification**

Run:

```bash
xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/HostEnvironmentVariableTests
xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'
xcodebuild build -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'
```

Expected: all commands exit 0. `git status --short` is expected to fail in this workspace because `/Users/xuhuihui/my-project/mobile-shell` is not a git repository.

---

## Self-Review

Spec coverage: The plan covers the model, parser, inheritance, persistence, terminal injection, UI editing, and verification requirements.

Placeholder scan: No placeholders or deferred behavior remain.

Type consistency: `ShellEnvironmentVariable`, `environmentVariables`, `environmentVariables(for:)`, and `EnvironmentVariablesTextEditor` are introduced before later steps use them.
