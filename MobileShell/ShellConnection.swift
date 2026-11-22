import Foundation
import Citadel
import Crypto
import NIO
import NIOPosix
import NIOSSH

struct SSHConnectionRequest: Equatable, Sendable {
    let hostID: ShellHost.ID
    let displayName: String
    let hostname: String
    let port: Int
    let username: String
    let password: String?
    let privateKey: String?
    let certificate: String?
    let knownHosts: [KnownHost]
    let jumpChain: [SSHConnectionRequest]

    init(
        hostID: ShellHost.ID,
        displayName: String,
        hostname: String,
        port: Int,
        username: String,
        password: String?,
        privateKey: String? = nil,
        certificate: String? = nil,
        knownHosts: [KnownHost] = [],
        jumpChain: [SSHConnectionRequest] = []
    ) {
        self.hostID = hostID
        self.displayName = displayName
        self.hostname = hostname
        self.port = port
        self.username = username
        self.password = password
        self.privateKey = privateKey
        self.certificate = certificate
        self.knownHosts = knownHosts
        self.jumpChain = jumpChain
    }
}

struct SSHConnectionRequestBuilder {
    var credentialVault: CredentialVault?
    var hosts: [ShellHost] = []
    var identities: [SSHIdentity] = []
    var keys: [SSHKey] = []
    var certificates: [SSHCertificate] = []
    var hostGroupProfiles: [HostGroupProfile] = []
    var knownHosts: [KnownHost] = []

    func request(for host: ShellHost) throws -> SSHConnectionRequest {
        try request(for: host, visitedHostIDs: [host.id])
    }

    private func request(for host: ShellHost, visitedHostIDs: Set<ShellHost.ID>) throws -> SSHConnectionRequest {
        let jumpChain = try jumpChain(for: host, visitedHostIDs: visitedHostIDs)
        if let identity = identity(for: host) {
            let keyCredential = try keyCredential(for: identity.sshKeyID)

            return SSHConnectionRequest(
                hostID: host.id,
                displayName: host.name,
                hostname: host.address,
                port: host.port,
                username: identity.username,
                password: try credentialVault?.password(forIdentityID: identity.id),
                privateKey: keyCredential.privateKey,
                certificate: keyCredential.certificate,
                knownHosts: knownHosts.filter { $0.matches(hostname: host.address, port: host.port) },
                jumpChain: jumpChain
            )
        }

        let keyCredential = try keyCredential(for: host.sshKeyID)

        return SSHConnectionRequest(
            hostID: host.id,
            displayName: host.name,
            hostname: host.address,
            port: host.port,
            username: host.username,
            password: try credentialVault?.password(forHostID: host.id),
            privateKey: keyCredential.privateKey,
            certificate: keyCredential.certificate,
            knownHosts: knownHosts.filter { $0.matches(hostname: host.address, port: host.port) },
            jumpChain: jumpChain
        )
    }

    private func jumpChain(for host: ShellHost, visitedHostIDs: Set<ShellHost.ID>) throws -> [SSHConnectionRequest] {
        guard let jumpHostID = jumpHostID(for: host),
              !visitedHostIDs.contains(jumpHostID),
              let jumpHost = hosts.first(where: { $0.id == jumpHostID })
        else {
            return []
        }

        return [
            try request(
                for: jumpHost,
                visitedHostIDs: visitedHostIDs.union([jumpHostID])
            )
        ]
    }

    private func jumpHostID(for host: ShellHost) -> ShellHost.ID? {
        if let jumpHostID = host.jumpHostID {
            return jumpHostID
        }

        return hostGroupProfiles.first {
            $0.name.caseInsensitiveCompare(host.group) == .orderedSame
        }?.jumpHostID
    }

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

    private func keyCredential(for sshKeyID: SSHKey.ID?) throws -> (privateKey: String?, certificate: String?) {
        guard let sshKeyID else {
            return (nil, nil)
        }

        let privateKey = try credentialVault?.privateKey(forKeyID: sshKeyID)
        guard let key = keys.first(where: { $0.id == sshKeyID }),
              let certificateID = key.certificateID,
              certificates.contains(where: { $0.id == certificateID })
        else {
            return (privateKey, nil)
        }

        return (
            privateKey,
            try credentialVault?.certificate(forCertificateID: certificateID)
        )
    }
}

enum LiveShellConnectionError: Error, Equatable, Sendable {
    case missingPassword
    case unsupportedPrivateKeyType(String)
}

