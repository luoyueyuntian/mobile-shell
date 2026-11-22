# Mosh Runtime V1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a first real `Mosh` terminal runtime so configured `Mosh` hosts can launch `mosh-server` over SSH, establish a true Mosh session, and render that session through the existing terminal UI.

**Architecture:** Reuse the existing host protocol/config groundwork, add a new `MoshPreparationClient` for SSH-launched server startup plus parsing, and introduce a separate `MoshRuntimeClient` / `MoshRuntimeSession` boundary for the real UDP-based runtime. The recommended runtime strategy is a thin iOS bridge around upstream Mosh client core rather than reimplementing the protocol stack in Swift from scratch.

**Tech Stack:** Swift 6, SwiftUI Observation, XCTest, existing SSH request builder and terminal lifecycle, Objective-C++ / C++ bridge for upstream Mosh client code, JSON persistence.

---

### Task 1: Preparation Result Parsing And Error Typing

**Files:**
- Create: `MobileShell/Services/Mosh/MoshPreparationError.swift`
- Create: `MobileShell/Services/Mosh/MoshServerLaunchResult.swift`
- Create: `MobileShell/Services/Mosh/MoshPreparationParser.swift`
- Create: `MobileShellTests/Services/Mosh/MoshPreparationParserTests.swift`
- Modify: `MobileShell.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write the failing tests**

Create `MobileShellTests/Services/Mosh/MoshPreparationParserTests.swift`:

```swift
import XCTest
@testable import MobileShell

final class MoshPreparationParserTests: XCTestCase {
    func testParseLaunchResultExtractsPortAndKeyFromOfficialOutput() throws {
        let output = """
        MOSH CONNECT 60004 4NeCCgvZFe2RnPgrcU1PQw

        mosh-server (mosh 1.1.3)
        [mosh-server detached, pid = 30261]
        """

        let result = try MoshPreparationParser.parse(output)

        XCTAssertEqual(result.port, 60004)
        XCTAssertEqual(result.key, "4NeCCgvZFe2RnPgrcU1PQw")
        XCTAssertEqual(result.serverOutput, output)
    }

    func testParseLaunchResultMapsMissingServerMessage() {
        let output = "bash: mosh-server: command not found"

        XCTAssertThrowsError(try MoshPreparationParser.parse(output)) { error in
            XCTAssertEqual(error as? MoshPreparationError, .moshServerMissing)
        }
    }

    func testParseLaunchResultMapsMalformedHandshake() {
        let output = "MOSH CONNECT garbage"

        XCTAssertThrowsError(try MoshPreparationParser.parse(output)) { error in
            XCTAssertEqual(error as? MoshPreparationError, .moshHandshakeParseFailed)
        }
    }

    func testParseLaunchResultMapsGenericLaunchFailure() {
        let output = "mosh-server: failed to bind"

        XCTAssertThrowsError(try MoshPreparationParser.parse(output)) { error in
            XCTAssertEqual(error as? MoshPreparationError, .moshServerLaunchFailed(output))
        }
    }
}
```

- [ ] **Step 2: Run tests to verify RED**

Run: `xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/MoshPreparationParserTests`

Expected: FAIL because the Mosh preparation parser/types do not exist yet.

- [ ] **Step 3: Write minimal implementation**

Create `MobileShell/Services/Mosh/MoshPreparationError.swift`:

```swift
import Foundation

enum MoshPreparationError: Error, Equatable {
    case moshServerMissing
    case moshServerLaunchFailed(String)
    case moshHandshakeParseFailed
}
```

Create `MobileShell/Services/Mosh/MoshServerLaunchResult.swift`:

```swift
import Foundation

struct MoshServerLaunchResult: Equatable {
    let port: Int
    let key: String
    let serverOutput: String
}
```

Create `MobileShell/Services/Mosh/MoshPreparationParser.swift`:

```swift
import Foundation

