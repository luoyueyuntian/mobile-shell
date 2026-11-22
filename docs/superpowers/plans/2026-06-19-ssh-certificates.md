# SSH Certificates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add personal Termius-style SSH certificate metadata, local vault storage, key links, request propagation, and Keychain UI.

**Architecture:** Certificates are metadata in `HostPersistenceSnapshot` and material in `CredentialVault`, mirroring SSH private keys. Each `SSHKey` can point at one active `SSHCertificate`, so hosts and identities continue selecting keys while requests automatically include linked certificate material.

**Tech Stack:** Swift, SwiftUI, XCTest, iOS Keychain via Security, existing Citadel request abstraction.

---

### Task 1: Certificate Store Tests

**Files:**
- Create: `MobileShellTests/Features/Keychain/SSHCertificateTests.swift`
- Modify: `MobileShell.xcodeproj/project.pbxproj`

- [x] **Step 1: Write failing tests for certificate storage and linking**

```swift
import XCTest
@testable import MobileShell

final class SSHCertificateTests: XCTestCase {
    func testAddingSSHCertificateStoresMetadataAndMaterialSeparately() throws {
        let vault = InMemoryCredentialVault()
        let keyID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-000000000001")!
        let key = SSHKey(id: keyID, name: "Device Key", fingerprint: "SHA256:key", kind: "ed25519")
        let store = MobileShellStore(keys: [key], credentialVault: vault)

        let certificate = try XCTUnwrap(try store.addSSHCertificate(
            name: "  Prod User Cert  ",
            kind: " user-cert ",
            certificate: "  ssh-ed25519-cert-v01@openssh.com AAAATEST prod  ",
            sshKeyID: keyID
        ))

        XCTAssertEqual(certificate.name, "Prod User Cert")
        XCTAssertEqual(certificate.kind, "user-cert")
        XCTAssertTrue(certificate.fingerprint.hasPrefix("SHA256:"))
        XCTAssertEqual(store.certificates, [certificate])
        XCTAssertEqual(store.keys.first?.certificateID, certificate.id)
        XCTAssertEqual(try vault.certificate(forCertificateID: certificate.id), "ssh-ed25519-cert-v01@openssh.com AAAATEST prod")
    }
}
```

- [x] **Step 2: Run RED**

Run:

```bash
xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/SSHCertificateTests
```

Expected: fail to compile because `SSHCertificate`, `certificates`, and certificate vault APIs do not exist yet.

- [x] **Step 3: Implement the minimal model/vault/store APIs**

Add `SSHCertificate`, `SSHKey.certificateID`, `MobileShellStore.certificates`, snapshot persistence, and `CredentialVault` certificate methods. Add `addSSHCertificate`, `updateSSHCertificate`, `deleteSSHCertificate`, `storedCertificate`, and key-link helpers.

- [x] **Step 4: Run GREEN for Task 1**

Run the same targeted test command. Expected: `SSHCertificateTests` pass.

### Task 2: Connection Request Tests

**Files:**
- Modify: `MobileShellTests/Features/Keychain/SSHCertificateTests.swift`
- Modify: `MobileShell/ShellConnection.swift`
- Modify: `MobileShell/Models.swift`

- [x] **Step 1: Add failing request-builder tests**

Add tests proving a host key and an identity key include linked certificate material in `SSHConnectionRequest.certificate`.

- [x] **Step 2: Run RED**

Run the targeted test command. Expected: fail because `SSHConnectionRequest` does not expose certificate material and the builder does not resolve linked certificates.

- [x] **Step 3: Implement request propagation**

Add `certificate: String? = nil` to `SSHConnectionRequest`, `keys` and `certificates` to `SSHConnectionRequestBuilder`, and pass store keys/certificates wherever requests are built.

- [x] **Step 4: Run GREEN**

Run the targeted test command. Expected: request-builder certificate tests pass.

### Task 3: Summary And Persistence Tests

**Files:**
- Modify: `MobileShellTests/Features/Keychain/SSHCertificateTests.swift`
- Modify: `MobileShell/Models.swift`
- Modify: `MobileShell/Persistence.swift`

- [x] **Step 1: Add failing tests for summaries, deletion, update, and JSON safety**

Add tests for certificate text in host and identity summaries, deleting a certificate clearing key links and vault material, updating material rotating fingerprint, and repository JSON excluding certificate material.

- [x] **Step 2: Run RED**

Run the targeted test command. Expected: fail where summary/deletion/update/persistence behavior is incomplete.

- [x] **Step 3: Implement summary and cleanup behavior**

Add certificate-aware summary formatting, delete cleanup, update rotation, and snapshot certificate migration with `decodeIfPresent`.

- [x] **Step 4: Run GREEN**

Run the targeted test command. Expected: all `SSHCertificateTests` pass.

### Task 4: Keychain UI

**Files:**
- Modify: `MobileShell/ShellRootView.swift`

- [x] **Step 1: Add certificate section and editor**

Add Keychain state for editing/deleting certificates, a "SSH Certificates" section, `SSHCertificateRow`, and `SSHCertificateEditorSheet`.

- [x] **Step 2: Surface certificate context in key/identity rows**

Pass linked certificate metadata into `SSHKeyRow` and `SSHIdentityRow` and append `+ cert: <name>` when present.

- [x] **Step 3: Build**

Run:

```bash
xcodebuild build -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'
```

Expected: build succeeds.

### Task 5: Verification

**Files:**
- Verify all modified files.

- [x] **Step 1: Run targeted certificate tests**

```bash
xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/SSHCertificateTests
```

- [x] **Step 2: Run full test suite**

```bash
xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'
```

- [x] **Step 3: Run app build**

```bash
xcodebuild build -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'
```

- [x] **Step 4: Confirm plan status**

Search this plan for unchecked boxes and update completed steps.
