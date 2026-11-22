import Foundation

extension MobileShellStore {
    @MainActor
    func openInteractiveTerminal(for host: ShellHost) async {
        let hadSession = terminalSessions.contains { $0.hostID == host.id }
        let existingSessionID = terminalSessions.first(where: { $0.hostID == host.id })?.id
        let hadLiveShell = existingSessionID.flatMap { activeTerminalShellSessions[$0] } != nil

        let sessionID: TerminalSession.ID?
        if host.`protocol` == .mosh {
            sessionID = await openMoshTerminal(for: host)
        } else {
            sessionID = connect(to: host, runStartupSnippet: false)
            if let sessionID {
                await startTerminalShell(for: sessionID)
            }
        }

        guard let sessionID else { return }
        guard !hadSession,
              !hadLiveShell,
              activeTerminalShellSessions[sessionID] != nil
        else { return }
        await exportEnvironmentVariablesIfNeeded(for: host, in: sessionID)
        await runStartupSnippetIfNeeded(for: host, in: sessionID)
    }

    @MainActor
    func reconnectTerminalSession(_ sessionID: TerminalSession.ID) {
        guard let index = terminalSessions.firstIndex(where: { $0.id == sessionID }),
              let host = hosts.first(where: { $0.id == terminalSessions[index].hostID })
        else { return }

        terminalUnavailableMessage = nil
        if host.`protocol` == .mosh {
            guard host.moshConfiguration != nil,
                  moshPreparationClient != nil,
                  moshRuntimeClient != nil else {
                terminalUnavailableMessage = Self.terminalUnavailableMoshMessage
                terminalConnectionRequests[sessionID] = nil
                return
            }

            terminalSessions[index].state = .reconnecting
            terminalSessions[index].prompt = "\(host.username)@\(host.name):~$"
            stopTerminalShell(for: sessionID)

            Task { @MainActor in
                let reconnectedSessionID = await self.openMoshTerminal(for: host)
                guard let reconnectedSessionID,
                      self.activeTerminalShellSessions[reconnectedSessionID] != nil
                else {
                    if let disconnectedIndex = self.terminalSessions.firstIndex(where: { $0.id == sessionID }) {
                        self.terminalSessions[disconnectedIndex].state = .disconnected
                    }
                    return
                }

                if let reconnectedIndex = self.terminalSessions.firstIndex(where: { $0.id == reconnectedSessionID }) {
                    self.terminalSessions[reconnectedIndex].state = .connected
                    let line = "Reconnected to \(host.name)"
                    self.terminalSessions[reconnectedIndex].lines.append(line)
                    self.appendSessionLogLines([line], for: reconnectedSessionID)
                }

                self.history.insert("Reconnected terminal \(host.name)", at: 0)
                try? self.persistSnapshot()
            }
            return
        }

        terminalSessions[index].state = .reconnecting
        terminalSessions[index].prompt = "\(host.username)@\(host.name):~$"
        terminalConnectionRequests[sessionID] = try? SSHConnectionRequestBuilder(
            credentialVault: credentialVault,
            hosts: hosts,
            identities: identities,
            keys: keys,
            certificates: certificates,
            hostGroupProfiles: hostGroupProfiles,
            knownHosts: knownHosts
        ).request(for: host)
        terminalSessions[index].state = .connected
        let line = "Reconnected to \(host.name)"
        terminalSessions[index].lines.append(line)
        appendSessionLogLines([line], for: sessionID)
        history.insert("Reconnected terminal \(host.name)", at: 0)
        try? persistSnapshot()
    }

    @MainActor
    private func openMoshTerminal(for host: ShellHost) async -> TerminalSession.ID? {
        terminalUnavailableMessage = nil

        if let existingSession = terminalSessions.first(where: { $0.hostID == host.id }),
           activeTerminalShellSessions[existingSession.id] != nil {
            selectTerminalSession(existingSession.id)
            assignTerminalSessionToSelectedWorkspace(existingSession.id)
            selectedSection = .terminals
            return existingSession.id
        }

        guard let configuration = host.moshConfiguration,
              let connector = moshTerminalConnector else {
            terminalUnavailableMessage = Self.terminalUnavailableMoshMessage
            return nil
        }

        do {
            let runtimeSession = try await connector.connect(host: host, configuration: configuration)
            guard let sessionID = connect(to: host, runStartupSnippet: false, allowMosh: true) else {
                await runtimeSession.close()
                return nil
            }
            activeTerminalShellSessions[sessionID] = runtimeSession
            if let index = terminalSessions.firstIndex(where: { $0.id == sessionID }) {
                terminalSessions[index].state = .connected
            }
            terminalShellOutputTasks[sessionID]?.cancel()
            terminalShellOutputTasks[sessionID] = Task { @MainActor [weak self] in
                for await output in runtimeSession.outputStream {
                    self?.appendRemoteOutput(output, to: sessionID)
                }
            }
            return sessionID
        } catch {
            terminalUnavailableMessage = MoshTerminalConnector.userFacingMessage(for: error)
        }

        return nil
    }
}
