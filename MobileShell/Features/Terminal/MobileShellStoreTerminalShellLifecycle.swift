import Foundation

extension MobileShellStore {
    func cacheConnectionRequest(for host: ShellHost) {
        guard let selectedSessionID, let credentialVault else { return }
        terminalConnectionRequests[selectedSessionID] = try? SSHConnectionRequestBuilder(
            credentialVault: credentialVault,
            hosts: hosts,
            identities: identities,
            keys: keys,
            certificates: certificates,
            hostGroupProfiles: hostGroupProfiles,
            knownHosts: knownHosts
        ).request(for: host)
    }

    func connectionRequest(for sessionID: TerminalSession.ID) -> SSHConnectionRequest? {
        guard let session = terminalSessions.first(where: { $0.id == sessionID }),
              let host = hosts.first(where: { $0.id == session.hostID })
        else {
            return terminalConnectionRequests[sessionID]
        }

        let request = try? SSHConnectionRequestBuilder(
            credentialVault: credentialVault,
            hosts: hosts,
            identities: identities,
            keys: keys,
            certificates: certificates,
            hostGroupProfiles: hostGroupProfiles,
            knownHosts: knownHosts
        ).request(for: host)
        terminalConnectionRequests[sessionID] = request
        return request
    }

    func stopTerminalShell(for sessionID: TerminalSession.ID) {
        terminalShellOutputTasks[sessionID]?.cancel()
        terminalShellOutputTasks[sessionID] = nil
        if let shell = activeTerminalShellSessions.removeValue(forKey: sessionID) {
            Task {
                await shell.close()
            }
        }
    }

    @MainActor
    func startTerminalShell(for sessionID: TerminalSession.ID) async {
        guard activeTerminalShellSessions[sessionID] == nil,
              let terminalShellClient,
              let request = connectionRequest(for: sessionID)
        else { return }

        do {
            if let index = terminalSessions.firstIndex(where: { $0.id == sessionID }) {
                terminalSessions[index].state = .reconnecting
            }
            let shell = try await terminalShellClient.openShell(using: request)
            activeTerminalShellSessions[sessionID] = shell
            if let index = terminalSessions.firstIndex(where: { $0.id == sessionID }) {
                terminalSessions[index].state = .connected
            }
            terminalShellOutputTasks[sessionID]?.cancel()
            terminalShellOutputTasks[sessionID] = Task { @MainActor [weak self] in
                for await output in shell.outputStream {
                    self?.appendRemoteOutput(output, to: sessionID)
                }
            }
        } catch {
            if recordHostKeyChallenge(error, action: .terminalShell(sessionID: sessionID)) {
                return
            }
            markTerminalSessionDisconnected(sessionID, reason: error.localizedDescription)
        }
    }

    @MainActor
    func executeRemoteCommand(_ command: String, in sessionID: TerminalSession.ID) async {
        guard let commandExecutor,
              let request = connectionRequest(for: sessionID)
        else { return }

        do {
            let output = try await commandExecutor.run(command, using: request)
            appendRemoteOutput(output, to: sessionID)
        } catch {
            if recordHostKeyChallenge(error, action: .remoteCommand(sessionID: sessionID, command: command)) {
                return
            }
            appendRemoteOutput("SSH error: \(error.localizedDescription)", to: sessionID)
        }
    }

    @MainActor
    func sendRemoteCommand(
        _ trimmedCommand: String,
        in sessionID: TerminalSession.ID,
        recordHistory: Bool,
        clearDraft: Bool
    ) async {
        guard let index = terminalSessions.firstIndex(where: { $0.id == sessionID }) else { return }

        let promptLine = "$ \(trimmedCommand)"
        terminalSessions[index].lines.append(promptLine)
        appendSessionLogLines([promptLine], for: sessionID)

        if recordHistory {
            history.insert(trimmedCommand, at: 0)
        }
        if clearDraft {
            commandInput = ""
            terminalSessions[index].commandDraft = ""
        }
        try? persistSnapshot()

        if let shell = activeTerminalShellSessions[sessionID] {
            do {
                try await shell.send("\(trimmedCommand)\n")
            } catch {
                markTerminalSessionDisconnected(sessionID, reason: error.localizedDescription)
            }
            return
        }

        guard commandExecutor != nil,
              connectionRequest(for: sessionID) != nil
        else {
            let outputLines = connectionClient.output(for: trimmedCommand, in: terminalSessions[index])
            terminalSessions[index].lines.append(contentsOf: outputLines)
            appendSessionLogLines(outputLines, for: sessionID)
            return
        }

        await executeRemoteCommand(trimmedCommand, in: sessionID)
    }

    @MainActor
    func retryPendingHostKeyAction(_ action: PendingHostKeyAction) async {
        switch action {
        case let .remoteCommand(sessionID, command):
            await executeRemoteCommand(command, in: sessionID)
        case let .terminalShell(sessionID):
            await startTerminalShell(for: sessionID)
        case let .sftpDirectory(hostID, path):
            guard hosts.contains(where: { $0.id == hostID }) else { return }
            selectedSection = .sftp
            selectedSFTPHostID = hostID
            await refreshSFTPDirectory(path: path)
        case let .portForward(ruleID):
            guard let rule = portForwardRules.first(where: { $0.id == ruleID }) else { return }
            await togglePortForwardRule(rule)
        }
    }

    @MainActor
    @discardableResult
    func recordHostKeyChallenge(_ error: Error, action: PendingHostKeyAction) -> Bool {
        guard let challenge = error as? HostKeyChallenge else { return false }
        pendingHostKeyChallenge = challenge
        pendingHostKeyAction = action
        return true
    }

    @MainActor
    func appendRemoteOutput(_ output: String, to sessionID: TerminalSession.ID) {
        guard let index = terminalSessions.firstIndex(where: { $0.id == sessionID }) else { return }
        let lines = output
            .split(whereSeparator: \.isNewline)
            .map(String.init)

        let outputLines = lines.isEmpty ? [""] : lines
        terminalSessions[index].lines.append(contentsOf: outputLines)
        appendSessionLogLines(outputLines, for: sessionID)
    }
}
