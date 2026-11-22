# Terminal Keyboard Shortcuts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the existing terminal extra keyboard row send useful mobile SSH control keys and symbols.

**Architecture:** Add a small `TerminalKeyboardShortcut` model with labels and raw SSH input sequences. `MobileShellStore` owns dispatch behavior: active live shells receive raw bytes immediately, while inactive/preview sessions only append printable symbols to the command draft. The SwiftUI keyboard row becomes a set of buttons that call the store.

**Tech Stack:** Swift, SwiftUI, XCTest.

---

### Task 1: Store-Level Shortcut Dispatch

**Files:**
- Modify: `MobileShell/Models.swift`
- Modify: `MobileShellTests/MobileShellStoreTests.swift`

- [ ] **Step 1: Write failing tests**

Add these tests near the interactive terminal tests:

```swift
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
    await store.sendTerminalKeyboardShortcut(.controlC)
    await store.sendTerminalKeyboardShortcut(.tab)

    XCTAssertEqual(shellSession.sentInputs, ["\u{03}", "\t"])
    XCTAssertTrue(store.history.isEmpty)
}
```

```swift
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
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/MobileShellStoreTests/testTerminalShortcutSendsRawControlInputToActiveShellSession -only-testing:MobileShellTests/MobileShellStoreTests/testPrintableTerminalShortcutAppendsToDraftWhenNoLiveShellIsActive
```

Expected: FAIL because `TerminalKeyboardShortcut` and `sendTerminalKeyboardShortcut` are undefined.

- [ ] **Step 3: Implement model and store dispatch**

Add this enum near `TerminalSessionState`:

```swift
enum TerminalKeyboardShortcut: String, CaseIterable, Identifiable, Equatable, Sendable {
    case escape
    case tab
    case controlC
    case controlD
    case dash
    case slash
    case tilde
    case pipe

    var id: String { rawValue }

    var label: String {
        switch self {
        case .escape: "esc"
        case .tab: "tab"
        case .controlC: "ctrl-c"
        case .controlD: "ctrl-d"
        case .dash: "-"
        case .slash: "/"
        case .tilde: "~"
        case .pipe: "|"
        }
    }

    var input: String {
        switch self {
        case .escape: "\u{1B}"
        case .tab: "\t"
        case .controlC: "\u{03}"
        case .controlD: "\u{04}"
        case .dash: "-"
        case .slash: "/"
        case .tilde: "~"
        case .pipe: "|"
        }
    }

    var appendsToDraftWithoutLiveShell: Bool {
        switch self {
        case .dash, .slash, .tilde, .pipe:
            true
        case .escape, .tab, .controlC, .controlD:
            false
        }
    }
}
```

Add this store method:

```swift
@MainActor
func sendTerminalKeyboardShortcut(_ shortcut: TerminalKeyboardShortcut) async {
    guard let selectedSessionID,
          let index = terminalSessions.firstIndex(where: { $0.id == selectedSessionID })
    else { return }

    if let shell = activeTerminalShellSessions[selectedSessionID] {
        do {
            try await shell.send(shortcut.input)
        } catch {
            markTerminalSessionDisconnected(selectedSessionID, reason: error.localizedDescription)
        }
        return
    }

    guard shortcut.appendsToDraftWithoutLiveShell else { return }
    updateCommandDraft(terminalSessions[index].commandDraft + shortcut.input, for: selectedSessionID)
}
```

- [ ] **Step 4: Run tests to verify pass**

Run the same targeted command. Expected: PASS.

### Task 2: Wire SwiftUI Extra Keyboard Row

**Files:**
- Modify: `MobileShell/ShellRootView.swift`

- [ ] **Step 1: Replace inert labels with buttons**

Change `ExtraKeyboardRow()` to `ExtraKeyboardRow(store: store)`.

Update `ExtraKeyboardRow` so it stores `@Bindable var store: MobileShellStore`, iterates over `TerminalKeyboardShortcut.allCases`, and sends each shortcut with:

```swift
Task { @MainActor in
    await store.sendTerminalKeyboardShortcut(shortcut)
}
```

- [ ] **Step 2: Run UI-adjacent store tests**

Run:

```bash
xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/MobileShellStoreTests
```

Expected: PASS.

### Task 3: Full Verification

**Files:**
- Verify: entire project

- [ ] **Step 1: Run full tests**

```bash
xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'
```

Expected: PASS.

- [ ] **Step 2: Run app build**

```bash
xcodebuild build -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'
```

Expected: exit 0.

---

## Self-Review

Spec coverage: The plan turns the existing inert extra keyboard row into usable terminal shortcuts for active SSH shells and safe draft insertion for non-live sessions.

Placeholder scan: No placeholders or deferred requirements remain.

Type consistency: `TerminalKeyboardShortcut` and `sendTerminalKeyboardShortcut(_:)` are introduced before UI usage and test references.
