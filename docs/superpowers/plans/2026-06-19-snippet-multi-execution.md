# Snippet Multi-Execution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add personal snippet multi-execution across the currently visible terminal set.

**Architecture:** Reuse `visibleTerminalSessions()` for target selection and `sendRemoteCommand(_:in:recordHistory:clearDraft:)` for execution so snippet multi-exec matches existing terminal behavior.

**Tech Stack:** Swift 6, SwiftUI Observation, XCTest.

---

### Task 1: Multi-Execution Behavior Tests

**Files:**
- Create: `MobileShellTests/Features/Snippets/SnippetMultiExecutionTests.swift`
- Modify: `MobileShell.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write failing tests**

Add tests for all-terminal targeting, selected-workspace targeting, empty target handling, and stale snippet handling.

- [ ] **Step 2: Run and verify RED**

Run: `xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/SnippetMultiExecutionTests`

Expected: FAIL because `runSnippetInVisibleTerminals(_:)` does not exist yet.

### Task 2: Store Multi-Execution

**Files:**
- Modify: `MobileShell/Models.swift`

- [ ] **Step 1: Add `runSnippetInVisibleTerminals(_:)`**
- [ ] **Step 2: Reuse `sendRemoteCommand` with `recordHistory: false` and `clearDraft: false`**
- [ ] **Step 3: Insert a single summary history entry and return the target count**
- [ ] **Step 4: Run targeted tests and verify GREEN**

### Task 3: Snippets UI Action

**Files:**
- Modify: `MobileShell/ShellRootView.swift`

- [ ] **Step 1: Add a Snippet row menu action for visible-terminal execution**
- [ ] **Step 2: Disable the action when no terminal sessions are visible**
- [ ] **Step 3: Run targeted tests, full tests, and app build**
