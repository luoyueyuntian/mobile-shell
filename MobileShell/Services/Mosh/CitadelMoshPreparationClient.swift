import Foundation
import Citadel
import NIO

struct CitadelMoshPreparationClient: MoshPreparationClient {
    func prepare(
        using request: SSHConnectionRequest,
        configuration: MoshHostConfiguration
    ) async throws -> MoshServerLaunchResult {
        let client = try await makeSSHClient(using: request)
        let command = MoshPreparationCommandBuilder.command(for: configuration)
        var capturedOutput = ""

        do {
            capturedOutput = try await captureInitialOutput(from: client, command: command)

            do {
                try await client.close()
            } catch {
                if capturedOutput.isEmpty || error.localizedDescription != "Already closed" {
                    throw error
                }
            }

            return try MoshPreparationParser.parse(capturedOutput)
        } catch {
            try? await client.close()
            throw error
        }
    }

    private func captureInitialOutput(from client: SSHClient, command: String) async throws -> String {
        return String(
            buffer: try await client.executeCommand(
                command,
                maxResponseSize: 4_096,
                mergeStreams: true
            )
        )
    }
}
