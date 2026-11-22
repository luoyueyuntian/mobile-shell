# Dynamic Port Forwarding V1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a real SOCKS5-backed dynamic port forwarding runtime so saved `dynamic` rules can start locally, proxy `CONNECT` traffic through SSH, and stop cleanly like existing local and remote tunnel types.

**Architecture:** Keep `MobileShellStore` orchestration unchanged at the boundary, remove the dynamic early-reject path, and route `PortForwardKind.dynamic` into a new service under `MobileShell/Services/PortForwarding/`. The new service owns SOCKS5 handshake parsing plus NIO listener lifecycle, while `CitadelPortForwardingClient` continues to be the single dispatch point for local, remote, and dynamic sessions.

**Tech Stack:** Swift 6, SwiftUI Observation, XCTest, Citadel, NIO, NIOPosix, existing `PortForwardGlueHandler`.

---

### Task 1: Dynamic Rule Store Behavior

**Files:**
- Modify: `MobileShell/Features/PortForwarding/MobileShellStorePortForwarding.swift`
- Modify: `MobileShell/Models.swift`
- Modify: `MobileShellTests/Features/PortForwarding/PortForwardingTypeTests.swift`

- [ ] **Step 1: Write the failing test**

Update `MobileShellTests/Features/PortForwarding/PortForwardingTypeTests.swift` so dynamic start expects success instead of the unsupported message:

```swift
@MainActor
func testStartingDynamicPortForwardUsesTypedRuleAndMarksItActive() async throws {
    let hostID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-000000000004")!
    let host = ShellHost(
        id: hostID,
        name: "bastion",
        address: "bastion.example.com",
        username: "deploy",
        group: "Production",
        tags: ["ssh"],
        status: .idle
    )
    let rule = PortForwardRule(
        id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-000000000005")!,
        kind: .dynamic,
        name: "SOCKS Proxy",
        sshHostID: hostID,
        localHost: "127.0.0.1",
        localPort: 1080,
        remoteHost: "",
        remotePort: 0,
        isActive: false
    )
    let vault = InMemoryCredentialVault()
    try vault.savePassword("secret", forHostID: hostID)
    let client = RecordingTypedPortForwardingClient()
    let store = MobileShellStore(
        hosts: [host],
        portForwardRules: [rule],
        credentialVault: vault,
        portForwardingClient: client
    )

    await store.togglePortForwardRule(rule)

    XCTAssertTrue(try XCTUnwrap(store.portForwardRules.first { $0.id == rule.id }).isActive)
    XCTAssertEqual(client.startedRules, [rule])
    XCTAssertNil(store.portForwardErrorMessage)
}
```

- [ ] **Step 2: Run test to verify RED**

Run:

```bash
xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/PortForwardingTypeTests
```

Expected: FAIL because store still blocks dynamic rules before reaching the client.

- [ ] **Step 3: Write minimal implementation**

Remove the store-level early return in `MobileShell/Features/PortForwarding/MobileShellStorePortForwarding.swift`:

```swift
if storedRule.kind == .dynamic {
    portForwardRules[index].isActive = false
    portForwardErrorMessage = "Port forward error: Dynamic port forwarding is not supported yet"
    return
}
```

Update `MobileShell/Models.swift` dynamic description to describe a real local SOCKS5 tunnel:

```swift
case .dynamic:
    "Run a local SOCKS5 tunnel through SSH for browser and CLI traffic."
```

- [ ] **Step 4: Run test to verify GREEN**

Run the same targeted command.

Expected: The dynamic store test passes, even though backend protocol tests are still pending.

### Task 2: SOCKS5 Handshake Parsing

**Files:**
- Create: `MobileShell/Services/PortForwarding/SOCKS5DynamicPortForwarding.swift`
- Create: `MobileShellTests/Services/PortForwarding/SOCKS5DynamicPortForwardingTests.swift`

- [ ] **Step 1: Write the failing tests**

Create protocol-focused tests in `MobileShellTests/Services/PortForwarding/SOCKS5DynamicPortForwardingTests.swift`:

