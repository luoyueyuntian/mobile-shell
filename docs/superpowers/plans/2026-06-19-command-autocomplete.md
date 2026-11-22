# Command Autocomplete Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add local Termius-style command autocomplete from snippets, history, and built-in shell commands.

**Architecture:** Add focused autocomplete model/engine files under `MobileShell/Features/Autocomplete`, expose them through `MobileShellStore`, and render a suggestion strip from `CommandBar`. Keep SSH execution unchanged; selecting a suggestion only updates the terminal draft.

**Tech Stack:** Swift 6, SwiftUI, Observation, XCTest.

---

### Task 1: Autocomplete Engine Tests

**Files:**
- Create: `MobileShellTests/Features/Autocomplete/CommandAutocompleteTests.swift`
- Modify: `MobileShell.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
@testable import MobileShell

final class CommandAutocompleteTests: XCTestCase {
    func testSuggestionsPreferSnippetsThenHistoryThenBuiltins() {
        let store = MobileShellStore(
            snippets: [
                ShellSnippet(id: UUID(), title: "Disk Usage", command: "df -h"),
                ShellSnippet(id: UUID(), title: "Docker Logs", command: "docker logs api")
            ],
            history: ["df -h", "docker ps"]
        )

        let suggestions = store.commandSuggestions(for: "d")

        XCTAssertEqual(suggestions.map(\.command), ["df -h", "docker logs api", "docker ps", "du -sh *"])
        XCTAssertEqual(suggestions.first?.source, .snippet)
    }

    func testSuggestionsDeduplicateCommandsAndIgnoreBlankInput() {
        let store = MobileShellStore(
            snippets: [ShellSnippet(id: UUID(), title: "Disk Usage", command: "df -h")],
            history: ["df -h", " uptime "]
        )

        XCTAssertTrue(store.commandSuggestions(for: "   ").isEmpty)
        XCTAssertEqual(store.commandSuggestions(for: "df").map(\.command), ["df -h"])
    }

    func testApplyingSuggestionUpdatesSelectedTerminalDraft() throws {
        let host = ShellHost(id: UUID(), name: "api", address: "api.example.com", username: "deploy", group: "Production", tags: ["ssh"], status: .idle)
        let store = MobileShellStore(hosts: [host])
        store.connect(to: host)

        store.applyCommandSuggestion(CommandSuggestion(title: "Disk Usage", command: "df -h", source: .snippet))

        XCTAssertEqual(store.selectedTerminalSession?.commandDraft, "df -h")
        XCTAssertEqual(store.commandInput, "df -h")
    }

    func testUsingSnippetUpdatesActiveTerminalDraft() throws {
        let host = ShellHost(id: UUID(), name: "api", address: "api.example.com", username: "deploy", group: "Production", tags: ["ssh"], status: .idle)
        let snippet = ShellSnippet(id: UUID(), title: "Health", command: "systemctl status api")
        let store = MobileShellStore(hosts: [host], snippets: [snippet])
        store.connect(to: host)

        store.useSnippet(snippet)

        XCTAssertEqual(store.selectedTerminalSession?.commandDraft, "systemctl status api")
        XCTAssertEqual(store.selectedSection, .terminals)
    }
}
```

- [ ] **Step 2: Run and verify RED**

Run: `xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/CommandAutocompleteTests`

Expected: FAIL because `CommandSuggestion`, `commandSuggestions(for:)`, and `applyCommandSuggestion(_:)` do not exist yet.

### Task 2: Autocomplete Model And Engine

**Files:**
- Create: `MobileShell/Features/Autocomplete/CommandSuggestion.swift`
- Create: `MobileShell/Features/Autocomplete/CommandAutocompleteEngine.swift`
- Modify: `MobileShell.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add suggestion model and source enum**
- [ ] **Step 2: Add a pure engine that filters, ranks, deduplicates, and limits results**
- [ ] **Step 3: Run targeted tests and verify remaining failures are Store integration only**

### Task 3: Store And UI Integration

**Files:**
- Modify: `MobileShell/Models.swift`
- Modify: `MobileShell/ShellRootView.swift`

- [ ] **Step 1: Add `commandSuggestions(for:)` and `applyCommandSuggestion(_:)` to `MobileShellStore`**
- [ ] **Step 2: Update `useSnippet(_:)` to populate the selected session draft when a terminal is active**
- [ ] **Step 3: Render suggestions above the command input and apply suggestions on tap**
- [ ] **Step 4: Run targeted tests, full tests, and build**