enum MoshPreparationParser {
    static func parse(_ output: String) throws -> MoshServerLaunchResult {
        if output.localizedCaseInsensitiveContains("mosh-server: command not found") ||
            output.localizedCaseInsensitiveContains("mosh-server not found") {
            throw MoshPreparationError.moshServerMissing
        }

        guard let connectLine = output
            .split(whereSeparator: \\.isNewline)
            .map(String.init)
            .first(where: { $0.hasPrefix("MOSH CONNECT ") })
        else {
            throw MoshPreparationError.moshServerLaunchFailed(output)
        }

        let parts = connectLine.split(separator: " ")
        guard parts.count == 4,
              let port = Int(parts[2]),
              !parts[3].isEmpty else {
            throw MoshPreparationError.moshHandshakeParseFailed
        }

        return MoshServerLaunchResult(
            port: port,
            key: String(parts[3]),
            serverOutput: output
        )
    }
}
```

- [ ] **Step 4: Run tests to verify GREEN**

Run: `xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/MoshPreparationParserTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add MobileShell/Services/Mosh/MoshPreparationError.swift MobileShell/Services/Mosh/MoshServerLaunchResult.swift MobileShell/Services/Mosh/MoshPreparationParser.swift MobileShellTests/Services/Mosh/MoshPreparationParserTests.swift MobileShell.xcodeproj/project.pbxproj
git commit -m "feat: add mosh preparation parsing"
```

### Task 2: SSH-Backed Mosh Preparation Client

**Files:**
- Create: `MobileShell/Services/Mosh/MoshPreparationClient.swift`
- Create: `MobileShell/Services/Mosh/SSHMoshPreparationClient.swift`
- Create: `MobileShellTests/Services/Mosh/SSHMoshPreparationClientTests.swift`
- Modify: `MobileShell.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write the failing tests**

Create `MobileShellTests/Services/Mosh/SSHMoshPreparationClientTests.swift`:

```swift
import XCTest
@testable import MobileShell

final class SSHMoshPreparationClientTests: XCTestCase {
    func testPreparationRunsConfiguredServerCommandThroughExecutorAndParsesResult() async throws {
        let executor = RecordingMoshCommandExecutor(result: .success("""
        MOSH CONNECT 60004 4NeCCgvZFe2RnPgrcU1PQw
        [mosh-server detached, pid = 30261]
        """))
        let client = SSHMoshPreparationClient(commandExecutor: executor)
        let request = SSHConnectionRequest(
            hostID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            displayName: "lab-mosh",
            hostname: "lab.example.com",
            port: 22,
            username: "ops",
            password: "secret"
        )
        let configuration = MoshHostConfiguration(
            udpPort: 60010,
            serverCommand: "mosh-server new -s",
            predictiveEcho: false,
            useExperimentalConnection: true
        )

        let result = try await client.prepare(using: request, configuration: configuration)

        XCTAssertEqual(result.port, 60004)
        XCTAssertEqual(result.key, "4NeCCgvZFe2RnPgrcU1PQw")
        XCTAssertEqual(executor.commands, ["mosh-server new -s -p 60010"])
    }

    func testPreparationMapsMissingServerFailure() async {
        let executor = RecordingMoshCommandExecutor(result: .success("bash: mosh-server: command not found"))
        let client = SSHMoshPreparationClient(commandExecutor: executor)
        let request = SSHConnectionRequest(
            hostID: UUID(),
            displayName: "lab-mosh",
            hostname: "lab.example.com",
            port: 22,
            username: "ops",
            password: "secret"
        )

        do {
            _ = try await client.prepare(using: request, configuration: .default)
            XCTFail("Expected moshServerMissing")
        } catch {
            XCTAssertEqual(error as? MoshPreparationError, .moshServerMissing)
        }
    }
}
```

Also add a test helper in the same file:

```swift
private final class RecordingMoshCommandExecutor: SSHCommandExecuting, @unchecked Sendable {
    var commands: [String] = []
    let result: Result<String, Error>

    init(result: Result<String, Error>) {
        self.result = result
    }

    func run(_ command: String, using request: SSHConnectionRequest) async throws -> String {
        commands.append(command)
        return try result.get()
    }
}
```

- [ ] **Step 2: Run tests to verify RED**

Run: `xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/SSHMoshPreparationClientTests`

Expected: FAIL because the preparation client protocol/implementation does not exist yet.

- [ ] **Step 3: Write minimal implementation**

Create `MobileShell/Services/Mosh/MoshPreparationClient.swift`:

```swift
import Foundation

protocol MoshPreparationClient: Sendable {
    func prepare(
        using request: SSHConnectionRequest,
        configuration: MoshHostConfiguration
    ) async throws -> MoshServerLaunchResult
}
```

Create `MobileShell/Services/Mosh/SSHMoshPreparationClient.swift`:

