# Mosh Configuration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add personal `Mosh` protocol modeling so hosts can be configured, displayed, and persisted as `Mosh` without yet implementing a real Mosh transport runtime.

**Architecture:** Introduce a thin protocol layer with `RemoteAccessProtocol` and `MoshHostConfiguration`, extend `ShellHost` with backward-compatible decoding, wire Host add/edit/list UI to expose `Mosh` settings, and gate terminal entry so `Mosh` hosts show a clear not-yet-implemented product message instead of falling back to SSH.

**Tech Stack:** Swift 6, SwiftUI, Observation, XCTest, JSON snapshot persistence, existing `ShellHost` / `MobileShellStore` / host feature UI.

---

### Task 1: Protocol Model And Persistence Compatibility

**Files:**
- Create: `MobileShell/Shared/Models/RemoteAccessProtocol.swift`
- Create: `MobileShell/Shared/Models/MoshHostConfiguration.swift`
- Modify: `MobileShell/Models.swift`
- Create: `MobileShellTests/Features/Hosts/MoshHostConfigurationTests.swift`
- Modify: `MobileShell.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write the failing tests**

Create `MobileShellTests/Features/Hosts/MoshHostConfigurationTests.swift`:

```swift
import XCTest
@testable import MobileShell

final class MoshHostConfigurationTests: XCTestCase {
    func testRemoteAccessProtocolRoundTripsThroughCodable() throws {
        let data = try JSONEncoder().encode(RemoteAccessProtocol.mosh)
        let decoded = try JSONDecoder().decode(RemoteAccessProtocol.self, from: data)

        XCTAssertEqual(decoded, .mosh)
    }

    func testMoshHostConfigurationDefaultValuesMatchProductSpec() {
        let configuration = MoshHostConfiguration.default

        XCTAssertEqual(configuration.udpPort, 60001)
        XCTAssertEqual(configuration.serverCommand, "mosh-server new -s")
        XCTAssertTrue(configuration.predictiveEcho)
        XCTAssertFalse(configuration.useExperimentalConnection)
    }

