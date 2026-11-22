# Group Startup Snippets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add inherited group startup snippets for personal Termius-style group defaults.

**Architecture:** Extend `HostGroupProfile`, reuse the existing `hostGroupProfile(for:)` inheritance lookup, and add group editor UI for assigning startup snippets.

**Tech Stack:** Swift 6, SwiftUI Observation, XCTest, JSON persistence.

---

### Task 1: Group Startup Snippet Tests

**Files:**
- Create: `MobileShellTests/Features/HostGroups/HostGroupStartupSnippetTests.swift`
- Modify: `MobileShell.xcodeproj/project.pbxproj`

- [x] **Step 1: Write failing tests**

Add tests for profile storage, inherited startup lookup, host override, inherited startup execution, and delete cleanup.

- [x] **Step 2: Run and verify RED**

Run: `xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/HostGroupStartupSnippetTests`

Expected: FAIL because `HostGroupProfile.startupSnippetID` and inherited startup lookup do not exist yet.

### Task 2: Model And Store Inheritance

**Files:**
- Modify: `MobileShell/Features/HostGroups/HostGroupProfile.swift`
- Modify: `MobileShell/Models.swift`

- [x] **Step 1: Add `startupSnippetID` to `HostGroupProfile`**
- [x] **Step 2: Add `startupSnippetID` to `upsertHostGroupProfile`**
- [x] **Step 3: Resolve startup snippets through host override then group fallback**
- [x] **Step 4: Detach deleted snippets from group profiles**
- [x] **Step 5: Run targeted tests and verify GREEN**

### Task 3: Group Editor UI

**Files:**
- Modify: `MobileShell/ShellRootView.swift`

- [x] **Step 1: Add group startup snippet summary to group cards**
- [x] **Step 2: Add Automation picker to `HostGroupEditorSheet`**
- [x] **Step 3: Run targeted tests, full tests, and app build**
