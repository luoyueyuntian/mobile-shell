# Port Forwarding Types Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add typed local/remote/dynamic port forwarding rules, preserve legacy local behavior, and implement live remote forwarding.

**Architecture:** Add `PortForwardKind` and `localHost` to `PortForwardRule` with legacy-safe decoding. Store APIs accept the new fields with defaults; the live port forwarding client dispatches local to the existing direct-tcpip listener, remote to Citadel remote forwarding, and dynamic to an explicit unsupported error.

**Tech Stack:** Swift 6, SwiftUI Observation, XCTest, Citadel, NIO.

---

### Task 1: Typed Rule Model Tests

**Files:**
- Create: `MobileShellTests/Features/PortForwarding/PortForwardingTypeTests.swift`
- Modify: `MobileShell.xcodeproj/project.pbxproj`

- [x] **Step 1: Write failing tests**

Create tests for legacy decoding, local rule defaults, remote rule storage, and dynamic unsupported behavior.

- [x] **Step 2: Run RED**

Run:

```bash
xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/PortForwardingTypeTests
```

Expected: fail because `PortForwardKind`, `localHost`, and typed store APIs do not exist yet.

- [x] **Step 3: Implement model and store APIs**

Add `PortForwardKind`, custom Codable for `PortForwardRule`, `localHost`, typed add/update APIs, dynamic start guard, and summary helpers.

- [x] **Step 4: Run GREEN**

Run the targeted test command. Expected: typed model tests pass.

### Task 2: Live Remote Forwarding

**Files:**
- Modify: `MobileShell/ShellConnection.swift`
- Modify: `MobileShellTests/Features/PortForwarding/PortForwardingTypeTests.swift`

- [x] **Step 1: Add focused backend tests where possible**

Use the injected `RecordingPortForwardingClient` for store-level remote start behavior and keep Citadel-specific behavior covered by build/type checks.

- [x] **Step 2: Implement live dispatch**

Split `CitadelPortForwardingSession.start` into local and remote helpers. Use `client.runRemotePortForward(host: rule.remoteHost, port: rule.remotePort, forwardingTo: rule.localHost, port: rule.localPort)` for remote rules and surface unsupported dynamic rules through `PortForwardingError.unsupportedKind`.

- [x] **Step 3: Run targeted tests**

Run the targeted port forwarding type tests.

### Task 3: Port Forwarding UI

**Files:**
- Modify: `MobileShell/ShellRootView.swift`

- [x] **Step 1: Add type picker and adaptive labels**

Update `PortForwardRuleEditorSheet` with `kind` and `localHost` state, type picker, adaptive field labels, and save calls.

- [x] **Step 2: Add row badges and summaries**

Update `PortForwardRuleRow` to show kind title and route summary.

- [x] **Step 3: Build**

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
xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/PortForwardingTypeTests
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
