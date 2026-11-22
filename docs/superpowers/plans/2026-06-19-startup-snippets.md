# Startup Snippets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add personal startup snippets that automatically run a saved snippet when a new host terminal session opens.

**Architecture:** Store the startup snippet reference on `ShellHost`, reuse existing snippet and terminal command execution paths, and expose host-level automation controls in the existing add/edit host sheets.

**Tech Stack:** Swift 6, SwiftUI Observation, XCTest, JSON persistence.

---

### Task 1: Startup Snippet Behavior Tests

**Files:**
- Create: `MobileShellTests/Features/Snippets/StartupSnippetTests.swift`
- Modify: `MobileShell.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write failing tests**

Add tests for host persistence, add/edit APIs, automatic execution on new sessions, no duplicate execution when selecting an existing session, and cleanup when deleting snippets.

- [ ] **Step 2: Run and verify RED**

Run: `xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/StartupSnippetTests`

Expected: FAIL because `startupSnippetID` and related Store behavior do not exist yet.

### Task 2: Host Model And Store Startup Behavior

**Files:**
- Modify: `MobileShell/Models.swift`

- [ ] **Step 1: Add `ShellHost.startupSnippetID` with legacy-safe decoding**
- [ ] **Step 2: Extend host creation/update helpers and public APIs with `startupSnippetID`**
- [ ] **Step 3: Run startup snippets once when a new session opens**
- [ ] **Step 4: Detach deleted snippets from hosts**
- [ ] **Step 5: Run targeted tests and verify GREEN**

### Task 3: Host Automation UI

**Files:**
- Modify: `MobileShell/ShellRootView.swift`

- [ ] **Step 1: Add startup snippet pickers to add/edit host sheets**
- [ ] **Step 2: Show host-row startup snippet metadata**
- [ ] **Step 3: Run targeted tests, full tests, and app build**
