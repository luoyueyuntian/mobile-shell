import Foundation
@testable import MobileShell

final class RecordingShellConnectionClient: ShellConnectionClient {
    var openedHostNames: [String] = []
    var commands: [String] = []

    func openSession(for host: ShellHost) -> TerminalSession {
        openedHostNames.append(host.name)
        return TerminalSession(
            id: UUID(uuidString: "CDCDCDCD-CDCD-CDCD-CDCD-CDCDCDCDCDCD")!,
            hostID: host.id,
            hostName: host.name,
            prompt: "custom$",
            lines: ["custom client connected"]
        )
    }

    func output(for command: String, in session: TerminalSession) -> [String] {
        commands.append(command)
        return ["custom output"]
    }
}

final class RecordingSSHCommandExecutor: SSHCommandExecuting, @unchecked Sendable {
    var commands: [String] = []
    var requests: [SSHConnectionRequest] = []
    var results: [Result<String, Error>]

    init(results: [Result<String, Error>] = [.success("remote-prod\nok")]) {
        self.results = results
    }

    func run(_ command: String, using request: SSHConnectionRequest) async throws -> String {
        commands.append(command)
        requests.append(request)
        let result = nextResult()
        return try result.get()
    }

    private func nextResult() -> Result<String, Error> {
        guard !results.isEmpty else {
            return .success("remote-prod\nok")
        }

        if results.count == 1 {
            return results[0]
        }

        return results.removeFirst()
    }
}

final class RecordingTerminalShellClient: TerminalShellClient, @unchecked Sendable {
    var requests: [SSHConnectionRequest] = []
    var results: [Result<any TerminalShellSession, Error>]

    init(result: Result<any TerminalShellSession, Error>) {
        self.results = [result]
    }

    init(results: [Result<any TerminalShellSession, Error>]) {
        self.results = results
    }

    func openShell(using request: SSHConnectionRequest) async throws -> any TerminalShellSession {
        requests.append(request)
        return try nextResult().get()
    }

    private func nextResult() -> Result<any TerminalShellSession, Error> {
        guard !results.isEmpty else {
            return .failure(RecordingTerminalShellClientError.noResult)
        }

        if results.count == 1 {
            return results[0]
        }

        return results.removeFirst()
    }
}

enum RecordingTerminalShellClientError: Error {
    case noResult
}

final class RecordingTerminalShellSession: TerminalShellSession, @unchecked Sendable {
    let outputStream: AsyncStream<String>
    var sentInputs: [String] = []
    var closeCount = 0

    init(outputs: [String]) {
        outputStream = AsyncStream { continuation in
            for output in outputs {
                continuation.yield(output)
            }
            continuation.finish()
        }
    }

    func send(_ input: String) async throws {
        sentInputs.append(input)
    }

    func close() async {
        closeCount += 1
    }
}

enum RecordingSFTPError: LocalizedError {
    case unreachable

    var errorDescription: String? {
        "SFTP fixture unreachable"
    }
}

enum RecordingSFTPOperation: Equatable {
    case createDirectory(path: String)
    case rename(oldPath: String, newPath: String)
    case deleteFile(path: String)
    case deleteDirectory(path: String)
    case download(path: String)
    case upload(path: String, data: Data)
}

final class RecordingSFTPDirectoryListingClient: SFTPDirectoryListingClient, @unchecked Sendable {
    var paths: [String] = []
    var requests: [SSHConnectionRequest] = []
    var operations: [RecordingSFTPOperation] = []
    var operationRequests: [SSHConnectionRequest] = []
    var results: [Result<[SFTPItem], Error>]
    let operationResult: Result<Void, Error>
    let downloadResult: Result<Data, Error>

    init(
        result: Result<[SFTPItem], Error>,
        operationResult: Result<Void, Error> = .success(()),
        downloadResult: Result<Data, Error> = .success(Data())
    ) {
        self.results = [result]
        self.operationResult = operationResult
        self.downloadResult = downloadResult
    }

    init(
        results: [Result<[SFTPItem], Error>],
        operationResult: Result<Void, Error> = .success(()),
        downloadResult: Result<Data, Error> = .success(Data())
    ) {
        self.results = results
        self.operationResult = operationResult
        self.downloadResult = downloadResult
    }

    func listDirectory(at path: String, using request: SSHConnectionRequest) async throws -> [SFTPItem] {
        paths.append(path)
        requests.append(request)
        return try nextResult().get()
    }

    func createDirectory(at path: String, using request: SSHConnectionRequest) async throws {
        operations.append(.createDirectory(path: path))
        operationRequests.append(request)
        try operationResult.get()
    }

    func renameItem(at oldPath: String, to newPath: String, using request: SSHConnectionRequest) async throws {
        operations.append(.rename(oldPath: oldPath, newPath: newPath))
        operationRequests.append(request)
        try operationResult.get()
    }

    func deleteItem(at path: String, isDirectory: Bool, using request: SSHConnectionRequest) async throws {
        operations.append(isDirectory ? .deleteDirectory(path: path) : .deleteFile(path: path))
        operationRequests.append(request)
        try operationResult.get()
    }

    func downloadFile(at path: String, using request: SSHConnectionRequest) async throws -> Data {
        operations.append(.download(path: path))
        operationRequests.append(request)
        return try downloadResult.get()
    }

    func uploadFile(_ data: Data, to path: String, using request: SSHConnectionRequest) async throws {
        operations.append(.upload(path: path, data: data))
        operationRequests.append(request)
        try operationResult.get()
    }

    private func nextResult() -> Result<[SFTPItem], Error> {
        guard !results.isEmpty else {
            return .success([])
        }

        if results.count == 1 {
            return results[0]
        }

        return results.removeFirst()
    }
}
