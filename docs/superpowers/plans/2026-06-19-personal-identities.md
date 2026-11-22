# Personal Identities Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Termius-style personal identities so hosts can reuse saved usernames, passwords, and SSH keys without team features.

**Architecture:** Introduce `SSHIdentity` as a persisted metadata object and store identity passwords in `CredentialVault`, not JSON. `ShellHost` gets an optional `identityID`; `SSHConnectionRequestBuilder` resolves identity credentials first and falls back to host-local credentials when no identity is attached. SwiftUI exposes identity CRUD in Keychain and lets host add/edit forms choose an identity.

**Tech Stack:** Swift, SwiftUI, XCTest, JSON persistence, iOS Keychain.

---

### Task 1: Identity Model, Persistence, and Credential Vault

**Files:**
- Modify: `MobileShell/Models.swift`
- Modify: `MobileShell/Persistence.swift`
- Modify: `MobileShellTests/MobileShellStoreTests.swift`
- Modify: `MobileShellTests/MobileShellPersistenceTests.swift`

- [ ] **Step 1: Write failing tests**

Add tests for identity CRUD, password isolation, persistence, and deleting identities detaching linked hosts.

- [ ] **Step 2: Run targeted tests and confirm failure**

Run:

```bash
xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/MobileShellStoreTests/testAddingIdentityStoresMetadataAndPasswordSeparately -only-testing:MobileShellTests/MobileShellStoreTests/testDeletingIdentityRemovesPasswordAndDetachesHosts -only-testing:MobileShellTests/MobileShellPersistenceTests/testStorePersistsIdentityMetadataWithoutPassword
```

Expected: FAIL because identity types and APIs do not exist.

- [ ] **Step 3: Implement minimal model and persistence**

Add `SSHIdentity`, `ShellHost.identityID`, `HostPersistenceSnapshot.identities`, credential vault identity password APIs, store identity CRUD, and persistence snapshot wiring.

- [ ] **Step 4: Re-run targeted tests**

Expected: PASS.

### Task 2: Use Identities for SSH Connection Requests

**Files:**
- Modify: `MobileShell/ShellConnection.swift`
- Modify: `MobileShell/Models.swift`
- Modify: `MobileShellTests/MobileShellStoreTests.swift`

- [ ] **Step 1: Write failing request-resolution tests**

Add tests proving a host linked to an identity uses the identity username, identity password, and identity SSH key.

- [ ] **Step 2: Run targeted tests and confirm failure**

Run:

```bash
xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/MobileShellStoreTests/testSSHConnectionRequestUsesLinkedIdentityCredentials -only-testing:MobileShellTests/MobileShellStoreTests/testAuthenticationSummaryDescribesIdentityCredentialStates
```

Expected: FAIL until builder and summaries understand identities.

- [ ] **Step 3: Implement request and summary resolution**

Thread identities into `SSHConnectionRequestBuilder`, cache/live request construction, and `authenticationSummary(for:)`.

- [ ] **Step 4: Re-run targeted tests**

Expected: PASS.

### Task 3: Basic Identity UI

**Files:**
- Modify: `MobileShell/ShellRootView.swift`

- [ ] **Step 1: Add Keychain identity list and editor**

Extend `KeychainView` with an Identities section and `SSHIdentityEditorSheet`.

- [ ] **Step 2: Add host identity picker**

Add optional identity picker to Add/Edit Host sheets and pass `identityID` into store host APIs.

- [ ] **Step 3: Run store tests**

```bash
xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/MobileShellStoreTests
```

Expected: PASS.

### Task 4: Full Verification

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

Spec coverage: The plan covers identity metadata, password isolation, host linkage, connection request resolution, authentication summaries, UI entry points, and verification.

Placeholder scan: No placeholder implementation steps remain.

Type consistency: `SSHIdentity`, `identityID`, and credential vault identity APIs are introduced before usage.