struct HostKeyMismatch: Error, Equatable, Sendable {}

protocol SSHCommandExecuting: Sendable {
    func run(_ command: String, using request: SSHConnectionRequest) async throws -> String
}

protocol TerminalShellSession: Sendable {
    var outputStream: AsyncStream<String> { get }
    func send(_ input: String) async throws
    func close() async
}

protocol TerminalShellClient: Sendable {
    func openShell(using request: SSHConnectionRequest) async throws -> any TerminalShellSession
}

struct CitadelCommandExecutor: SSHCommandExecuting {
    func run(_ command: String, using request: SSHConnectionRequest) async throws -> String {
        let client = try await makeSSHClient(using: request)

        do {
            let output = try await client.executeCommand(command)
            try await client.close()
            return String(buffer: output)
        } catch {
            try? await client.close()
            throw error
        }
    }
}

struct CitadelTerminalShellClient: TerminalShellClient {
    func openShell(using request: SSHConnectionRequest) async throws -> any TerminalShellSession {
        let client = try await makeSSHClient(using: request)

        do {
            return try await CitadelTerminalShellSession.start(client: client)
        } catch {
            try? await client.close()
            throw error
        }
    }
}

private enum CitadelTerminalShellSessionError: LocalizedError, Sendable {
    case notReady

    var errorDescription: String? {
        switch self {
        case .notReady:
            "SSH shell is not ready for input"
        }
    }
}

private final class CitadelTerminalShellSession: TerminalShellSession, @unchecked Sendable {
    let outputStream: AsyncStream<String>

    private let outputContinuation: AsyncStream<String>.Continuation
    private let clientBox: SSHClientBox
    private let writerBox: CitadelTTYWriterBox
    private let lifecycleTask: Task<Void, Never>

    private init(
        outputStream: AsyncStream<String>,
        outputContinuation: AsyncStream<String>.Continuation,
        clientBox: SSHClientBox,
        writerBox: CitadelTTYWriterBox,
        lifecycleTask: Task<Void, Never>
    ) {
        self.outputStream = outputStream
        self.outputContinuation = outputContinuation
        self.clientBox = clientBox
        self.writerBox = writerBox
        self.lifecycleTask = lifecycleTask
    }

    static func start(client: SSHClient) async throws -> CitadelTerminalShellSession {
        var outputContinuation: AsyncStream<String>.Continuation!
        let outputStream = AsyncStream<String>(bufferingPolicy: .unbounded) { continuation in
            outputContinuation = continuation
        }
        let clientBox = SSHClientBox(client)
        let writerBox = CitadelTTYWriterBox()
        let startupGate = CitadelTerminalShellStartupGate()
        let streamContinuation = outputContinuation!
        let lifecycleTask = Task { [clientBox, outputContinuation = streamContinuation, writerBox, startupGate] in
            do {
                let request = SSHChannelRequestEvent.PseudoTerminalRequest(
                    wantReply: true,
                    term: "xterm-256color",
                    terminalCharacterWidth: 80,
                    terminalRowHeight: 24,
                    terminalPixelWidth: 0,
                    terminalPixelHeight: 0,
                    terminalModes: SSHTerminalModes([:])
                )

                try await clientBox.client.withPTY(request) { inbound, outbound in
                    writerBox.set(outbound)
                    startupGate.succeed()
                    defer {
                        writerBox.clear()
                    }

                    for try await output in inbound {
                        switch output {
                        case .stdout(let buffer), .stderr(let buffer):
                            let text = String(buffer: buffer)
                            if !text.isEmpty {
                                outputContinuation.yield(text)
                            }
                        }
                    }
                }

                outputContinuation.finish()
            } catch is CancellationError {
                outputContinuation.finish()
            } catch {
                startupGate.fail(error)
                outputContinuation.yield("SSH shell error: \(error.localizedDescription)")
                outputContinuation.finish()
            }

            try? await clientBox.client.close()
        }

        do {
            try await startupGate.wait()
        } catch {
            lifecycleTask.cancel()
            try? await client.close()
            throw error
        }

        return CitadelTerminalShellSession(
            outputStream: outputStream,
            outputContinuation: streamContinuation,
            clientBox: clientBox,
            writerBox: writerBox,
            lifecycleTask: lifecycleTask
        )
    }