    func testLegacyShellHostDecodesWithoutProtocolFields() throws {
        let data = Data(\"\"\"\n        {\n          \"id\": \"11111111-1111-1111-1111-111111111111\",\n          \"name\": \"api-prod\",\n          \"address\": \"api.example.com\",\n          \"port\": 22,\n          \"username\": \"deploy\",\n          \"group\": \"Production\",\n          \"tags\": [\"ssh\"],\n          \"status\": \"idle\"\n        }\n        \"\"\".utf8)

        let host = try JSONDecoder().decode(ShellHost.self, from: data)

        XCTAssertEqual(host.protocol, .ssh)
        XCTAssertNil(host.moshConfiguration)
    }

    func testShellHostWithMoshConfigurationRoundTripsThroughJSON() throws {
        let host = ShellHost(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            name: "lab-mosh",
            address: "lab.example.com",
            port: 22,
            username: "ops",
            group: "Lab",
            tags: ["mosh"],
            status: .idle,
            protocol: .mosh,
            moshConfiguration: MoshHostConfiguration(
                udpPort: 60010,
                serverCommand: "mosh-server new -s",
                predictiveEcho: false,
                useExperimentalConnection: true
            )
        )

        let data = try JSONEncoder().encode(host)
        let decoded = try JSONDecoder().decode(ShellHost.self, from: data)

        XCTAssertEqual(decoded.protocol, .mosh)
        XCTAssertEqual(decoded.moshConfiguration?.udpPort, 60010)
        XCTAssertEqual(decoded.moshConfiguration?.serverCommand, "mosh-server new -s")
        XCTAssertEqual(decoded.moshConfiguration?.predictiveEcho, false)
        XCTAssertEqual(decoded.moshConfiguration?.useExperimentalConnection, true)
    }
}
```

- [ ] **Step 2: Run tests to verify RED**

Run: `xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/MoshHostConfigurationTests`

Expected: FAIL because `RemoteAccessProtocol`, `MoshHostConfiguration`, and the new `ShellHost` fields do not exist yet.

- [ ] **Step 3: Write minimal implementation**

Create `MobileShell/Shared/Models/RemoteAccessProtocol.swift`:

```swift
import Foundation

enum RemoteAccessProtocol: String, CaseIterable, Codable, Sendable {
    case ssh
    case mosh
}
```

Create `MobileShell/Shared/Models/MoshHostConfiguration.swift`:

```swift
import Foundation

struct MoshHostConfiguration: Equatable, Codable, Sendable {
    var udpPort: Int
    var serverCommand: String
    var predictiveEcho: Bool
    var useExperimentalConnection: Bool
}

extension MoshHostConfiguration {
    static let `default` = MoshHostConfiguration(
        udpPort: 60001,
        serverCommand: "mosh-server new -s",
        predictiveEcho: true,
        useExperimentalConnection: false
    )
}
```

Update `ShellHost` in `MobileShell/Models.swift` so it gains:

```swift
var protocol: RemoteAccessProtocol
var moshConfiguration: MoshHostConfiguration?
```

and update its init/`CodingKeys`/`init(from:)` so decoding uses:

```swift
protocol = try container.decodeIfPresent(RemoteAccessProtocol.self, forKey: .protocol) ?? .ssh
moshConfiguration = try container.decodeIfPresent(MoshHostConfiguration.self, forKey: .moshConfiguration)
```

with default init values:

```swift
protocol: RemoteAccessProtocol = .ssh,
moshConfiguration: MoshHostConfiguration? = nil
```

- [ ] **Step 4: Run tests to verify GREEN**

Run: `xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/MoshHostConfigurationTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add MobileShell/Shared/Models/RemoteAccessProtocol.swift MobileShell/Shared/Models/MoshHostConfiguration.swift MobileShell/Models.swift MobileShellTests/Features/Hosts/MoshHostConfigurationTests.swift MobileShell.xcodeproj/project.pbxproj
git commit -m "feat: add mosh host protocol model"
```

### Task 2: Host Add/Edit UI For Mosh Configuration

**Files:**
- Modify: `MobileShell/Features/Hosts/HostsView.swift`
- Modify: `MobileShellTests/MobileShellStoreTests.swift`
- Modify: `MobileShellTests/MobileShellPersistenceTests.swift`

- [ ] **Step 1: Write the failing tests**

Add these tests to `MobileShellTests/MobileShellStoreTests.swift`:

```swift
func testAddHostStoresMoshProtocolAndConfiguration() throws {
    let store = MobileShellStore()

    try store.addHost(
        name: "lab-mosh",
        address: "lab.example.com",
        port: 22,
        username: "ops",
        group: "Lab",
        tags: "mosh,lab",
        password: "",
        protocol: .mosh,
        moshConfiguration: MoshHostConfiguration(
            udpPort: 60010,
            serverCommand: "mosh-server new -s",
            predictiveEcho: false,
            useExperimentalConnection: true
        )
    )

    let host = try XCTUnwrap(store.hosts.last)
    XCTAssertEqual(host.protocol, .mosh)
    XCTAssertEqual(host.moshConfiguration?.udpPort, 60010)
    XCTAssertEqual(host.moshConfiguration?.serverCommand, "mosh-server new -s")
    XCTAssertEqual(host.moshConfiguration?.predictiveEcho, false)
    XCTAssertEqual(host.moshConfiguration?.useExperimentalConnection, true)
}

func testUpdateHostCanSwitchBetweenSSHAndMoshProtocols() throws {
    let host = ShellHost(
        id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
        name: "api",
        address: "api.example.com",
        username: "deploy",
        group: "Production",
        tags: ["ssh"],
        status: .idle
    )
    let store = MobileShellStore(hosts: [host])

    let updated = try XCTUnwrap(store.updateHost(
        host,
        name: host.name,
        address: host.address,
        port: host.port,
        username: host.username,
        group: host.group,
        tags: host.tags.joined(separator: ","),
        password: "",
        protocol: .mosh,
        moshConfiguration: .default
    ))

    XCTAssertEqual(updated.protocol, .mosh)
    XCTAssertEqual(updated.moshConfiguration, .default)
}
```

Add this test to `MobileShellTests/MobileShellPersistenceTests.swift`:

```swift
func testStorePersistsMoshHostConfiguration() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let repository = JSONHostRepository(fileURL: directory.appendingPathComponent("vault.json"))
    let store = try MobileShellStore(repository: repository, credentialVault: InMemoryCredentialVault())

