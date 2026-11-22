# Terminal Theme Inheritance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add personal Termius-style terminal theme presets with host and group inheritance.

**Architecture:** A focused `TerminalTheme` enum owns built-in theme names and SwiftUI colors. `ShellHost` and `HostGroupProfile` store optional theme choices, while `MobileShellStore.terminalTheme(for:)` resolves host override, group fallback, then default. SwiftUI editors expose optional pickers and `TerminalView` applies the resolved selected-session theme.

**Tech Stack:** Swift 6, SwiftUI Observation, XCTest, JSON Codable persistence.

---

### Task 1: Theme Inheritance Tests

**Files:**
- Create: `MobileShellTests/Features/Terminal/TerminalThemeInheritanceTests.swift`
- Modify: `MobileShell.xcodeproj/project.pbxproj`

- [x] **Step 1: Write failing tests**

Create tests for default theme, group inheritance, host override, persistence, and group upsert:

```swift
import XCTest
@testable import MobileShell

final class TerminalThemeInheritanceTests: XCTestCase {
    func testTerminalThemeDefaultsToObsidianNeon() {
        let host = makeHost(name: "api")
        let store = MobileShellStore(hosts: [host])

        XCTAssertEqual(store.terminalTheme(for: host), .obsidianNeon)
    }

    func testTerminalThemeFallsBackToGroupTheme() {
        let host = makeHost(name: "api", group: "Production")
        let store = MobileShellStore(
            hosts: [host],
            hostGroupProfiles: [
                HostGroupProfile(name: "Production", identityID: nil, terminalTheme: .solarizedDark)
            ]
        )

        XCTAssertEqual(store.terminalTheme(for: host), .solarizedDark)
    }

    func testHostTerminalThemeOverridesGroupTheme() {
        let host = makeHost(name: "api", group: "Production", terminalTheme: .everforestDark)
        let store = MobileShellStore(
            hosts: [host],
            hostGroupProfiles: [
                HostGroupProfile(name: "Production", identityID: nil, terminalTheme: .solarizedDark)
            ]
        )

        XCTAssertEqual(store.terminalTheme(for: host), .everforestDark)
    }

    func testHostAndGroupTerminalThemesPersist() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = JSONHostRepository(fileURL: directory.appendingPathComponent("vault.json"))
        let host = makeHost(name: "api", group: "Production", terminalTheme: .everforestDark)
        let profile = HostGroupProfile(name: "Production", identityID: nil, terminalTheme: .solarizedDark)

        try repository.save(HostPersistenceSnapshot(hosts: [host], hostGroupProfiles: [profile]))
        let loaded = try repository.load()

        XCTAssertEqual(loaded.hosts.first?.terminalTheme, .everforestDark)
        XCTAssertEqual(loaded.hostGroupProfiles.first?.terminalTheme, .solarizedDark)
    }

    func testUpsertingGroupProfileStoresTerminalTheme() throws {
        let store = MobileShellStore()

        let profile = try XCTUnwrap(store.upsertHostGroupProfile(
            name: "Production",
            identityID: nil,
            terminalTheme: .solarizedDark
        ))

        XCTAssertEqual(profile.terminalTheme, .solarizedDark)
        XCTAssertEqual(store.hostGroupProfiles.first?.terminalTheme, .solarizedDark)
    }

    private func makeHost(
        name: String,
        group: String = "Production",
        terminalTheme: TerminalTheme? = nil
    ) -> ShellHost {
        ShellHost(
            id: UUID(),
            name: name,
            address: "\(name).example.com",
            username: "deploy",
            group: group,
            tags: ["ssh"],
            status: .idle,
            terminalTheme: terminalTheme
        )
    }
}
```

- [x] **Step 2: Run and verify RED**

Run:

```bash
xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/TerminalThemeInheritanceTests
```

Expected: FAIL because `TerminalTheme`, `ShellHost.terminalTheme`, `HostGroupProfile.terminalTheme`, and `MobileShellStore.terminalTheme(for:)` do not exist.

### Task 2: Theme Model And Store Resolution

**Files:**
- Create: `MobileShell/Features/Terminal/TerminalTheme.swift`
- Modify: `MobileShell/Features/HostGroups/HostGroupProfile.swift`
- Modify: `MobileShell/Models.swift`
- Modify: `MobileShell.xcodeproj/project.pbxproj`

- [x] **Step 1: Create `TerminalTheme`**

Add a `TerminalTheme` enum with `.obsidianNeon`, `.solarizedDark`, and `.everforestDark`, plus `displayName`, `terminalBackground`, `terminalForeground`, `promptForeground`, and `mutedForeground` colors.

- [x] **Step 2: Add theme fields to host and group models**

Add optional `terminalTheme: TerminalTheme?` to `ShellHost` and `HostGroupProfile`, including `ShellHost` initializer, coding keys, and legacy-safe decoding.

- [x] **Step 3: Resolve theme through host, group, default**

Add:

```swift
func terminalTheme(for host: ShellHost) -> TerminalTheme {
    host.terminalTheme ?? hostGroupProfile(for: host)?.terminalTheme ?? .obsidianNeon
}
```

- [x] **Step 4: Thread theme through host and group save APIs**

Add optional `terminalTheme` parameters to host add/update helpers and `upsertHostGroupProfile`.

- [x] **Step 5: Run targeted tests and verify GREEN**

Run the same targeted `xcodebuild test` command. Expected: PASS.

### Task 3: Theme Picker UI And Terminal Rendering

**Files:**
- Modify: `MobileShell/ShellRootView.swift`

- [x] **Step 1: Apply selected theme in `TerminalView`**

Compute `selectedTheme` from the selected session's host and apply its colors to the terminal scroll area and line text. Use the default theme when no session is selected.

- [x] **Step 2: Add group terminal theme picker**

Add `@State private var terminalTheme: TerminalTheme?` to `HostGroupEditorSheet`, initialize it from the profile, add an Appearance section, and pass it to `upsertHostGroupProfile`.

- [x] **Step 3: Add host terminal theme pickers**

Add optional terminal theme state to Add Host and Edit Host sheets, add an Appearance section with "Group / Default" plus all built-in themes, and pass it to add/update host APIs.

- [x] **Step 4: Run targeted tests, full tests, and build**

Run:

```bash
xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/TerminalThemeInheritanceTests
xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'
xcodebuild build -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'
```

Expected: all commands exit 0.

---

## Self-Review

Spec coverage: The plan covers theme presets, host override, group fallback, default theme, persistence, editor UI, terminal rendering, and verification.

Placeholder scan: No placeholders or deferred behavior remain.

Type consistency: `TerminalTheme`, `terminalTheme`, and `terminalTheme(for:)` are introduced before later tasks use them.