```swift
import Foundation

struct SSHMoshPreparationClient: MoshPreparationClient {
    let commandExecutor: any SSHCommandExecuting

    init(commandExecutor: any SSHCommandExecuting) {
        self.commandExecutor = commandExecutor
    }

    func prepare(
        using request: SSHConnectionRequest,
        configuration: MoshHostConfiguration
    ) async throws -> MoshServerLaunchResult {
        let command = "\(configuration.serverCommand) -p \(configuration.udpPort)"
        let output = try await commandExecutor.run(command, using: request)
        return try MoshPreparationParser.parse(output)
    }
}
```

- [ ] **Step 4: Run tests to verify GREEN**

Run: `xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/SSHMoshPreparationClientTests -only-testing:MobileShellTests/MoshPreparationParserTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add MobileShell/Services/Mosh/MoshPreparationClient.swift MobileShell/Services/Mosh/SSHMoshPreparationClient.swift MobileShellTests/Services/Mosh/SSHMoshPreparationClientTests.swift MobileShell.xcodeproj/project.pbxproj
git commit -m "feat: add ssh-backed mosh preparation client"
```

### Task 3: Mosh Runtime Abstractions And Testable Store Wiring

**Files:**
- Create: `MobileShell/Services/Mosh/MoshRuntimeError.swift`
- Create: `MobileShell/Services/Mosh/MoshRuntimeClient.swift`
- Create: `MobileShell/Services/Mosh/MoshRuntimeSession.swift`
- Modify: `MobileShell/Models.swift`
- Create: `MobileShellTests/Features/Terminal/MoshTerminalRuntimeTests.swift`
- Modify: `MobileShell.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write the failing tests**

Create `MobileShellTests/Features/Terminal/MoshTerminalRuntimeTests.swift`:

```swift
import XCTest
@testable import MobileShell

final class MoshTerminalRuntimeTests: XCTestCase {
    @MainActor
    func testOpeningMoshHostRunsPreparationThenRuntimeAndCreatesSession() async throws {
        let host = ShellHost(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            name: "lab-mosh",
            address: "lab.example.com",
            username: "ops",
            group: "Lab",
            tags: ["mosh"],
            status: .idle,
            protocol: .mosh,
            moshConfiguration: .default
        )
        let preparationClient = RecordingMoshPreparationClient(result: .success(
            MoshServerLaunchResult(port: 60004, key: "4NeCCgvZFe2RnPgrcU1PQw", serverOutput: "MOSH CONNECT 60004 4NeCCgvZFe2RnPgrcU1PQw")
        ))
        let runtimeSession = RecordingMoshRuntimeSession(outputs: ["mosh-ready", "ops@lab:~$"])
        let runtimeClient = RecordingMoshRuntimeClient(result: .success(runtimeSession))
        let store = MobileShellStore(
            hosts: [host],
            moshPreparationClient: preparationClient,
            moshRuntimeClient: runtimeClient
        )

        await store.openInteractiveTerminal(for: host)
        try await Task.sleep(nanoseconds: 1_000_000)

        XCTAssertEqual(preparationClient.preparedHostIDs, [host.id])
        XCTAssertEqual(runtimeClient.startedHostIDs, [host.id])
        XCTAssertEqual(store.terminalSessions.count, 1)
        XCTAssertEqual(store.selectedTerminalSession?.hostName, "lab-mosh")
        XCTAssertEqual(store.selectedTerminalSession?.state, .connected)
        XCTAssertTrue(store.selectedTerminalSession?.lines.contains("mosh-ready") == true)
    }

    @MainActor
    func testMissingMoshServerShowsInstallGuidanceAndCreatesNoSession() async {
        let host = ShellHost(
            id: UUID(),
            name: "lab-mosh",
            address: "lab.example.com",
            username: "ops",
            group: "Lab",
            tags: ["mosh"],
            status: .idle,
            protocol: .mosh,
            moshConfiguration: .default
        )
        let preparationClient = RecordingMoshPreparationClient(result: .failure(MoshPreparationError.moshServerMissing))
        let runtimeClient = RecordingMoshRuntimeClient(result: .failure(MoshRuntimeError.connectFailed("unused")))
        let store = MobileShellStore(
            hosts: [host],
            moshPreparationClient: preparationClient,
            moshRuntimeClient: runtimeClient
        )

        await store.openInteractiveTerminal(for: host)

        XCTAssertTrue(store.terminalSessions.isEmpty)
        XCTAssertEqual(store.terminalUnavailableMessage, "Mosh is configured for this host, but `mosh-server` is not installed on the remote machine. Install `mosh` on the server and try again.")
        XCTAssertTrue(runtimeClient.startedHostIDs.isEmpty)
    }

