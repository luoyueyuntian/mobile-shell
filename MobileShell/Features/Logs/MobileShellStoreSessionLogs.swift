import Foundation

extension MobileShellStore {
    func startSessionLog(for session: TerminalSession) {
        let log = SessionLog(
            hostID: session.hostID,
            hostName: session.hostName,
            lines: session.lines
        )
        sessionLogs.insert(log, at: 0)
        terminalSessionLogIDs[session.id] = log.id
        try? persistSnapshot()
    }

    func appendSessionLogLines(_ lines: [String], for sessionID: TerminalSession.ID) {
        guard !lines.isEmpty,
              let logID = terminalSessionLogIDs[sessionID],
              let index = sessionLogs.firstIndex(where: { $0.id == logID })
        else { return }

        sessionLogs[index].lines.append(contentsOf: lines)
        try? persistSnapshot()
    }

    func closeSessionLog(for sessionID: TerminalSession.ID) {
        guard let logID = terminalSessionLogIDs.removeValue(forKey: sessionID),
              let index = sessionLogs.firstIndex(where: { $0.id == logID })
        else { return }

        if sessionLogs[index].endedAt == nil {
            sessionLogs[index].endedAt = Date()
        }
        try? persistSnapshot()
    }

    func updateSessionLogHostName(_ hostName: String, for sessionID: TerminalSession.ID) {
        guard let logID = terminalSessionLogIDs[sessionID],
              let index = sessionLogs.firstIndex(where: { $0.id == logID })
        else { return }

        sessionLogs[index].hostName = hostName
    }

    func updateSessionLog(
        withID logID: SessionLog.ID,
        _ mutate: (inout SessionLog) -> Void
    ) -> Bool {
        guard let index = sessionLogs.firstIndex(where: { $0.id == logID }) else {
            return false
        }

        mutate(&sessionLogs[index])
        try? persistSnapshot()
        return true
    }

    func updateSessionLog(
        withID logID: SessionLog.ID,
        historyEntry: String? = nil,
        _ mutate: (inout SessionLog) -> Bool
    ) -> Bool {
        guard let index = sessionLogs.firstIndex(where: { $0.id == logID }) else {
            return false
        }

        guard mutate(&sessionLogs[index]) else {
            return false
        }

        if let historyEntry {
            history.insert(historyEntry, at: 0)
        }

        try? persistSnapshot()
        return true
    }

    func persistKnownHostsChange(_ historyEntry: String) {
        history.insert(historyEntry, at: 0)
        try? persistSnapshot()
    }
}