    func send(_ input: String) async throws {
        guard let writer = writerBox.current() else {
            throw CitadelTerminalShellSessionError.notReady
        }

        try await writer.write(ByteBuffer(string: input))
    }

    func close() async {
        lifecycleTask.cancel()
        writerBox.clear()
        outputContinuation.finish()
        try? await clientBox.client.close()
    }
}

private final class CitadelTTYWriterBox: @unchecked Sendable {
    private let lock = NSLock()
    private var writer: TTYStdinWriter?

    func set(_ writer: TTYStdinWriter) {
        lock.lock()
        self.writer = writer
        lock.unlock()
    }

    func clear() {
        lock.lock()
        writer = nil
        lock.unlock()
    }

    func current() -> TTYStdinWriter? {
        lock.lock()
        let currentWriter = writer
        lock.unlock()
        return currentWriter
    }
}

private final class CitadelTerminalShellStartupGate: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Void, Error>?
    private var continuations: [CheckedContinuation<Void, Error>] = []

    func wait() async throws {
        try await withCheckedThrowingContinuation { continuation in
            if let result = appendOrReturnResult(for: continuation) {
                continuation.resume(with: result)
            }
        }
    }

    func succeed() {
        complete(.success(()))
    }

    func fail(_ error: Error) {
        complete(.failure(error))
    }

    private func appendOrReturnResult(for continuation: CheckedContinuation<Void, Error>) -> Result<Void, Error>? {
        lock.lock()
        defer { lock.unlock() }

        if let result {
            return result
        }

        continuations.append(continuation)
        return nil
    }

    private func complete(_ result: Result<Void, Error>) {
        lock.lock()
        guard self.result == nil else {
            lock.unlock()
            return
        }
        self.result = result
        let pendingContinuations = continuations
        continuations.removeAll()
        lock.unlock()

        for continuation in pendingContinuations {
            continuation.resume(with: result)
        }
    }
}

protocol SFTPDirectoryListingClient: Sendable {
    func listDirectory(at path: String, using request: SSHConnectionRequest) async throws -> [SFTPItem]
    func createDirectory(at path: String, using request: SSHConnectionRequest) async throws
    func renameItem(at oldPath: String, to newPath: String, using request: SSHConnectionRequest) async throws
    func deleteItem(at path: String, isDirectory: Bool, using request: SSHConnectionRequest) async throws
    func downloadFile(at path: String, using request: SSHConnectionRequest) async throws -> Data
    func uploadFile(_ data: Data, to path: String, using request: SSHConnectionRequest) async throws
}

protocol PortForwardingSession: Sendable {
    func stop() async
}

protocol PortForwardingClient: Sendable {
    func start(rule: PortForwardRule, using request: SSHConnectionRequest) async throws -> any PortForwardingSession
}

enum PortForwardingError: LocalizedError, Sendable {
    case invalidChannelType
    case unsupportedKind(PortForwardKind)

    var errorDescription: String? {
        switch self {
        case .invalidChannelType:
            "Invalid SSH forwarding channel"
        case .unsupportedKind(let kind):
            "\(kind.title) port forwarding is unavailable in this context"
        }
    }
}

struct CitadelPortForwardingClient: PortForwardingClient {
    func start(rule: PortForwardRule, using request: SSHConnectionRequest) async throws -> any PortForwardingSession {
        let client = try await makeSSHClient(using: request)

        do {
            switch rule.kind {
            case .local:
                return try await CitadelPortForwardingSession.startLocal(rule: rule, client: client)
            case .remote:
                return try await CitadelRemotePortForwardingSession.start(rule: rule, client: client)
            case .dynamic:
                return try await CitadelDynamicPortForwardingSession.start(rule: rule, client: client)
            }
        } catch {
            try? await client.close()
            throw error
        }
    }
}

final class CitadelPortForwardingSession: PortForwardingSession, @unchecked Sendable {
    private let client: SSHClient
    private let serverChannel: Channel

    private init(client: SSHClient, serverChannel: Channel) {
        self.client = client
        self.serverChannel = serverChannel
    }