    @MainActor
    func testMoshRuntimeFailureShowsErrorAndCreatesNoSession() async {
        let host = ShellHost(
            id: UUID(),
            name: "lab-mosh",
            address: "lab.example.com",
            username: "ops",
            group: "Lab",
            tags: ["mosh"],
            status: .idle,
            protocol: .mosh,
            moshConfiguration: .default
        )
        let preparationClient = RecordingMoshPreparationClient(result: .success(
            MoshServerLaunchResult(port: 60004, key: "4NeCCgvZFe2RnPgrcU1PQw", serverOutput: "MOSH CONNECT 60004 4NeCCgvZFe2RnPgrcU1PQw")
        ))
        let runtimeClient = RecordingMoshRuntimeClient(result: .failure(MoshRuntimeError.connectFailed("UDP handshake failed")))
        let store = MobileShellStore(
            hosts: [host],
            moshPreparationClient: preparationClient,
            moshRuntimeClient: runtimeClient
        )

        await store.openInteractiveTerminal(for: host)

        XCTAssertTrue(store.terminalSessions.isEmpty)
        XCTAssertEqual(store.terminalUnavailableMessage, "Mosh connection failed: UDP handshake failed")
    }
}
```

Add test doubles in the same file:

```swift
private final class RecordingMoshPreparationClient: MoshPreparationClient, @unchecked Sendable {
    var preparedHostIDs: [UUID] = []
    let result: Result<MoshServerLaunchResult, Error>

    init(result: Result<MoshServerLaunchResult, Error>) {
        self.result = result
    }

    func prepare(using request: SSHConnectionRequest, configuration: MoshHostConfiguration) async throws -> MoshServerLaunchResult {
        preparedHostIDs.append(request.hostID)
        return try result.get()
    }
}

private final class RecordingMoshRuntimeSession: MoshRuntimeSession, @unchecked Sendable {
    let outputStream: AsyncStream<String>
    private let continuation: AsyncStream<String>.Continuation
    private(set) var sentInputs: [String] = []
    private(set) var closeCount = 0

    init(outputs: [String]) {
        var captured: AsyncStream<String>.Continuation!
        outputStream = AsyncStream { continuation in
            captured = continuation
        }
        continuation = captured
        for output in outputs {
            continuation.yield(output)
        }
    }

    func send(_ input: String) async throws {
        sentInputs.append(input)
    }

    func close() async {
        closeCount += 1
        continuation.finish()
    }
}

private final class RecordingMoshRuntimeClient: MoshRuntimeClient, @unchecked Sendable {
    var startedHostIDs: [UUID] = []
    let result: Result<any MoshRuntimeSession, Error>

    init(result: Result<any MoshRuntimeSession, Error>) {
        self.result = result
    }

    func connect(host: ShellHost, launchResult: MoshServerLaunchResult) async throws -> any MoshRuntimeSession {
        startedHostIDs.append(host.id)
        return try result.get()
    }
}
```

- [ ] **Step 2: Run tests to verify RED**

Run: `xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/MoshTerminalRuntimeTests`

Expected: FAIL because the Mosh runtime abstractions and store orchestration do not exist yet.

- [ ] **Step 3: Write minimal implementation**

Create `MobileShell/Services/Mosh/MoshRuntimeError.swift`:

```swift
import Foundation

enum MoshRuntimeError: Error, Equatable {
    case connectFailed(String)
}
```

Create `MobileShell/Services/Mosh/MoshRuntimeSession.swift`:

```swift
import Foundation

protocol MoshRuntimeSession: Sendable {
    var outputStream: AsyncStream<String> { get }
    func send(_ input: String) async throws
    func close() async
}
```

Replace it with:

```swift
import Foundation

protocol MoshRuntimeSession: TerminalShellSession {}
```

Create `MobileShell/Services/Mosh/MoshRuntimeClient.swift`:

```swift
import Foundation

