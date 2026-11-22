import Foundation

struct MoshTerminalConnector {
    var credentialVault: CredentialVault?
    var hosts: [ShellHost]
    var identities: [SSHIdentity]
    var keys: [SSHKey]
    var certificates: [SSHCertificate]
    var hostGroupProfiles: [HostGroupProfile]
    var knownHosts: [KnownHost]
    var preparationClient: any MoshPreparationClient
    var runtimeClient: any MoshRuntimeClient

    @MainActor
    func connect(
        host: ShellHost,
        configuration: MoshHostConfiguration
    ) async throws -> any MoshRuntimeSession {
        let request = try SSHConnectionRequestBuilder(
            credentialVault: credentialVault,
            hosts: hosts,
            identities: identities,
            keys: keys,
            certificates: certificates,
            hostGroupProfiles: hostGroupProfiles,
            knownHosts: knownHosts
        ).request(for: host)

        let launchResult = try await preparationClient.prepare(using: request, configuration: configuration)
        return try await runtimeClient.connect(host: host, launchResult: launchResult)
    }

    static func userFacingMessage(for error: Error) -> String {
        switch error {
        case let error as MoshPreparationError:
            switch error {
            case .moshServerMissing:
                return "Mosh is configured for this host, but `mosh-server` is not installed on the remote machine. Install `mosh` on the server and try again."
            case .moshServerLaunchFailed(let output):
                return "Mosh server failed to start: \(output)"
            case .moshHandshakeParseFailed:
                return "Mosh server started, but the handshake response could not be parsed."
            }
        case let error as MoshRuntimeError:
            switch error {
            case .connectFailed(let message):
                return "Mosh connection failed: \(message)"
            }
        default:
            return "Mosh connection failed: \(error.localizedDescription)"
        }
    }
}
