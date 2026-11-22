import Foundation

struct MoshHostConfiguration: Equatable, Codable, Sendable {
    var udpPort: Int
    var serverCommand: String
    var predictiveEcho: Bool
    var useExperimentalConnection: Bool
}

extension MoshHostConfiguration {
    static let `default` = MoshHostConfiguration(
        udpPort: 60001,
        serverCommand: "mosh-server new -s",
        predictiveEcho: true,
        useExperimentalConnection: false
    )
}