protocol MoshRuntimeClient: Sendable {
    func connect(
        host: ShellHost,
        launchResult: MoshServerLaunchResult
    ) async throws -> any MoshRuntimeSession
}
```

Then in `MobileShell/Models.swift`:

- Add injected properties:

```swift
private var moshPreparationClient: (any MoshPreparationClient)?
private var moshRuntimeClient: (any MoshRuntimeClient)?
```

- Add initializer parameters with default `nil`
- In `openInteractiveTerminal(for:)`, replace the current Mosh unavailable branch with:

```swift
if host.protocol == .mosh {
    await openMoshTerminal(for: host)
    return
}
```

- Add:

```swift
@MainActor
private func openMoshTerminal(for host: ShellHost) async {
    terminalUnavailableMessage = nil
    guard let configuration = host.moshConfiguration,
          let moshPreparationClient,
          let moshRuntimeClient else {
        terminalUnavailableMessage = "Mosh configuration is saved for this host, but real Mosh sessions are not available in this version yet."
        return
    }

    let request: SSHConnectionRequest
    do {
        request = try SSHConnectionRequestBuilder(
            credentialVault: credentialVault,
            hosts: hosts,
            identities: identities,
            keys: keys,
            certificates: certificates,
            hostGroupProfiles: hostGroupProfiles,
            knownHosts: knownHosts
        ).request(for: host)
    } catch {
        terminalUnavailableMessage = "Mosh connection failed: \(error.localizedDescription)"
        return
    }

    do {
        let launchResult = try await moshPreparationClient.prepare(using: request, configuration: configuration)
        let runtimeSession = try await moshRuntimeClient.connect(host: host, launchResult: launchResult)
        let sessionID = connect(to: host, runStartupSnippet: false)
        guard let sessionID else { return }
        activeTerminalShellSessions[sessionID] = runtimeSession
        if let index = terminalSessions.firstIndex(where: { $0.id == sessionID }) {
            terminalSessions[index].state = .connected
        }

        let outputTask = Task { @MainActor [weak self] in
            for await line in runtimeSession.outputStream {
                guard let self,
                      let index = self.terminalSessions.firstIndex(where: { $0.id == sessionID })
                else { continue }
                self.terminalSessions[index].lines.append(line)
                self.appendSessionLogLines([line], for: sessionID)
            }
        }
        terminalShellOutputTasks[sessionID] = outputTask
    } catch let error as MoshPreparationError {
        switch error {
        case .moshServerMissing:
            terminalUnavailableMessage = "Mosh is configured for this host, but `mosh-server` is not installed on the remote machine. Install `mosh` on the server and try again."
        case .moshServerLaunchFailed(let output):
            terminalUnavailableMessage = "Mosh server failed to start: \(output)"
        case .moshHandshakeParseFailed:
            terminalUnavailableMessage = "Mosh server started, but the handshake response could not be parsed."
        }
    } catch let error as MoshRuntimeError {
        switch error {
        case .connectFailed(let message):
            terminalUnavailableMessage = "Mosh connection failed: \(message)"
        }
    } catch {
        terminalUnavailableMessage = "Mosh connection failed: \(error.localizedDescription)"
    }
}
```

- [ ] **Step 4: Run tests to verify GREEN**

Run: `xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/MoshTerminalRuntimeTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add MobileShell/Services/Mosh/MoshRuntimeError.swift MobileShell/Services/Mosh/MoshRuntimeClient.swift MobileShell/Services/Mosh/MoshRuntimeSession.swift MobileShell/Models.swift MobileShellTests/Features/Terminal/MoshTerminalRuntimeTests.swift MobileShell.xcodeproj/project.pbxproj
git commit -m "feat: orchestrate mosh runtime path"
```

### Task 4: Upstream Mosh Client Bridge Spike

**Files:**
- Create: `MobileShell/Services/Mosh/Bridge/MoshClientBridge.h`
- Create: `MobileShell/Services/Mosh/Bridge/MoshClientBridge.mm`
- Create: `MobileShell/Services/Mosh/Bridge/MoshRuntimeClientBridge.swift`
- Modify: `MobileShell.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write the failing bridge smoke test**

Create `MobileShellTests/Services/Mosh/MoshClientBridgeSmokeTests.swift`:

```swift
import XCTest
@testable import MobileShell

final class MoshClientBridgeSmokeTests: XCTestCase {
    func testBridgeObjectCanBeConstructed() {
        let bridge = MoshClientBridgeAdapter()
        XCTAssertNotNil(bridge)
    }
}
```

- [ ] **Step 2: Run test to verify RED**

Run: `xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/MoshClientBridgeSmokeTests`

