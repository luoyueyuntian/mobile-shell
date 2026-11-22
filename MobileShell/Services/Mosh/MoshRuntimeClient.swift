import Foundation

protocol MoshRuntimeClient: Sendable {
    func connect(
        host: ShellHost,
        launchResult: MoshServerLaunchResult
    ) async throws -> any MoshRuntimeSession
}
