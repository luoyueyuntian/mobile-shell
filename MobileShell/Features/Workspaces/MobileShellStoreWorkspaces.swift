import Foundation

extension MobileShellStore {
    @discardableResult
    func createTerminalWorkspace(name: String) -> TerminalWorkspace? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }

        let workspace = TerminalWorkspace(name: trimmedName)
        terminalWorkspaces.append(workspace)
        selectedWorkspaceID = workspace.id
        selectedSessionID = nil
        commandInput = ""
        history.insert("Created workspace \(workspace.name)", at: 0)
        try? persistSnapshot()
        return workspace
    }

    func selectTerminalWorkspace(_ workspaceID: TerminalWorkspace.ID?) {
        guard let workspaceID else {
            selectedWorkspaceID = nil
            if selectedSessionID == nil, let firstSession = terminalSessions.first {
                selectTerminalSession(firstSession.id)
            }
            return
        }

        guard terminalWorkspaces.contains(where: { $0.id == workspaceID }) else { return }
        selectedWorkspaceID = workspaceID
        let visibleSessions = visibleTerminalSessions()
        if let selectedSessionID,
           visibleSessions.contains(where: { $0.id == selectedSessionID }) {
            return
        }

        if let firstSession = visibleSessions.first {
            selectTerminalSession(firstSession.id)
        } else {
            selectedSessionID = nil
            commandInput = ""
        }
    }

    func visibleTerminalSessions() -> [TerminalSession] {
        guard let selectedWorkspaceID,
              let workspace = terminalWorkspaces.first(where: { $0.id == selectedWorkspaceID })
        else { return terminalSessions }

        let workspaceSessionIDs = Set(workspace.sessionIDs)
        return terminalSessions.filter { workspaceSessionIDs.contains($0.id) }
    }

    func terminalSessionCount(for workspace: TerminalWorkspace) -> Int {
        let workspaceSessionIDs = Set(workspace.sessionIDs)
        return terminalSessions.filter { workspaceSessionIDs.contains($0.id) }.count
    }

    func setBroadcastEnabled(_ isEnabled: Bool, for workspaceID: TerminalWorkspace.ID) {
        guard let index = terminalWorkspaces.firstIndex(where: { $0.id == workspaceID }) else { return }
        terminalWorkspaces[index].isBroadcastEnabled = isEnabled
        try? persistSnapshot()
    }

    @discardableResult
    func saveSelectedWorkspaceAsTemplate(name: String) -> TerminalWorkspaceTemplate? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              let workspace = selectedTerminalWorkspace
        else { return nil }

        var seenHostIDs = Set<ShellHost.ID>()
        let hostIDs = visibleTerminalSessions().compactMap { session -> ShellHost.ID? in
            guard seenHostIDs.insert(session.hostID).inserted else { return nil }
            return session.hostID
        }
        guard !hostIDs.isEmpty else { return nil }

        let template = TerminalWorkspaceTemplate(
            name: trimmedName,
            hostIDs: hostIDs,
            isBroadcastEnabled: workspace.isBroadcastEnabled
        )
        terminalWorkspaceTemplates.append(template)
        history.insert("Saved workspace template \(template.name)", at: 0)
        try? persistSnapshot()
        return template
    }

    @discardableResult
    func openWorkspaceTemplate(_ template: TerminalWorkspaceTemplate) -> TerminalWorkspace? {
        let trimmedName = template.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let workspace = createTerminalWorkspace(name: trimmedName) else { return nil }

        setBroadcastEnabled(template.isBroadcastEnabled, for: workspace.id)
        var openedHostIDs = Set<ShellHost.ID>()
        for hostID in template.hostIDs where openedHostIDs.insert(hostID).inserted {
            guard let host = hosts.first(where: { $0.id == hostID }) else { continue }
            connect(to: host)
        }

        history.insert("Opened workspace template \(trimmedName)", at: 0)
        try? persistSnapshot()
        return terminalWorkspaces.first { $0.id == workspace.id }
    }

    func deleteWorkspaceTemplate(_ template: TerminalWorkspaceTemplate) {
        terminalWorkspaceTemplates.removeAll { $0.id == template.id }
        try? persistSnapshot()
    }

    func templateHostNames(for template: TerminalWorkspaceTemplate) -> [String] {
        template.hostIDs.compactMap { hostID in
            hosts.first { $0.id == hostID }?.name
        }
    }

    func assignTerminalSessionToSelectedWorkspace(_ sessionID: TerminalSession.ID) {
        guard let selectedWorkspaceID,
              let index = terminalWorkspaces.firstIndex(where: { $0.id == selectedWorkspaceID }),
              !terminalWorkspaces[index].sessionIDs.contains(sessionID)
        else { return }

        terminalWorkspaces[index].sessionIDs.append(sessionID)
    }

    func removeTerminalSessionFromWorkspaces(_ sessionID: TerminalSession.ID) {
        for index in terminalWorkspaces.indices {
            terminalWorkspaces[index].sessionIDs.removeAll { $0 == sessionID }
        }
    }
}