Expected: FAIL because no bridge exists yet.

- [ ] **Step 3: Write minimal implementation**

Create `MobileShell/Services/Mosh/Bridge/MoshClientBridge.h`:

```objective-c
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MoshClientBridgeAdapter : NSObject
- (instancetype)init;
@end

NS_ASSUME_NONNULL_END
```

Create `MobileShell/Services/Mosh/Bridge/MoshClientBridge.mm`:

```objective-c++
#import "MoshClientBridge.h"

@implementation MoshClientBridgeAdapter
- (instancetype)init {
    self = [super init];
    return self;
}
@end
```

Create `MobileShell/Services/Mosh/Bridge/MoshRuntimeClientBridge.swift`:

```swift
import Foundation

final class MoshRuntimeClientBridge: NSObject {
    let adapter = MoshClientBridgeAdapter()
}
```

This task is only a bridge scaffold. Do not claim real Mosh runtime connectivity yet.

- [ ] **Step 4: Run test to verify GREEN**

Run: `xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/MoshClientBridgeSmokeTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add MobileShell/Services/Mosh/Bridge/MoshClientBridge.h MobileShell/Services/Mosh/Bridge/MoshClientBridge.mm MobileShell/Services/Mosh/Bridge/MoshRuntimeClientBridge.swift MobileShellTests/Services/Mosh/MoshClientBridgeSmokeTests.swift MobileShell.xcodeproj/project.pbxproj
git commit -m "chore: add mosh client bridge scaffold"
```

### Task 5: Connect The Real Runtime Or Stop At The Proven Boundary

**Files:**
- Modify: `MobileShell/Services/Mosh/Bridge/MoshClientBridge.mm`
- Modify: `MobileShell/Services/Mosh/Bridge/MoshRuntimeClientBridge.swift`
- Modify: `MobileShell/Tests/Services/Mosh/...` as needed

- [ ] **Step 1: Decide the implementation boundary explicitly**

Before touching code, verify one fact in the codebase:

- If upstream Mosh client sources are vendored and buildable for iOS, proceed with the bridge integration in this task.
- If they are not vendored and no iOS-safe embeddable client core is available locally, STOP this task and record that the plan must split into a separate upstream-vendoring spike before claiming real runtime support.

- [ ] **Step 2: If bridgeable, add one failing integration test**

The failing test must prove a real `MoshRuntimeSession` can emit at least one output line from a controlled bridge fixture.

- [ ] **Step 3: Implement the smallest real bridge**

Only if upstream code is available locally and linkable:

- instantiate the upstream client core
- feed launch result host/port/key into it
- bridge received output back into `AsyncStream<String>`
- bridge send/close methods

- [ ] **Step 4: Verify GREEN**

Run the Mosh runtime test suite plus the broader terminal regression suite.

- [ ] **Step 5: Commit**

```bash
git add MobileShell/Services/Mosh/Bridge/MoshClientBridge.h MobileShell/Services/Mosh/Bridge/MoshClientBridge.mm MobileShell/Services/Mosh/Bridge/MoshRuntimeClientBridge.swift MobileShellTests/Services/Mosh/MoshClientBridgeSmokeTests.swift MobileShell.xcodeproj/project.pbxproj
git commit -m "feat: connect mosh runtime bridge"
```

### Task 6: Failure UX And Full Verification

**Files:**
- Modify: `docs/product/termius-personal/07-current-state-gap-analysis.md`
- Modify: any Mosh service/store files if wording adjustments are needed

- [ ] **Step 1: Update product progress documentation**

Update `docs/product/termius-personal/07-current-state-gap-analysis.md` so it distinguishes one of two final outcomes:

- `Mosh groundwork only` if Task 5 stops at bridge scaffold
- `Mosh runtime available` if Task 5 completes a real session path

The doc must not claim real runtime support unless end-to-end Mosh session tests actually pass.

- [ ] **Step 2: Run broader verification**

Run: `xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'`

Run: `xcodebuild build -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'`

Expected:

- If real runtime integration is complete, both commands PASS.
- If Task 5 is blocked by lack of embeddable upstream client code, do not claim completion of real runtime; report the boundary honestly and stop at the validated scaffold/preparation layer.

- [ ] **Step 3: Commit**

```bash
git add docs/product/termius-personal/07-current-state-gap-analysis.md
git commit -m "docs: record mosh runtime progress"
```
