import Foundation

enum MoshPreparationCommandBuilder {
    static func command(for configuration: MoshHostConfiguration) -> String {
        let serverCommand = "\(configuration.serverCommand) -p \(configuration.udpPort)"
        return configuration.useExperimentalConnection
            ? "echo \"MOSH SSH_CONNECTION $SSH_CONNECTION\" && \(serverCommand)"
            : serverCommand
    }
}

struct SSHMoshPreparationClient: MoshPreparationClient {
    let commandExecutor: any SSHCommandExecuting

    init(commandExecutor: any SSHCommandExecuting) {
        self.commandExecutor = commandExecutor
    }

    func prepare(
        using request: SSHConnectionRequest,
        configuration: MoshHostConfiguration
    ) async throws -> MoshServerLaunchResult {
        let command = MoshPreparationCommandBuilder.command(for: configuration)
        let output = try await commandExecutor.run(command, using: request)
        return try MoshPreparationParser.parse(output)
    }
}