    static func startLocal(rule: PortForwardRule, client: SSHClient) async throws -> CitadelPortForwardingSession {
        let clientBox = SSHClientBox(client)
        let serverChannel = try await ServerBootstrap(group: client.eventLoop, childGroup: client.eventLoop)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.allowRemoteHalfClosure, value: true)
            .childChannelInitializer { inboundChannel in
                let inboundBox = ChannelBox(inboundChannel)
                return inboundChannel.eventLoop.makeFutureWithTask { [clientBox, inboundBox, rule] in
                    let inboundChannel = inboundBox.channel
                    let originatorAddress = try inboundChannel.remoteAddress
                        ?? SocketAddress(ipAddress: "127.0.0.1", port: 0)

                    _ = try await clientBox.client.createDirectTCPIPChannel(
                        using: SSHChannelType.DirectTCPIP(
                            targetHost: rule.remoteHost,
                            targetPort: rule.remotePort,
                            originatorAddress: originatorAddress
                        )
                    ) { sshChannel in
                        let (sshGlue, localGlue) = PortForwardGlueHandler.matchedPair()
                        return sshChannel.pipeline.addHandler(sshGlue).flatMap {
                            inboundChannel.pipeline.addHandler(localGlue)
                        }
                    }
                }
            }
            .bind(host: rule.localHost, port: rule.localPort)
            .get()

        return CitadelPortForwardingSession(client: client, serverChannel: serverChannel)
    }

    func stop() async {
        try? await serverChannel.close()
        try? await client.close()
    }
}

final class CitadelRemotePortForwardingSession: PortForwardingSession, @unchecked Sendable {
    private let client: SSHClient
    private let task: Task<Void, Error>

    private init(client: SSHClient, task: Task<Void, Error>) {
        self.client = client
        self.task = task
    }

    static func start(rule: PortForwardRule, client: SSHClient) async throws -> CitadelRemotePortForwardingSession {
        let clientBox = SSHClientBox(client)
        let startupGate = CitadelPortForwardStartupGate()
        let task = Task { [clientBox, startupGate, rule] in
            do {
                try await clientBox.client.runRemotePortForward(
                    host: rule.remoteHost,
                    port: rule.remotePort,
                    forwardingTo: rule.localHost,
                    port: rule.localPort
                ) { _ in
                    startupGate.succeed()
                }
            } catch {
                startupGate.fail(error)
                throw error
            }
        }

        do {
            try await startupGate.wait()
            return CitadelRemotePortForwardingSession(client: client, task: task)
        } catch {
            task.cancel()
            try? await client.close()
            throw error
        }
    }

    func stop() async {
        task.cancel()
        try? await client.close()
    }
}

private final class CitadelPortForwardStartupGate: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Void, Error>?
    private var continuations: [CheckedContinuation<Void, Error>] = []

    func wait() async throws {
        try await withCheckedThrowingContinuation { continuation in
            if let result = appendOrReturnResult(for: continuation) {
                continuation.resume(with: result)
            }
        }
    }

    func succeed() {
        complete(.success(()))
    }

    func fail(_ error: Error) {
        complete(.failure(error))
    }

    private func appendOrReturnResult(for continuation: CheckedContinuation<Void, Error>) -> Result<Void, Error>? {
        lock.lock()
        defer { lock.unlock() }

        if let result {
            return result
        }

        continuations.append(continuation)
        return nil
    }

    private func complete(_ result: Result<Void, Error>) {
        lock.lock()
        guard self.result == nil else {
            lock.unlock()
            return
        }
        self.result = result
        let pendingContinuations = continuations
        continuations.removeAll()
        lock.unlock()

        for continuation in pendingContinuations {
            continuation.resume(with: result)
        }
    }
}

struct PreviewPortForwardingClient: PortForwardingClient {
    func start(rule: PortForwardRule, using request: SSHConnectionRequest) async throws -> any PortForwardingSession {
        PreviewPortForwardingSession()
    }
}

struct PreviewPortForwardingSession: PortForwardingSession {
    func stop() async {}
}

private final class SSHClientBox: @unchecked Sendable {
    let client: SSHClient

    init(_ client: SSHClient) {
        self.client = client
    }
}

private final class ChannelBox: @unchecked Sendable {
    let channel: Channel

    init(_ channel: Channel) {
        self.channel = channel
    }
}

final class PortForwardGlueHandler: @unchecked Sendable {
    private var partner: PortForwardGlueHandler?
    private var context: ChannelHandlerContext?
    private var pendingRead = false

    private init() {}

    static func matchedPair() -> (PortForwardGlueHandler, PortForwardGlueHandler) {
        let first = PortForwardGlueHandler()
        let second = PortForwardGlueHandler()
        first.partner = second
        second.partner = first
        return (first, second)
    }

    private func partnerWrite(_ data: NIOAny) {
        context?.write(data, promise: nil)
    }

