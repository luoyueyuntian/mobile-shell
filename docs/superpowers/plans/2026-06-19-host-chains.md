# Host Chains Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Termius-style personal jump host / host chain metadata so saved hosts and groups can express bastion routing without team features.

**Architecture:** Extend `ShellHost` and `HostGroupProfile` with optional `jumpHostID`. `SSHConnectionRequestBuilder` receives all hosts and resolves a nested `jumpChain` on every request, with host-level jump host overriding group-level jump host. SwiftUI exposes jump host pickers in Host and Group editors and displays simple “Via …” summaries.

**Tech Stack:** Swift, SwiftUI, XCTest, JSON persistence.

---

### Task 1: Request-Level Jump Chain Resolution

**Files:**
- Modify: `MobileShell/ShellConnection.swift`
- Modify: `MobileShell/Models.swift`
- Modify: `MobileShell/Features/HostGroups/HostGroupProfile.swift`
- Modify: `MobileShell/Persistence.swift`
- Create: `MobileShellTests/Features/HostChains/HostChainTests.swift`
- Modify: `MobileShell.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write failing tests**

Add tests for host-level jump host, group-level inherited jump host, host override priority, and persistence:

```swift
import XCTest
@testable import MobileShell

final class HostChainTests: XCTestCase {
    func testConnectionRequestIncludesHostJumpHostRequest() throws {
        let targetID = UUID(uuidString: "61616161-1111-2222-3333-616161616161")!
        let jumpID = UUID(uuidString: "62626262-1111-2222-3333-626262626262")!
        let target = ShellHost(id: targetID, name: "private-api", address: "10.0.0.12", username: "app", group: "Production", tags: ["ssh"], status: .idle, jumpHostID: jumpID)
        let jump = ShellHost(id: jumpID, name: "bastion", address: "bastion.example.com", username: "deploy", group: "Production", tags: ["ssh"], status: .idle)
        let vault = InMemoryCredentialVault()
        try vault.savePassword("target-secret", forHostID: targetID)
        try vault.savePassword("jump-secret", forHostID: jumpID)

        let request = try SSHConnectionRequestBuilder(
            credentialVault: vault,
            hosts: [target, jump]
        ).request(for: target)

        XCTAssertEqual(request.hostname, "10.0.0.12")
        XCTAssertEqual(request.jumpChain.map(\.hostname), ["bastion.example.com"])
        XCTAssertEqual(request.jumpChain.first?.username, "deploy")
        XCTAssertEqual(request.jumpChain.first?.password, "jump-secret")
    }

    func testConnectionRequestInheritsGroupJumpHostWhenHostHasNone() throws {
        let target = ShellHost(id: UUID(uuidString: "63636363-1111-2222-3333-636363636363")!, name: "db", address: "10.0.0.20", username: "postgres", group: "Databases", tags: ["ssh"], status: .idle)
        let groupJumpID = UUID(uuidString: "64646464-1111-2222-3333-646464646464")!
        let jump = ShellHost(id: groupJumpID, name: "db-bastion", address: "db-bastion.example.com", username: "deploy", group: "Production", tags: ["ssh"], status: .idle)

        let request = try SSHConnectionRequestBuilder(
            hosts: [target, jump],
            hostGroupProfiles: [HostGroupProfile(name: "Databases", identityID: nil, jumpHostID: groupJumpID)]
        ).request(for: target)

        XCTAssertEqual(request.jumpChain.map(\.displayName), ["db-bastion"])
    }

