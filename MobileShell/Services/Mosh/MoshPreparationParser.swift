import Foundation

enum MoshPreparationParser {
    static func parse(_ output: String) throws -> MoshServerLaunchResult {
        if output.localizedCaseInsensitiveContains("mosh-server: command not found") ||
            output.localizedCaseInsensitiveContains("mosh-server not found") {
            throw MoshPreparationError.moshServerMissing
        }

        guard let connectLine = output
            .split(whereSeparator: \.isNewline)
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

        let remoteIPAddress = output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first(where: { $0.hasPrefix("MOSH SSH_CONNECTION ") })
            .flatMap { connectionLine -> String? in
                let connectionParts = connectionLine.split(separator: " ")
                guard connectionParts.count >= 6 else { return nil }
                return String(connectionParts[2])
            }

        return MoshServerLaunchResult(
            port: port,
            key: String(parts[3]),
            serverOutput: output,
            remoteIPAddress: remoteIPAddress
        )
    }
}