    try store.addHost(
        name: "lab-mosh",
        address: "lab.example.com",
        port: 22,
        username: "ops",
        group: "Lab",
        tags: "mosh",
        password: "",
        protocol: .mosh,
        moshConfiguration: MoshHostConfiguration(
            udpPort: 60010,
            serverCommand: "mosh-server new -s",
            predictiveEcho: false,
            useExperimentalConnection: true
        )
    )

    let restored = try XCTUnwrap(repository.load().hosts.first)
    XCTAssertEqual(restored.protocol, .mosh)
    XCTAssertEqual(restored.moshConfiguration?.udpPort, 60010)
    XCTAssertEqual(restored.moshConfiguration?.serverCommand, "mosh-server new -s")
}
```

- [ ] **Step 2: Run tests to verify RED**

Run: `xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/MobileShellStoreTests/testAddHostStoresMoshProtocolAndConfiguration -only-testing:MobileShellTests/MobileShellStoreTests/testUpdateHostCanSwitchBetweenSSHAndMoshProtocols -only-testing:MobileShellTests/MobileShellPersistenceTests/testStorePersistsMoshHostConfiguration`

Expected: FAIL because `addHost` / `updateHost` do not accept protocol parameters yet.

- [ ] **Step 3: Write minimal implementation**

Update the host mutation APIs in `MobileShell/Models.swift`:

- Add `protocol: RemoteAccessProtocol = .ssh`
- Add `moshConfiguration: MoshHostConfiguration? = nil`

to:

- `addHost(...)`
- `updateHost(...)`
- the internal `makeHost(...)`

Ensure `ShellHost` construction passes these through.

Update `AddHostSheet` and `EditHostSheet` in `MobileShell/Features/Hosts/HostsView.swift`:

- Add `@State private var protocol: RemoteAccessProtocol`
- Add `@State private var moshUDPPort: String`
- Add `@State private var moshServerCommand: String`
- Add `@State private var moshPredictiveEcho: Bool`
- Add `@State private var moshExperimentalConnection: Bool`

Initialize defaults:

```swift
_protocol = State(initialValue: .ssh)
_moshUDPPort = State(initialValue: String(MoshHostConfiguration.default.udpPort))
_moshServerCommand = State(initialValue: MoshHostConfiguration.default.serverCommand)
_moshPredictiveEcho = State(initialValue: MoshHostConfiguration.default.predictiveEcho)
_moshExperimentalConnection = State(initialValue: MoshHostConfiguration.default.useExperimentalConnection)
```

For edit:

```swift
_protocol = State(initialValue: host.protocol)
_moshUDPPort = State(initialValue: String(host.moshConfiguration?.udpPort ?? MoshHostConfiguration.default.udpPort))
_moshServerCommand = State(initialValue: host.moshConfiguration?.serverCommand ?? MoshHostConfiguration.default.serverCommand)
_moshPredictiveEcho = State(initialValue: host.moshConfiguration?.predictiveEcho ?? MoshHostConfiguration.default.predictiveEcho)
_moshExperimentalConnection = State(initialValue: host.moshConfiguration?.useExperimentalConnection ?? MoshHostConfiguration.default.useExperimentalConnection)
```

Add a `Protocol` section:

```swift
Section("Protocol") {
    Picker("Protocol", selection: $protocol) {
        ForEach(RemoteAccessProtocol.allCases, id: \.self) { protocol in
            Text(protocol == .ssh ? "SSH" : "Mosh").tag(protocol)
        }
    }
}
```

Add conditional `Mosh` settings section:

```swift
if protocol == .mosh {
    Section("Mosh") {
        TextField("UDP Port", text: $moshUDPPort)
            .keyboardType(.numberPad)
        TextField("Server Command", text: $moshServerCommand)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        Toggle("Predictive Echo", isOn: $moshPredictiveEcho)
        Toggle("Experimental Connection", isOn: $moshExperimentalConnection)
    }
}
```

In `saveHost()`, derive:

```swift
let moshConfiguration: MoshHostConfiguration?
if protocol == .mosh {
    guard let udpPort = Int(moshUDPPort), (1...65_535).contains(udpPort) else {
        errorMessage = "Enter a Mosh UDP port between 1 and 65535."
        return
    }
    let trimmedCommand = moshServerCommand.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedCommand.isEmpty else {
        errorMessage = "Enter a Mosh server command."
        return
    }
    moshConfiguration = MoshHostConfiguration(
        udpPort: udpPort,
        serverCommand: trimmedCommand,
        predictiveEcho: moshPredictiveEcho,
        useExperimentalConnection: moshExperimentalConnection
    )
} else {
    moshConfiguration = nil
}
```

Then pass `protocol` and `moshConfiguration` into `addHost` / `updateHost`.

- [ ] **Step 4: Run tests to verify GREEN**

Run: `xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/MobileShellStoreTests/testAddHostStoresMoshProtocolAndConfiguration -only-testing:MobileShellTests/MobileShellStoreTests/testUpdateHostCanSwitchBetweenSSHAndMoshProtocols -only-testing:MobileShellTests/MobileShellPersistenceTests/testStorePersistsMoshHostConfiguration`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add MobileShell/Models.swift MobileShell/Features/Hosts/HostsView.swift MobileShellTests/MobileShellStoreTests.swift MobileShellTests/MobileShellPersistenceTests.swift
git commit -m "feat: add mosh host configuration editing"
```

