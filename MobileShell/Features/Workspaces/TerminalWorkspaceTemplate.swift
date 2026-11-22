import Foundation

struct TerminalWorkspaceTemplate: Identifiable, Equatable, Codable {
    let id: UUID
    var name: String
    var hostIDs: [ShellHost.ID]
    var isBroadcastEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String,
        hostIDs: [ShellHost.ID] = [],
        isBroadcastEnabled: Bool = false
    ) {
        self.id = id
        self.name = name
        self.hostIDs = hostIDs
        self.isBroadcastEnabled = isBroadcastEnabled
    }
}
