# Host Group Identities Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Termius-style personal host group identity inheritance so hosts can reuse credentials from their group without team or shared vault features.

**Architecture:** Introduce `HostGroupProfile` as persisted metadata keyed by group name. `ShellHost.identityID` remains the strongest override; if a host has no identity, `SSHConnectionRequestBuilder` and authentication summaries resolve the host's group identity before falling back to host-local credentials. SwiftUI adds a compact group editor from the existing Hosts screen.

**Tech Stack:** Swift, SwiftUI, XCTest, JSON persistence, iOS Keychain.

---

### Task 1: Group Profile Model and Persistence

**Files:**
- Create: `MobileShell/Features/HostGroups/HostGroupProfile.swift`
- Modify: `MobileShell/Persistence.swift`
- Modify: `MobileShell/Models.swift`
- Modify: `MobileShell.xcodeproj/project.pbxproj`
- Create: `MobileShellTests/Features/HostGroups/HostGroupIdentityTests.swift`

- [ ] **Step 1: Write the failing tests**

Add tests proving group profile metadata is persisted and can be updated through `MobileShellStore`:

```swift
import XCTest
@testable import MobileShell

final class HostGroupIdentityTests: XCTestCase {
    func testAddingHostGroupProfileTrimsNameAndStoresIdentityReference() throws {
        let identityID = UUID(uuidString: "51515151-1111-2222-3333-515151515151")!
        let store = MobileShellStore()

        let group = try XCTUnwrap(store.upsertHostGroupProfile(name: " Production ", identityID: identityID))

        XCTAssertEqual(group.name, "Production")
        XCTAssertEqual(group.identityID, identityID)
        XCTAssertEqual(store.hostGroupProfiles, [group])
        XCTAssertEqual(store.history.first, "Updated group Production")
    }

    func testStorePersistsHostGroupProfiles() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repository = JSONHostRepository(fileURL: tempDirectory.appendingPathComponent("hosts.json"))
        let identityID = UUID(uuidString: "52525252-1111-2222-3333-525252525252")!
        let store = MobileShellStore(repository: repository, credentialVault: InMemoryCredentialVault())

        _ = try XCTUnwrap(store.upsertHostGroupProfile(name: "Production", identityID: identityID))

        let reloaded = try MobileShellStore(repository: repository, credentialVault: InMemoryCredentialVault())
        XCTAssertEqual(reloaded.hostGroupProfiles, [
            HostGroupProfile(name: "Production", identityID: identityID)
        ])
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/HostGroupIdentityTests/testAddingHostGroupProfileTrimsNameAndStoresIdentityReference -only-testing:MobileShellTests/HostGroupIdentityTests/testStorePersistsHostGroupProfiles
```

Expected: FAIL because `HostGroupProfile`, `hostGroupProfiles`, and `upsertHostGroupProfile` do not exist.

- [ ] **Step 3: Implement minimal model and persistence**

Create `HostGroupProfile`:

```swift
import Foundation

struct HostGroupProfile: Identifiable, Equatable, Codable {
    var name: String
    var identityID: SSHIdentity.ID?

    var id: String { name }
}
```

Add `hostGroupProfiles: [HostGroupProfile]` to `HostPersistenceSnapshot`, decode it with `decodeIfPresent(... ) ?? []`, pass it through store initializers, and persist it in `persistSnapshot()`.

Add store methods:

```swift
@discardableResult
func upsertHostGroupProfile(name: String, identityID: SSHIdentity.ID?) -> HostGroupProfile? {
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else { return nil }

    let profile = HostGroupProfile(name: trimmedName, identityID: identityID)
    if let index = hostGroupProfiles.firstIndex(where: { $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame }) {
        hostGroupProfiles[index] = profile
    } else {
        hostGroupProfiles.append(profile)
        hostGroupProfiles.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    history.insert("Updated group \(profile.name)", at: 0)
    try? persistSnapshot()
    return profile
}
```

- [ ] **Step 4: Run tests to verify pass**

Run the same targeted command. Expected: PASS.

### Task 2: Connection Request and Summary Inheritance

**Files:**
- Modify: `MobileShell/ShellConnection.swift`
- Modify: `MobileShell/Models.swift`
- Modify: `MobileShellTests/Features/HostGroups/HostGroupIdentityTests.swift`

- [ ] **Step 1: Write the failing resolution tests**

Add tests proving host identity wins over group identity, and group identity is used when the host has none:

