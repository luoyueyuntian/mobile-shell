# Workspace Command Broadcast Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Termius-style command broadcasting for personal terminal workspaces.

**Architecture:** Reuse the existing workspace membership model, add a Store broadcast API that shares command execution logic with single-session commands, and expose a broadcast toggle/button in the terminal UI.

**Tech Stack:** Swift 6, SwiftUI Observation, XCTest.

---

### Task 1: Broadcast Behavior Tests

**Files:**
- Modify: `MobileShellTests/Features/Workspaces/TerminalWorkspaceTests.swift`

- [ ] **Step 1: Write failing tests**

Add tests for `broadcastCommand(_:)`, `setBroadcastEnabled(_:for:)`, and blank input behavior.

- [ ] **Step 2: Run and verify RED**

Run: `xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/TerminalWorkspaceTests`

Expected: FAIL because broadcast Store APIs do not exist yet.

### Task 2: Store Broadcast Execution

**Files:**
- Modify: `MobileShell/Models.swift`

- [ ] **Step 1: Add `setBroadcastEnabled(_:for:)`**
- [ ] **Step 2: Add `broadcastCommand(_:)`**
- [ ] **Step 3: Extract a private targeted command helper shared by single and broadcast execution**
- [ ] **Step 4: Run targeted tests and verify GREEN**

### Task 3: UI Broadcast Controls

**Files:**
- Modify: `MobileShell/Features/Workspaces/TerminalWorkspaceSwitcher.swift`
- Modify: `MobileShell/ShellRootView.swift`

- [ ] **Step 1: Show a broadcast toggle for selected workspaces**
- [ ] **Step 2: Add a broadcast button beside the command submit button when broadcast is enabled**
- [ ] **Step 3: Run full tests and app build**