    private func partnerFlush() {
        context?.flush()
    }

    private func partnerWriteEOF() {
        context?.close(mode: .output, promise: nil)
    }

    private func partnerCloseFull() {
        context?.close(promise: nil)
    }

    private func partnerBecameWritable() {
        if pendingRead {
            pendingRead = false
            context?.read()
        }
    }

    private var partnerWritable: Bool {
        context?.channel.isWritable ?? false
    }
}

extension PortForwardGlueHandler: ChannelDuplexHandler {
    typealias InboundIn = NIOAny
    typealias OutboundIn = NIOAny
    typealias OutboundOut = NIOAny

    func handlerAdded(context: ChannelHandlerContext) {
        self.context = context

        if context.channel.isWritable {
            partner?.partnerBecameWritable()
        }
    }

    func handlerRemoved(context: ChannelHandlerContext) {
        self.context = nil
        self.partner = nil
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        partner?.partnerWrite(data)
    }

    func channelReadComplete(context: ChannelHandlerContext) {
        partner?.partnerFlush()
    }

    func channelInactive(context: ChannelHandlerContext) {
        partner?.partnerCloseFull()
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if let event = event as? ChannelEvent, case .inputClosed = event {
            partner?.partnerWriteEOF()
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        partner?.partnerCloseFull()
    }

    func channelWritabilityChanged(context: ChannelHandlerContext) {
        if context.channel.isWritable {
            partner?.partnerBecameWritable()
        }
    }

    func read(context: ChannelHandlerContext) {
        if let partner, partner.partnerWritable {
            context.read()
        } else {
            pendingRead = true
        }
    }
}

struct CitadelSFTPDirectoryListingClient: SFTPDirectoryListingClient {
    func listDirectory(at path: String, using request: SSHConnectionRequest) async throws -> [SFTPItem] {
        let client = try await makeSSHClient(using: request)

        do {
            let items = try await client.withSFTP { sftp in
                let names = try await sftp.listDirectory(atPath: path)
                return names
                    .flatMap(\.components)
                    .filter { $0.filename != "." && $0.filename != ".." }
                    .map(Self.item(from:))
            }
            try await client.close()
            return items
        } catch {
            try? await client.close()
            throw error
        }
    }

    func createDirectory(at path: String, using request: SSHConnectionRequest) async throws {
        try await withSFTP(using: request) { sftp in
            try await sftp.createDirectory(atPath: path)
        }
    }

    func renameItem(at oldPath: String, to newPath: String, using request: SSHConnectionRequest) async throws {
        try await withSFTP(using: request) { sftp in
            try await sftp.rename(at: oldPath, to: newPath)
        }
    }

    func deleteItem(at path: String, isDirectory: Bool, using request: SSHConnectionRequest) async throws {
        try await withSFTP(using: request) { sftp in
            if isDirectory {
                try await sftp.rmdir(at: path)
            } else {
                try await sftp.remove(at: path)
            }
        }
    }

    func downloadFile(at path: String, using request: SSHConnectionRequest) async throws -> Data {
        try await withSFTP(using: request) { sftp in
            try await sftp.withFile(filePath: path, flags: .read) { file in
                let buffer = try await file.readAll()
                return Data(buffer.readableBytesView)
            }
        }
    }

    func uploadFile(_ data: Data, to path: String, using request: SSHConnectionRequest) async throws {
        let bytes = [UInt8](data)
        try await withSFTP(using: request) { sftp in
            try await sftp.withFile(filePath: path, flags: [.write, .create, .truncate]) { file in
                var buffer = ByteBuffer()
                buffer.writeBytes(bytes)
                try await file.write(buffer)
            }
        }
    }

    private static func item(from component: SFTPPathComponent) -> SFTPItem {
        SFTPItem(
            id: UUID(),
            name: component.filename,
            kind: kind(for: component),
            size: sizeText(for: component.attributes.size)
        )
    }

    private static func kind(for component: SFTPPathComponent) -> String {
        if isDirectory(component) {
            return "folder"
        }

        let lowercasedName = component.filename.lowercased()
        if lowercasedName.hasSuffix(".sh") || lowercasedName.hasSuffix(".bash") || lowercasedName.hasSuffix(".zsh") {
            return "shell"
        }
        if lowercasedName.hasSuffix(".zip") || lowercasedName.hasSuffix(".tar") || lowercasedName.hasSuffix(".gz") {
            return "archive"
        }
        return "text"
    }