```swift
func testConnectionRequestUsesGroupIdentityWhenHostHasNoIdentity() throws {
    let hostID = UUID(uuidString: "53535353-1111-2222-3333-535353535353")!
    let identityID = UUID(uuidString: "54545454-1111-2222-3333-545454545454")!
    let keyID = UUID(uuidString: "55555555-1111-2222-3333-555555555555")!
    let host = ShellHost(
        id: hostID,
        name: "group-host",
        address: "group.example.com",
        username: "host-user",
        group: "Production",
        tags: ["ssh"],
        status: .idle
    )
    let identity = SSHIdentity(id: identityID, name: "Production Deploy", username: "deploy", sshKeyID: keyID)
    let credentialVault = InMemoryCredentialVault()
    try credentialVault.savePassword("group-secret", forIdentityID: identityID)
    try credentialVault.savePrivateKey("group-private-key", forKeyID: keyID)

    let request = try SSHConnectionRequestBuilder(
        credentialVault: credentialVault,
        identities: [identity],
        hostGroupProfiles: [HostGroupProfile(name: "Production", identityID: identityID)]
    ).request(for: host)

    XCTAssertEqual(request.username, "deploy")
    XCTAssertEqual(request.password, "group-secret")
    XCTAssertEqual(request.privateKey, "group-private-key")
}

func testHostIdentityOverridesGroupIdentity() throws {
    let hostIdentityID = UUID(uuidString: "56565656-1111-2222-3333-565656565656")!
    let groupIdentityID = UUID(uuidString: "57575757-1111-2222-3333-575757575757")!
    let host = ShellHost(
        id: UUID(uuidString: "58585858-1111-2222-3333-585858585858")!,
        name: "override-host",
        address: "override.example.com",
        username: "host-user",
        group: "Production",
        tags: ["ssh"],
        status: .idle,
        identityID: hostIdentityID
    )
    let hostIdentity = SSHIdentity(id: hostIdentityID, name: "Host Identity", username: "host-identity", sshKeyID: nil)
    let groupIdentity = SSHIdentity(id: groupIdentityID, name: "Group Identity", username: "group-identity", sshKeyID: nil)

    let request = try SSHConnectionRequestBuilder(
        identities: [hostIdentity, groupIdentity],
        hostGroupProfiles: [HostGroupProfile(name: "Production", identityID: groupIdentityID)]
    ).request(for: host)

    XCTAssertEqual(request.username, "host-identity")
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/HostGroupIdentityTests/testConnectionRequestUsesGroupIdentityWhenHostHasNoIdentity -only-testing:MobileShellTests/HostGroupIdentityTests/testHostIdentityOverridesGroupIdentity
```

Expected: FAIL because `SSHConnectionRequestBuilder` does not accept group profiles.

- [ ] **Step 3: Implement request and summary inheritance**

Add `var hostGroupProfiles: [HostGroupProfile] = []` to `SSHConnectionRequestBuilder`. Resolve identity with this priority:

```swift
private func identity(for host: ShellHost) -> SSHIdentity? {
    if let identityID = host.identityID {
        return identities.first { $0.id == identityID }
    }
    guard let groupIdentityID = hostGroupProfiles.first(where: {
        $0.name.caseInsensitiveCompare(host.group) == .orderedSame
    })?.identityID else {
        return nil
    }
    return identities.first { $0.id == groupIdentityID }
}
```

Thread `hostGroupProfiles` through every `SSHConnectionRequestBuilder` call inside `MobileShellStore`. Update `authenticationSummary(for:)` so missing host identity still reports `"Missing identity"`, while inherited group identity reports `"Group Identity: <name> (...)"`.

- [ ] **Step 4: Run tests to verify pass**

Run the same targeted command. Expected: PASS.

### Task 3: Basic Group UI

**Files:**
- Modify: `MobileShell/ShellRootView.swift`

- [ ] **Step 1: Add group editor entry point**

In `HostsView`, add `@State private var editingGroupName: String?`. Make each `GroupCard` tappable/editable and show a sheet for `HostGroupEditorSheet`.

- [ ] **Step 2: Add `HostGroupEditorSheet`**

Create a form with group name read-only, an optional identity picker, and a Save button that calls:

```swift
store.upsertHostGroupProfile(name: groupName, identityID: identityID)
```

- [ ] **Step 3: Run store tests**

```bash
xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/HostGroupIdentityTests
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

Spec coverage: The plan covers group metadata, persistence, connection request inheritance, host override priority, authentication summaries, a minimal group editor, and verification.

Placeholder scan: No placeholder implementation steps remain.

Type consistency: `HostGroupProfile`, `hostGroupProfiles`, and `upsertHostGroupProfile` are introduced before later tasks use them.