### Task 3: Host List Presentation And Protocol Badge

**Files:**
- Modify: `MobileShell/Features/Hosts/HostsView.swift`
- Modify: `MobileShellTests/Features/Hosts/HostTagNavigationTests.swift`

- [ ] **Step 1: Write the failing test**

Add this test to `MobileShellTests/Features/Hosts/HostTagNavigationTests.swift`:

```swift
func testFilteredHostsRetainMoshProtocolMetadata() {
    let store = MobileShellStore(hosts: [
        ShellHost(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            name: "lab-mosh",
            address: "lab.example.com",
            username: "ops",
            group: "Lab",
            tags: ["mosh"],
            status: .idle,
            protocol: .mosh,
            moshConfiguration: .default
        )
    ])

    let host = try? XCTUnwrap(store.filteredHosts().first)
    XCTAssertEqual(host??.protocol, .mosh)
}
```

- [ ] **Step 2: Run test to verify RED**

Run: `xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/HostTagNavigationTests/testFilteredHostsRetainMoshProtocolMetadata`

Expected: FAIL if protocol metadata is not yet exposed cleanly through current host rows or model use.

- [ ] **Step 3: Write minimal implementation**

In `HostRow` inside `MobileShell/Features/Hosts/HostsView.swift`, add a lightweight protocol badge:

```swift
if host.protocol == .mosh {
    Text("MOSH")
        .font(.caption2.weight(.bold))
        .foregroundStyle(ShellColor.orange)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(ShellColor.orange.opacity(0.14))
        .clipShape(Capsule())
}
```

Place it near the existing authentication / route / startup metadata without displacing the primary host title.

- [ ] **Step 4: Run test to verify GREEN**

Run: `xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/HostTagNavigationTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add MobileShell/Features/Hosts/HostsView.swift MobileShellTests/Features/Hosts/HostTagNavigationTests.swift
git commit -m "feat: show mosh host protocol badge"
```

### Task 4: Terminal Entry Gating For Mosh Hosts

**Files:**
- Modify: `MobileShell/Models.swift`
- Modify: `MobileShell/ShellRootView.swift`
- Modify: `MobileShellTests/MobileShellStoreTests.swift`