    func testHostJumpHostOverridesGroupJumpHost() throws {
        let hostJumpID = UUID(uuidString: "65656565-1111-2222-3333-656565656565")!
        let groupJumpID = UUID(uuidString: "66666666-1111-2222-3333-666666666666")!
        let target = ShellHost(id: UUID(uuidString: "67676767-1111-2222-3333-676767676767")!, name: "api", address: "10.0.0.30", username: "deploy", group: "Production", tags: ["ssh"], status: .idle, jumpHostID: hostJumpID)
        let hostJump = ShellHost(id: hostJumpID, name: "host-bastion", address: "host-bastion.example.com", username: "deploy", group: "Production", tags: ["ssh"], status: .idle)
        let groupJump = ShellHost(id: groupJumpID, name: "group-bastion", address: "group-bastion.example.com", username: "deploy", group: "Production", tags: ["ssh"], status: .idle)

        let request = try SSHConnectionRequestBuilder(
            hosts: [target, hostJump, groupJump],
            hostGroupProfiles: [HostGroupProfile(name: "Production", identityID: nil, jumpHostID: groupJumpID)]
        ).request(for: target)

        XCTAssertEqual(request.jumpChain.map(\.displayName), ["host-bastion"])
    }

    func testStorePersistsHostAndGroupJumpHostReferences() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repository = JSONHostRepository(fileURL: tempDirectory.appendingPathComponent("hosts.json"))
        let jumpID = UUID(uuidString: "68686868-1111-2222-3333-686868686868")!
        let host = ShellHost(id: UUID(uuidString: "69696969-1111-2222-3333-696969696969")!, name: "api", address: "api.internal", username: "deploy", group: "Production", tags: ["ssh"], status: .idle, jumpHostID: jumpID)
        let snapshot = HostPersistenceSnapshot(
            hosts: [host],
            hostGroupProfiles: [HostGroupProfile(name: "Production", identityID: nil, jumpHostID: jumpID)]
        )

        try repository.save(snapshot)
        let reloaded = try repository.load()

        XCTAssertEqual(reloaded.hosts.first?.jumpHostID, jumpID)
        XCTAssertEqual(reloaded.hostGroupProfiles.first?.jumpHostID, jumpID)
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/HostChainTests
```

Expected: FAIL because jump host properties and request chain support do not exist.

- [ ] **Step 3: Implement model, persistence, and request chain**

Add `jumpHostID` to `ShellHost` and `HostGroupProfile`, with `ShellHost` custom decoding using `decodeIfPresent`. Add `jumpChain: [SSHConnectionRequest] = []` to `SSHConnectionRequest`. Add `hosts: [ShellHost] = []` to `SSHConnectionRequestBuilder`, resolve host jump first, then group jump, and recursively build nested jump requests while ignoring cycles.

- [ ] **Step 4: Re-run targeted tests**

Run the same command. Expected: PASS.

### Task 2: Store Threading and UI

**Files:**
- Modify: `MobileShell/Models.swift`
- Modify: `MobileShell/ShellRootView.swift`
- Modify: `MobileShellTests/Features/HostChains/HostChainTests.swift`

- [ ] **Step 1: Add store-level route summary tests**

Add a test proving `MobileShellStore.routeSummary(for:)` describes direct and inherited jump routes.

- [ ] **Step 2: Implement store helper and thread builder hosts**

Thread `hosts: hosts` into every store-created `SSHConnectionRequestBuilder`. Add `routeSummary(for:) -> String?` that returns `"Via <host name>"` for the resolved jump host or `"Missing jump host"` when the configured ID is stale.

- [ ] **Step 3: Add UI pickers**

Add optional jump host pickers to `AddHostSheet`, `EditHostSheet`, and `HostGroupEditorSheet`. Show route summaries in `HostRow` and `GroupCard`.

- [ ] **Step 4: Run focused tests**

```bash
xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/HostChainTests
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

Spec coverage: The plan covers host-level and group-level jump host metadata, request resolution, override priority, persistence, UI entry points, and verification.

Placeholder scan: No placeholders or deferred implementation steps remain.

Type consistency: `jumpHostID`, `jumpChain`, `hosts`, and `routeSummary(for:)` are defined before use.

Git note: This workspace is not a git repository, so do not commit. Report changed files and verification results instead.