    private static func isDirectory(_ component: SFTPPathComponent) -> Bool {
        if let permissions = component.attributes.permissions {
            return permissions & 0o170000 == 0o040000
        }
        return component.longname.hasPrefix("d")
    }

    private static func sizeText(for size: UInt64?) -> String {
        guard let size else { return "--" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }

    private func withSFTP<Result>(
        using request: SSHConnectionRequest,
        operation: @escaping @Sendable (SFTPClient) async throws -> Result
    ) async throws -> Result {
        let client = try await makeSSHClient(using: request)

        do {
            let result = try await client.withSFTP { sftp in
                try await operation(sftp)
            }
            try await client.close()
            return result
        } catch {
            try? await client.close()
            throw error
        }
    }
}

struct PreviewSFTPDirectoryListingClient: SFTPDirectoryListingClient {
    func listDirectory(at path: String, using request: SSHConnectionRequest) async throws -> [SFTPItem] {
        [
            SFTPItem(id: UUID(), name: "backup", kind: "folder", size: "--"),
            SFTPItem(id: UUID(), name: "deploy.sh", kind: "shell", size: "4 KB"),
            SFTPItem(id: UUID(), name: "app_start_logs.txt", kind: "text", size: "28 KB"),
            SFTPItem(id: UUID(), name: "catalog_archive.tar", kind: "archive", size: "1.2 GB")
        ]
    }

    func createDirectory(at path: String, using request: SSHConnectionRequest) async throws {}

    func renameItem(at oldPath: String, to newPath: String, using request: SSHConnectionRequest) async throws {}

    func deleteItem(at path: String, isDirectory: Bool, using request: SSHConnectionRequest) async throws {}

    func downloadFile(at path: String, using request: SSHConnectionRequest) async throws -> Data {
        Data("Preview download from \(path)".utf8)
    }

    func uploadFile(_ data: Data, to path: String, using request: SSHConnectionRequest) async throws {}
}

func makeSSHClient(using request: SSHConnectionRequest) async throws -> SSHClient {
    return try await SSHClient.connect(
        host: request.hostname,
        port: request.port,
        authenticationMethod: try authenticationMethod(for: request),
        hostKeyValidator: hostKeyValidator(for: request),
        reconnect: .never
    )
}

func hostKeyValidator(for request: SSHConnectionRequest) -> SSHHostKeyValidator {
    return .custom(KnownHostsValidator(policy: SSHHostKeyPolicy(
        hostname: request.hostname,
        port: request.port,
        knownHosts: request.knownHosts
    )))
}

enum HostKeyEvaluation: Equatable, Sendable {
    case trusted
    case challenge(HostKeyChallenge)
    case mismatch

    var hostKeyChallenge: HostKeyChallenge? {
        guard case let .challenge(challenge) = self else { return nil }
        return challenge
    }
}

struct SSHHostKeyPolicy: Equatable, Sendable {
    let hostname: String
    let port: Int
    let knownHosts: [KnownHost]

    func evaluate(keyType: String, fingerprint: String) -> HostKeyEvaluation {
        let normalizedKeyType = keyType.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedFingerprint = normalizedSHA256Fingerprint(fingerprint)
        let matchingKnownHosts = knownHosts.filter {
            $0.matches(hostname: hostname, port: port) &&
                $0.keyType.caseInsensitiveCompare(normalizedKeyType) == .orderedSame
        }

        guard !matchingKnownHosts.isEmpty else {
            return .challenge(HostKeyChallenge(
                hostname: hostname,
                port: port,
                keyType: normalizedKeyType,
                fingerprint: normalizedFingerprint
            ))
        }

        if matchingKnownHosts.contains(where: {
            normalizedSHA256Fingerprint($0.fingerprint) == normalizedFingerprint
        }) {
            return .trusted
        }

        return .mismatch
    }

    func trusts(keyType: String, fingerprint: String) -> Bool {
        evaluate(keyType: keyType, fingerprint: fingerprint) == .trusted
    }
}

final class KnownHostsValidator: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    let policy: SSHHostKeyPolicy

