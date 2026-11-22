import Foundation

struct TerminalWorkspace: Identifiable, Equatable, Codable {
    let id: UUID
    var name: String
    var sessionIDs: [TerminalSession.ID]
    var isBroadcastEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String,
        sessionIDs: [TerminalSession.ID] = [],
        isBroadcastEnabled: Bool = false
    ) {
        self.id = id
        self.name = name
        self.sessionIDs = sessionIDs
        self.isBroadcastEnabled = isBroadcastEnabled
    }
}