```swift
import XCTest
@testable import MobileShell

final class SOCKS5DynamicPortForwardingTests: XCTestCase {
    func testGreetingAcceptsNoAuthMethod() throws {
        let result = try SOCKS5ServerHandshake.parseGreeting([0x05, 0x02, 0x00, 0x02])
        XCTAssertEqual(result.selectedMethod, 0x00)
    }

    func testGreetingRejectsWhenNoAuthMethodMissing() {
        XCTAssertThrowsError(try SOCKS5ServerHandshake.parseGreeting([0x05, 0x01, 0x02])) { error in
            XCTAssertEqual(error as? SOCKS5HandshakeError, .unsupportedAuthenticationMethod)
        }
    }

    func testConnectRequestParsesDomainDestination() throws {
        let bytes: [UInt8] = [0x05, 0x01, 0x00, 0x03, 0x0B] + Array("example.com".utf8) + [0x01, 0xBB]
        let request = try SOCKS5ConnectRequest.parse(bytes)

        XCTAssertEqual(request.host, "example.com")
        XCTAssertEqual(request.port, 443)
    }

    func testConnectRequestRejectsUDPAssociate() {
        let bytes: [UInt8] = [0x05, 0x03, 0x00, 0x01, 127, 0, 0, 1, 0x00, 0x35]
        XCTAssertThrowsError(try SOCKS5ConnectRequest.parse(bytes)) { error in
            XCTAssertEqual(error as? SOCKS5HandshakeError, .unsupportedCommand(0x03))
        }
    }
}
```

- [ ] **Step 2: Run test to verify RED**

Run:

```bash
xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/SOCKS5DynamicPortForwardingTests
```

Expected: FAIL because the parser types do not exist yet.

- [ ] **Step 3: Write minimal implementation**

Inside `MobileShell/Services/PortForwarding/SOCKS5DynamicPortForwarding.swift`, add pure parsing helpers first:

```swift
enum SOCKS5HandshakeError: Error, Equatable {
    case unsupportedVersion(UInt8)
    case unsupportedAuthenticationMethod
    case unsupportedCommand(UInt8)
    case unsupportedAddressType(UInt8)
    case malformedRequest
}

struct SOCKS5GreetingResult: Equatable {
    let selectedMethod: UInt8
}

enum SOCKS5ServerHandshake {
    static func parseGreeting(_ bytes: [UInt8]) throws -> SOCKS5GreetingResult {
        guard bytes.count >= 3 else { throw SOCKS5HandshakeError.malformedRequest }
        guard bytes[0] == 0x05 else { throw SOCKS5HandshakeError.unsupportedVersion(bytes[0]) }
        let methodCount = Int(bytes[1])
        guard bytes.count == methodCount + 2 else { throw SOCKS5HandshakeError.malformedRequest }
        guard bytes[2...].contains(0x00) else {
            throw SOCKS5HandshakeError.unsupportedAuthenticationMethod
        }
        return SOCKS5GreetingResult(selectedMethod: 0x00)
    }
}

struct SOCKS5ConnectRequest: Equatable {
    let host: String
    let port: Int

    static func parse(_ bytes: [UInt8]) throws -> SOCKS5ConnectRequest {
        guard bytes.count >= 7 else { throw SOCKS5HandshakeError.malformedRequest }
        guard bytes[0] == 0x05 else { throw SOCKS5HandshakeError.unsupportedVersion(bytes[0]) }
        guard bytes[1] == 0x01 else { throw SOCKS5HandshakeError.unsupportedCommand(bytes[1]) }
        guard bytes[2] == 0x00 else { throw SOCKS5HandshakeError.malformedRequest }

        switch bytes[3] {
        case 0x01:
            guard bytes.count == 10 else { throw SOCKS5HandshakeError.malformedRequest }
            let host = "\(bytes[4]).\(bytes[5]).\(bytes[6]).\(bytes[7])"
            let port = Int(bytes[8]) << 8 | Int(bytes[9])
            return SOCKS5ConnectRequest(host: host, port: port)
        case 0x03:
            let count = Int(bytes[4])
            guard bytes.count == count + 7 else { throw SOCKS5HandshakeError.malformedRequest }
            let host = String(decoding: bytes[5..<(5 + count)], as: UTF8.self)
            let portIndex = 5 + count
            let port = Int(bytes[portIndex]) << 8 | Int(bytes[portIndex + 1])
            return SOCKS5ConnectRequest(host: host, port: port)
        case 0x04:
            guard bytes.count == 22 else { throw SOCKS5HandshakeError.malformedRequest }
            let segments = stride(from: 4, to: 20, by: 2).map { index in
                String(format: "%02x%02x", bytes[index], bytes[index + 1])
            }
            let port = Int(bytes[20]) << 8 | Int(bytes[21])
            return SOCKS5ConnectRequest(host: segments.joined(separator: ":"), port: port)
        default:
            throw SOCKS5HandshakeError.unsupportedAddressType(bytes[3])
        }
    }
}
```