    init(policy: SSHHostKeyPolicy) {
        self.policy = policy
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        switch policy.evaluate(keyType: sshKeyType(for: hostKey), fingerprint: sshSHA256Fingerprint(for: hostKey)) {
        case .trusted:
            validationCompletePromise.succeed(())
        case let .challenge(challenge):
            validationCompletePromise.fail(challenge)
        case .mismatch:
            validationCompletePromise.fail(HostKeyMismatch())
        }
    }
}

func sshKeyType(for hostKey: NIOSSHPublicKey) -> String {
    String(String(openSSHPublicKey: hostKey).split(separator: " ").first ?? "")
}

func sshSHA256Fingerprint(for hostKey: NIOSSHPublicKey) -> String {
    var buffer = ByteBuffer()
    hostKey.write(to: &buffer)
    let digest = SHA256.hash(data: Data(buffer.readableBytesView))
    var encodedDigest = Data(digest).base64EncodedString()
    while encodedDigest.hasSuffix("=") {
        encodedDigest.removeLast()
    }
    return "SHA256:\(encodedDigest)"
}

func normalizedSHA256Fingerprint(_ fingerprint: String) -> String {
    var normalized = fingerprint.trimmingCharacters(in: .whitespacesAndNewlines)
    while normalized.hasSuffix("=") {
        normalized.removeLast()
    }
    return normalized
}

private func authenticationMethod(for request: SSHConnectionRequest) throws -> SSHAuthenticationMethod {
    if let privateKey = request.privateKey?.trimmingCharacters(in: .whitespacesAndNewlines),
       !privateKey.isEmpty {
        let keyType = try SSHKeyDetection.detectPrivateKeyType(from: privateKey)
        if keyType == .ed25519 {
            return try .ed25519(
                username: request.username,
                privateKey: Curve25519.Signing.PrivateKey(sshEd25519: privateKey)
            )
        }
        if keyType == .rsa {
            return try .rsa(
                username: request.username,
                privateKey: Insecure.RSA.PrivateKey(sshRsa: privateKey)
            )
        }
        throw LiveShellConnectionError.unsupportedPrivateKeyType(keyType.rawValue)
    }

    guard let password = request.password, !password.isEmpty else {
        throw LiveShellConnectionError.missingPassword
    }

    return .passwordBased(username: request.username, password: password)
}

protocol ShellConnectionClient {
    func openSession(for host: ShellHost) -> TerminalSession
    func output(for command: String, in session: TerminalSession) -> [String]
}

struct PreviewShellConnectionClient: ShellConnectionClient {
    func openSession(for host: ShellHost) -> TerminalSession {
        TerminalSession(
            id: UUID(),
            hostID: host.id,
            hostName: host.name,
            prompt: "\(host.username)@\(host.name):~$",
            lines: [
                "Connecting to \(host.address):\(host.port)...",
                "Connected to \(host.name) as \(host.username)",
                "Vault credential unlocked with Face ID",
                "Last login: Fri Jun 19 10:24:03 from MobileShell"
            ]
        )
    }

    func output(for command: String, in session: TerminalSession) -> [String] {
        switch command.lowercased() {
        case "uptime":
            ["10:26 up 42 days, 3 users, load average: 0.28, 0.31, 0.25"]
        case "df -h":
            [
                "Filesystem      Size  Used Avail Use% Mounted on",
                "/dev/root        78G   39G   36G  52% /",
                "tmpfs           2.0G  4.0M  2.0G   1% /run"
            ]
        case "whoami":
            [session.prompt.split(separator: "@").first.map(String.init) ?? "deploy"]
        default:
            ["Command queued in preview terminal: \(command)", "Exit status: 0"]
        }
    }
}

struct PreviewTerminalShellClient: TerminalShellClient {
    func openShell(using request: SSHConnectionRequest) async throws -> any TerminalShellSession {
        PreviewTerminalShellSession(request: request)
    }
}

final class PreviewTerminalShellSession: TerminalShellSession, @unchecked Sendable {
    let outputStream: AsyncStream<String>
    private let continuation: AsyncStream<String>.Continuation

    init(request: SSHConnectionRequest) {
        var streamContinuation: AsyncStream<String>.Continuation!
        outputStream = AsyncStream { continuation in
            streamContinuation = continuation
        }
        continuation = streamContinuation
        continuation.yield("Interactive preview shell opened for \(request.displayName)")
        continuation.yield("\(request.username)@\(request.displayName):~$")
    }

    func send(_ input: String) async throws {
        let command = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        continuation.yield("Preview shell executed: \(command)")
        continuation.yield("Exit status: 0")
    }

    func close() async {
        continuation.finish()
    }
}
