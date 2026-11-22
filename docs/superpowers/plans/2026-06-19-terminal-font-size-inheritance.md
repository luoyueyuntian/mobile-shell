# Terminal Font Size Inheritance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add personal Termius-style terminal font size presets with host and group inheritance.

**Architecture:** A focused `TerminalFontSize` enum owns display names and point sizes. `ShellHost` and `HostGroupProfile` store optional font size choices, while `MobileShellStore.terminalFontSize(for:)` resolves host override, group fallback, then default. SwiftUI editors expose optional pickers and `TerminalView` applies the resolved selected-session font size.

**Tech Stack:** Swift 6, SwiftUI Observation, XCTest, JSON Codable persistence.

---

### Task 1: Font Size Inheritance Tests

**Files:**
- Create: `MobileShellTests/Features/Terminal/TerminalFontSizeInheritanceTests.swift`
- Modify: `MobileShell.xcodeproj/project.pbxproj`

- [x] **Step 1: Write failing tests**

Create tests for default font size, group inheritance, host override, persistence, and group upsert:

```swift
import XCTest
@testable import MobileShell

final class TerminalFontSizeInheritanceTests: XCTestCase {
    func testTerminalFontSizeDefaultsToStandard() {
        let host = makeHost(name: "api")
        let store = MobileShellStore(hosts: [host])

        XCTAssertEqual(store.terminalFontSize(for: host), .standard)
        XCTAssertEqual(store.terminalFontSize(for: host).pointSize, 13)
    }

    func testTerminalFontSizeFallsBackToGroupFontSize() {
        let host = makeHost(name: "api", group: "Production")
        let store = MobileShellStore(
            hosts: [host],
            hostGroupProfiles: [
                HostGroupProfile(name: "Production", identityID: nil, terminalFontSize: .large)
            ]
        )

        XCTAssertEqual(store.terminalFontSize(for: host), .large)
    }

    func testHostTerminalFontSizeOverridesGroupFontSize() {
        let host = makeHost(name: "api", group: "Production", terminalFontSize: .extraLarge)
        let store = MobileShellStore(
            hosts: [host],
            hostGroupProfiles: [
                HostGroupProfile(name: "Production", identityID: nil, terminalFontSize: .small)
            ]
        )

        XCTAssertEqual(store.terminalFontSize(for: host), .extraLarge)
    }

    func testHostAndGroupTerminalFontSizesPersist() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = JSONHostRepository(fileURL: directory.appendingPathComponent("vault.json"))
        let host = makeHost(name: "api", group: "Production", terminalFontSize: .extraLarge)
        let profile = HostGroupProfile(name: "Production", identityID: nil, terminalFontSize: .large)

        try repository.save(HostPersistenceSnapshot(hosts: [host], hostGroupProfiles: [profile]))
        let loaded = try repository.load()

        XCTAssertEqual(loaded.hosts.first?.terminalFontSize, .extraLarge)
        XCTAssertEqual(loaded.hostGroupProfiles.first?.terminalFontSize, .large)
    }

    func testUpsertingGroupProfileStoresTerminalFontSize() throws {
        let store = MobileShellStore()

        let profile = try XCTUnwrap(store.upsertHostGroupProfile(
            name: "Production",
            identityID: nil,
            terminalFontSize: .large
        ))

        XCTAssertEqual(profile.terminalFontSize, .large)
        XCTAssertEqual(store.hostGroupProfiles.first?.terminalFontSize, .large)
    }

    private func makeHost(
        name: String,
        group: String = "Production",
        terminalFontSize: TerminalFontSize? = nil
    ) -> ShellHost {
        ShellHost(
            id: UUID(),
            name: name,
            address: "\(name).example.com",
            username: "deploy",
            group: group,
            tags: ["ssh"],
            status: .idle,
            terminalFontSize: terminalFontSize
        )
    }
}
```

- [x] **Step 2: Run and verify RED**

Run:

```bash
xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/TerminalFontSizeInheritanceTests
```

Expected: FAIL because `TerminalFontSize`, `ShellHost.terminalFontSize`, `HostGroupProfile.terminalFontSize`, and `MobileShellStore.terminalFontSize(for:)` do not exist.

### Task 2: Font Size Model And Store Resolution

**Files:**
- Modify: `MobileShell/Features/Terminal/TerminalTheme.swift`
- Modify: `MobileShell/Features/HostGroups/HostGroupProfile.swift`
- Modify: `MobileShell/Models.swift`

- [x] **Step 1: Add `TerminalFontSize`**

Add a `TerminalFontSize` enum with `.small`, `.standard`, `.large`, and `.extraLarge`, plus `displayName` and `pointSize`.

- [x] **Step 2: Add font size fields to host and group models**

Add optional `terminalFontSize: TerminalFontSize?` to `ShellHost` and `HostGroupProfile`, including `ShellHost` initializer, coding keys, and legacy-safe decoding.

- [x] **Step 3: Resolve font size through host, group, default**

Add:

```swift
func terminalFontSize(for host: ShellHost) -> TerminalFontSize {
    host.terminalFontSize ?? hostGroupProfile(for: host)?.terminalFontSize ?? .standard
}
```

- [x] **Step 4: Thread font size through host and group save APIs**

Add optional `terminalFontSize` parameters to host add/update helpers and `upsertHostGroupProfile`.

- [x] **Step 5: Run targeted tests and verify GREEN**

Run the same targeted `xcodebuild test` command. Expected: PASS.

### Task 3: Font Size Picker UI And Terminal Rendering

**Files:**
- Modify: `MobileShell/ShellRootView.swift`

- [x] **Step 1: Apply selected font size in `TerminalView`**

Compute `selectedFontSize` from the selected session's host and apply `selectedFontSize.pointSize` to terminal output lines.

- [x] **Step 2: Add group terminal font size picker**

Add `@State private var terminalFontSize: TerminalFontSize?` to `HostGroupEditorSheet`, initialize it from the profile, add it to the Appearance section, and pass it to `upsertHostGroupProfile`.

- [x] **Step 3: Add host terminal font size pickers**

Add optional terminal font size state to Add Host and Edit Host sheets, add it to each Appearance section with "Group / Default" plus all built-in sizes, and pass it to add/update host APIs.

- [x] **Step 4: Run targeted tests, full tests, and build**

Run:

```bash
xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/TerminalFontSizeInheritanceTests
xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'
xcodebuild build -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'
```

Expected: all commands exit 0.

---

## Self-Review

Spec coverage: The plan covers font size presets, host override, group fallback, default size, persistence, editor UI, terminal rendering, and verification.

Placeholder scan: No placeholders or deferred behavior remain.

Type consistency: `TerminalFontSize`, `terminalFontSize`, and `terminalFontSize(for:)` are introduced before later tasks use them.