- [ ] **Step 1: Write the failing tests**

Add these tests to `MobileShellTests/MobileShellStoreTests.swift`:

```swift
@MainActor
func testOpeningMoshHostDoesNotCreateTerminalSessionAndShowsUnavailableMessage() async throws {
    let host = ShellHost(
        id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
        name: "lab-mosh",
        address: "lab.example.com",
        username: "ops",
        group: "Lab",
        tags: ["mosh"],
        status: .idle,
        protocol: .mosh,
        moshConfiguration: .default
    )
    let shellClient = RecordingTerminalShellClient(result: .success(RecordingTerminalShellSession(outputs: [])))
    let store = MobileShellStore(
        hosts: [host],
        terminalShellClient: shellClient
    )

    await store.openInteractiveTerminal(for: host)

    XCTAssertTrue(store.terminalSessions.isEmpty)
    XCTAssertTrue(shellClient.requests.isEmpty)
    XCTAssertEqual(store.terminalUnavailableMessage, "Mosh configuration is saved for this host, but real Mosh sessions are not available in this version yet.")
}

func testOpeningSSHHostStillCreatesTerminalSession() throws {
    let host = ShellHost(
        id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
        name: "api-prod",
        address: "api.example.com",
        username: "deploy",
        group: "Production",
        tags: ["ssh"],
        status: .idle
    )
    let store = MobileShellStore(hosts: [host])

    store.connect(to: host)

    XCTAssertEqual(store.terminalSessions.count, 1)
}
```

- [ ] **Step 2: Run tests to verify RED**

Run: `xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/MobileShellStoreTests/testOpeningMoshHostDoesNotCreateTerminalSessionAndShowsUnavailableMessage`

Expected: FAIL because `terminalUnavailableMessage` does not exist and `openInteractiveTerminal` still assumes SSH.

- [ ] **Step 3: Write minimal implementation**

In `MobileShell/Models.swift`:

- Add:

```swift
var terminalUnavailableMessage: String?
```

- Clear it at the start of `openInteractiveTerminal(for:)`

- Add early branch:

```swift
if host.protocol == .mosh {
    terminalUnavailableMessage = "Mosh configuration is saved for this host, but real Mosh sessions are not available in this version yet."
    return
}
```

In `MobileShell/ShellRootView.swift`, surface this with an alert:

```swift
.alert(
    "Terminal Unavailable",
    isPresented: Binding(
        get: { store.terminalUnavailableMessage != nil },
        set: { isPresented in
            if !isPresented {
                store.terminalUnavailableMessage = nil
            }
        }
    )
) {
    Button("OK", role: .cancel) {
        store.terminalUnavailableMessage = nil
    }
} message: {
    if let message = store.terminalUnavailableMessage {
        Text(message)
    }
}
```

- [ ] **Step 4: Run tests to verify GREEN**

Run: `xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/MobileShellStoreTests/testOpeningMoshHostDoesNotCreateTerminalSessionAndShowsUnavailableMessage -only-testing:MobileShellTests/MobileShellStoreTests/testOpeningSSHHostStillCreatesTerminalSession`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add MobileShell/Models.swift MobileShell/ShellRootView.swift MobileShellTests/MobileShellStoreTests.swift
git commit -m "feat: gate mosh terminal entry"
```

### Task 5: Broader Verification

**Files:**
- Modify: `docs/product/termius-personal/07-current-state-gap-analysis.md`

- [ ] **Step 1: Update progress documentation**

Add a short note in `docs/product/termius-personal/07-current-state-gap-analysis.md` under the deferred/forward-looking area that `Mosh` now has configuration-level groundwork but not transport runtime.

- [ ] **Step 2: Run broader verification**

Run: `xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'`

Run: `xcodebuild build -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'`

Expected: both commands PASS.

- [ ] **Step 3: Commit**

```bash
git add docs/product/termius-personal/07-current-state-gap-analysis.md
git commit -m "docs: record mosh configuration groundwork"
```
