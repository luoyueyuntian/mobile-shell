import Foundation

struct MoshServerLaunchResult: Equatable {
    let port: Int
    let key: String
    let serverOutput: String
    let remoteIPAddress: String?

    init(
        port: Int,
        key: String,
        serverOutput: String,
        remoteIPAddress: String? = nil
    ) {
        self.port = port
        self.key = key
        self.serverOutput = serverOutput
        self.remoteIPAddress = remoteIPAddress
    }
}