- [ ] **Step 4: Run test to verify GREEN**

Run the same targeted command.

Expected: Parser tests pass before any listener integration is added.

### Task 3: Dynamic Listener Runtime

**Files:**
- Modify: `MobileShell/ShellConnection.swift`
- Modify: `MobileShell/Services/PortForwarding/SOCKS5DynamicPortForwarding.swift`
- Modify: `MobileShellTests/Features/PortForwarding/PortForwardingTypeTests.swift`

- [ ] **Step 1: Write the failing integration-style test**

Extend `MobileShellTests/Features/PortForwarding/PortForwardingTypeTests.swift` with a client-level assertion that `CitadelPortForwardingClient` no longer treats `.dynamic` as unsupported:

```swift
func testDynamicKindIsNotReportedAsUnsupported() {
    XCTAssertNotEqual(
        PortForwardingError.unsupportedKind(.dynamic).errorDescription,
        "Dynamic port forwarding is not supported yet"
    )
}
```

Also keep the store success test from Task 1 as the behavior gate.

- [ ] **Step 2: Run test to verify RED**

Run:

```bash
xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/PortForwardingTypeTests
```

Expected: FAIL because backend error text and dispatch still encode the unsupported path.

- [ ] **Step 3: Write minimal implementation**

In `MobileShell/ShellConnection.swift`, change the dispatch to route `.dynamic` into the new session:

```swift
switch rule.kind {
case .local:
    return try await CitadelPortForwardingSession.startLocal(rule: rule, client: client)
case .remote:
    return try await CitadelRemotePortForwardingSession.start(rule: rule, client: client)
case .dynamic:
    return try await CitadelDynamicPortForwardingSession.start(rule: rule, client: client)
}
```

Implement `CitadelDynamicPortForwardingSession.start(rule:client:)` in `MobileShell/Services/PortForwarding/SOCKS5DynamicPortForwarding.swift` to:

```swift
let serverChannel = try await ServerBootstrap(group: client.eventLoop, childGroup: client.eventLoop)
    .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
    .childChannelOption(ChannelOptions.allowRemoteHalfClosure, value: true)
    .childChannelInitializer { inboundChannel in
        inboundChannel.pipeline.addHandler(
            SOCKS5DynamicPortForwardingHandler(client: client, inboundChannel: inboundChannel)
        )
    }
    .bind(host: rule.localHost, port: rule.localPort)
    .get()
```

The handler should:

- parse greeting
- reply `[0x05, 0x00]`
- parse `CONNECT`
- create `direct-tcpip` channel with requested host and port
- reply success bytes
- glue the inbound channel to the SSH channel via `PortForwardGlueHandler.matchedPair()`

- [ ] **Step 4: Run targeted tests**

Run:

```bash
xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/PortForwardingTypeTests -only-testing:MobileShellTests/SOCKS5DynamicPortForwardingTests
```

Expected: PASS.

### Task 4: Regression Verification

**Files:**
- Modify: `docs/product/termius-personal/07-current-state-gap-analysis.md`
- Verify all touched source and test files

- [ ] **Step 1: Update user-facing gap status**

Mark dynamic forwarding as implemented in `docs/product/termius-personal/07-current-state-gap-analysis.md` and narrow the remaining gap list to `Telnet / Serial` and deferred cloud sync.

- [ ] **Step 2: Run relevant port forwarding tests**

Run:

```bash
xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/PortForwardingTypeTests -only-testing:MobileShellTests/PortForwardingStoreTests -only-testing:MobileShellTests/SOCKS5DynamicPortForwardingTests
```

Expected: PASS.

- [ ] **Step 3: Run app build**

Run:

```bash
xcodebuild build -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Run full tests if targeted verification is green**

Run:

```bash
xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'
```

Expected: `** TEST SUCCEEDED **`
