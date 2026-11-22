import Foundation

protocol MoshPreparationClient: Sendable {
    func prepare(
        using request: SSHConnectionRequest,
        configuration: MoshHostConfiguration
    ) async throws -> MoshServerLaunchResult
}
