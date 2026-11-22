import Foundation

extension MobileShellStore {
    @discardableResult
    func connect(to host: ShellHost) -> TerminalSession.ID? {
        connect(to: host, runStartupSnippet: true)
    }

    var moshTerminalConnector: MoshTerminalConnector? {
        guard let moshPreparationClient,
              let moshRuntimeClient else {
            return nil
        }

        return MoshTerminalConnector(
            credentialVault: credentialVault,
            hosts: hosts,
            identities: identities,
            keys: keys,
            certificates: certificates,
            hostGroupProfiles: hostGroupProfiles,
            knownHosts: knownHosts,
            preparationClient: moshPreparationClient,
            runtimeClient: moshRuntimeClient
        )
    }

    @discardableResult
    func connect(
        to host: ShellHost,
        runStartupSnippet: Bool,
        allowMosh: Bool = false
    ) -> TerminalSession.ID? {
        terminalUnavailableMessage = nil

        if host.`protocol` == .mosh && !allowMosh {
            terminalUnavailableMessage = Self.terminalUnavailableMoshMessage
            return nil
        }

        let sessionID: TerminalSession.ID
        let openedNewSession: Bool

        if let existingIndex = terminalSessions.firstIndex(where: { $0.hostID == host.id }) {
            sessionID = terminalSessions[existingIndex].id
            openedNewSession = false
            selectTerminalSession(sessionID)
            assignTerminalSessionToSelectedWorkspace(sessionID)
        } else {
            let session = connectionClient.openSession(for: host)
            terminalSessions.append(session)
            startSessionLog(for: session)
            selectTerminalSession(session.id)
            assignTerminalSessionToSelectedWorkspace(session.id)
            sessionID = session.id
            openedNewSession = true
        }

        selectedSection = .terminals
        if openedNewSession {
            history.insert("Connected to \(host.name)", at: 0)
            cacheConnectionRequest(for: host)
            if runStartupSnippet {
                runEnvironmentVariableExportsPreview(for: host, in: sessionID)
                runStartupSnippetPreview(for: host, in: sessionID)
            }
        }
        try? persistSnapshot()
        return sessionID
    }

    @MainActor
    func exportEnvironmentVariablesIfNeeded(for host: ShellHost, in sessionID: TerminalSession.ID) async {
        for variable in environmentVariables(for: host) {
            await sendRemoteCommand(variable.exportCommand, in: sessionID, recordHistory: false, clearDraft: false)
        }
    }

    @MainActor
    func runStartupSnippetIfNeeded(for host: ShellHost, in sessionID: TerminalSession.ID) async {
        guard let snippet = startupSnippet(for: host) else { return }
        let command = snippet.command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }

        await sendRemoteCommand(command, in: sessionID, recordHistory: false, clearDraft: false)
        history.insert("Ran startup snippet \(snippet.title) on \(host.name)", at: 0)
        try? persistSnapshot()
    }

    func updateOpenTerminalSessions(for host: ShellHost) {
        for index in terminalSessions.indices where terminalSessions[index].hostID == host.id {
            terminalSessions[index].hostName = host.name
            terminalSessions[index].prompt = "\(host.username)@\(host.name):~$"
            terminalConnectionRequests[terminalSessions[index].id] = try? SSHConnectionRequestBuilder(
                credentialVault: credentialVault,
                hosts: hosts,
                identities: identities,
                keys: keys,
                certificates: certificates,
                hostGroupProfiles: hostGroupProfiles,
                knownHosts: knownHosts
            ).request(for: host)
            updateSessionLogHostName(host.name, for: terminalSessions[index].id)
        }
    }

    func clearTerminalState(forHostID hostID: ShellHost.ID) {
        let removedSessionIDs = terminalSessions
            .filter { $0.hostID == hostID }
            .map(\.id)

        terminalSessions.removeAll { $0.hostID == hostID }
        for sessionID in removedSessionIDs {
            stopTerminalShell(for: sessionID)
            terminalConnectionRequests[sessionID] = nil
            closeSessionLog(for: sessionID)
            removeTerminalSessionFromWorkspaces(sessionID)
        }

        if let selectedSessionID, removedSessionIDs.contains(selectedSessionID) {
            if let replacementSession = visibleTerminalSessions().first {
                selectTerminalSession(replacementSession.id)
            } else {
                self.selectedSessionID = nil
                commandInput = ""
            }
        }
    }
}
