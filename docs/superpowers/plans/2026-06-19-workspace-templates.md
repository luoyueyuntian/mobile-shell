# Workspace Templates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add personal workspace templates that save and reopen a Termius-style terminal workspace host set.

**Architecture:** Introduce a small workspace-template model, persist templates in the existing JSON snapshot, coordinate save/open through focused `MobileShellStore` methods, and surface template actions in the workspace switcher.

**Tech Stack:** Swift 6, SwiftUI Observation, XCTest, JSON persistence.

---

### Task 1: Workspace Template Behavior Tests

**Files:**
- Create: `MobileShellTests/Features/Workspaces/TerminalWorkspaceTemplateTests.swift`
- Modify: `MobileShell.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write failing tests**

Add tests for saving selected workspaces, ignoring invalid saves, opening templates, and persistence round-trips.

- [ ] **Step 2: Run and verify RED**

Run: `xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/TerminalWorkspaceTemplateTests`

Expected: FAIL because `TerminalWorkspaceTemplate` and Store template APIs do not exist yet.

### Task 2: Template Model And Persistence

**Files:**
- Create: `MobileShell/Features/Workspaces/TerminalWorkspaceTemplate.swift`
- Modify: `MobileShell/Persistence.swift`
- Modify: `MobileShell.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add `TerminalWorkspaceTemplate`**

Define `id`, `name`, `hostIDs`, and `isBroadcastEnabled`.

- [ ] **Step 2: Persist templates**

Add `terminalWorkspaceTemplates` to `HostPersistenceSnapshot`, initializer, coding keys, and backward-compatible decoding.

### Task 3: Store Template Operations

**Files:**
- Modify: `MobileShell/Models.swift`

- [ ] **Step 1: Add Store state and initializer loading for templates**
- [ ] **Step 2: Implement `saveSelectedWorkspaceAsTemplate(name:)`**
- [ ] **Step 3: Implement `openWorkspaceTemplate(_:)`**
- [ ] **Step 4: Implement `deleteWorkspaceTemplate(_:)` and `templateHostNames(for:)`**
- [ ] **Step 5: Run targeted tests and verify GREEN**

### Task 4: Workspace Switcher UI

**Files:**
- Modify: `MobileShell/Features/Workspaces/TerminalWorkspaceSwitcher.swift`

- [ ] **Step 1: Add a save-template alert for the selected workspace**
- [ ] **Step 2: Add template chips that reopen saved templates**
- [ ] **Step 3: Run targeted tests, full tests, and app build**
