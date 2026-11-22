# Snippet Packages Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Organize personal command snippets into Termius-style packages while preserving existing snippets and startup snippet behavior.

**Architecture:** Add a defaulted `packageName` to `ShellSnippet`, derive package sections in `MobileShellStore`, and keep package organization lightweight without introducing package CRUD. Autocomplete and SwiftUI list rendering consume the same model field so package labels stay consistent.

**Tech Stack:** Swift 6, SwiftUI Observation, XCTest, Codable persistence.

---

### Task 1: Snippet Package Tests

**Files:**
- Create: `MobileShellTests/Features/Snippets/SnippetPackageTests.swift`
- Modify: `MobileShell.xcodeproj/project.pbxproj`

- [x] **Step 1: Write failing package tests**

Add tests for:

```swift
func testLegacySnippetDecodesIntoPersonalPackage() throws
func testAddingSnippetStoresTrimmedPackageNameAndDefaultsBlankPackage() throws
func testUpdatingSnippetKeepsIDAndMovesPackage() throws
func testSnippetPackagesGroupAndSortCaseInsensitively() throws
func testAutocompleteSnippetDetailIncludesPackageName() throws
```

- [x] **Step 2: Run RED**

Run:

```bash
xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/SnippetPackageTests
```

Expected: fail because `packageName`, `SnippetPackageSection`, and package-aware APIs do not exist yet.

### Task 2: Model And Store

**Files:**
- Modify: `MobileShell/Models.swift`
- Modify: `MobileShell/Features/Autocomplete/CommandAutocompleteEngine.swift`

- [x] **Step 1: Add package model support**

Add `packageName` to `ShellSnippet` with default `Personal` and legacy-safe Codable decoding.

- [x] **Step 2: Add package-aware store APIs**

Update `addSnippet`, `updateSnippet`, and `makeSnippet` to accept `packageName` and normalize blank package names to `Personal`.

- [x] **Step 3: Add derived package sections**

Add `SnippetPackageSection` and `snippetPackages()` to group snippets by package name and sort sections/snippets case-insensitively.

- [x] **Step 4: Include package in autocomplete detail**

Set snippet suggestion detail to `"<package> package"`.

- [x] **Step 5: Run targeted tests**

Run:

```bash
xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/SnippetPackageTests
```

Expected: snippet package tests pass.

### Task 3: Snippets UI

**Files:**
- Modify: `MobileShell/ShellRootView.swift`

- [x] **Step 1: Render package sections**

Replace the flat `ForEach(store.snippets)` in `SnippetsView` with `ForEach(store.snippetPackages())`, package headers, and rows per package.

- [x] **Step 2: Show package badges**

Update `SnippetRow` to show `snippet.packageName` in a compact badge.

- [x] **Step 3: Add package editor field**

Add `@State private var packageName`, initialize it from the snippet, and pass it to add/update calls.

- [x] **Step 4: Build**

Run:

```bash
xcodebuild build -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'
```

Expected: build succeeds.

### Task 4: Verification

**Files:**
- Verify all modified files.

- [x] **Step 1: Run targeted tests**

```bash
xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/SnippetPackageTests
```

- [x] **Step 2: Run full tests**

```bash
xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'
```

- [x] **Step 3: Run app build**

```bash
xcodebuild build -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'
```

- [x] **Step 4: Confirm plan status**

Search this plan for unchecked implementation boxes and update completed steps.
