import Foundation

protocol MoshBridgeSessionControlling: AnyObject, Sendable {
    func startSession(
        outputHandler: @escaping @Sendable (String) -> Void,
        exitHandler: @escaping @Sendable (String?) -> Void
    ) throws
    func sendBridgeInput(_ input: String) throws
    func closeBridgeSession()
}

struct MoshBridgeConnectionOptions: Equatable, Sendable {
    let host: String
    let port: String
    let key: String
    let predictionMode: String
    let localesBundlePath: String
    let predictOverwrite: String?
}

typealias MoshBridgeSessionFactory = @Sendable (MoshBridgeConnectionOptions) throws -> any MoshBridgeSessionControlling

final class MoshRuntimeClientBridge: MoshRuntimeClient {
    let adapter: MoshClientBridgeAdapter
    private let sessionFactory: MoshBridgeSessionFactory

    init(
        adapter: MoshClientBridgeAdapter = MoshClientBridgeAdapter(),
        sessionFactory: MoshBridgeSessionFactory? = nil
    ) {
        self.adapter = adapter
        self.sessionFactory = sessionFactory ?? Self.makeSessionController
    }

    var isBinaryLinked: Bool {
        MoshClientBridgeAdapter.isMoshBinaryLinked()
    }

    var localesBundleURL: URL? {
        Bundle.main.url(forResource: "locales", withExtension: "bundle")
    }

    func connect(
        host: ShellHost,
        launchResult: MoshServerLaunchResult
    ) async throws -> any MoshRuntimeSession {
        let options = try Self.makeConnectionOptions(
            host: host,
            launchResult: launchResult,
            localesBundleURL: localesBundleURL
        )
        let controller = try sessionFactory(options)
        let session = MoshBridgeRuntimeSession(controller: controller)
        try session.start()
        return session
    }

    private static func makeConnectionOptions(
        host: ShellHost,
        launchResult: MoshServerLaunchResult,
        localesBundleURL: URL?
    ) throws -> MoshBridgeConnectionOptions {
        guard MoshClientBridgeAdapter.isMoshBinaryLinked() else {
            throw MoshRuntimeError.connectFailed("Mosh binary is not linked into this build.")
        }

        guard let localesBundleURL else {
            throw MoshRuntimeError.connectFailed("Mosh locale resources are missing from the app bundle.")
        }

        let predictionMode = (host.moshConfiguration?.predictiveEcho ?? true) ? "adaptive" : "never"

        return MoshBridgeConnectionOptions(
            host: launchResult.remoteIPAddress ?? host.address,
            port: String(launchResult.port),
            key: launchResult.key,
            predictionMode: predictionMode,
            localesBundlePath: localesBundleURL.path,
            predictOverwrite: nil
        )
    }

    private static func makeSessionController(
        options: MoshBridgeConnectionOptions
    ) throws -> any MoshBridgeSessionControlling {
        MoshClientBridgeAdapter(
            host: options.host,
            port: options.port,
            key: options.key,
            predictionMode: options.predictionMode,
            localesBundlePath: options.localesBundlePath,
            predictOverwrite: options.predictOverwrite
        )
    }
}

extension MoshClientBridgeAdapter: @unchecked Sendable {}

extension MoshClientBridgeAdapter: MoshBridgeSessionControlling {
    func startSession(
        outputHandler: @escaping @Sendable (String) -> Void,
        exitHandler: @escaping @Sendable (String?) -> Void
    ) throws {
        try start(outputHandler: outputHandler, exitHandler: exitHandler)
    }

    func sendBridgeInput(_ input: String) throws {
        try send(input: input)
    }

    func closeBridgeSession() {
        closeSession()
    }
}

private final class MoshBridgeRuntimeSession: MoshRuntimeSession, @unchecked Sendable {
    let outputStream: AsyncStream<String>

    private let continuation: AsyncStream<String>.Continuation
    private let controller: any MoshBridgeSessionControlling

    init(controller: any MoshBridgeSessionControlling) {
        self.controller = controller

        var capturedContinuation: AsyncStream<String>.Continuation!
        self.outputStream = AsyncStream<String>(bufferingPolicy: .unbounded) { continuation in
            capturedContinuation = continuation
        }
        self.continuation = capturedContinuation
    }

    func start() throws {
        try controller.startSession(
            outputHandler: { [continuation] output in
                continuation.yield(output)
            },
            exitHandler: { [continuation] message in
                if let message, !message.isEmpty {
                    continuation.yield(message)
                }
                continuation.finish()
            }
        )
    }

    func send(_ input: String) async throws {
        try controller.sendBridgeInput(input)
    }

    func close() async {
        controller.closeBridgeSession()
        continuation.finish()
    }
}
