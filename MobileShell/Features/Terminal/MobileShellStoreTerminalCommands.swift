import Foundation

extension MobileShellStore {
    func selectTerminalSession(_ sessionID: TerminalSession.ID) {
        guard let session = terminalSessions.first(where: { $0.id == sessionID }) else { return }
        selectedSessionID = session.id
        commandInput = session.commandDraft
    }

    func updateCommandDraft(_ draft: String, for sessionID: TerminalSession.ID) {
        guard let index = terminalSessions.firstIndex(where: { $0.id == sessionID }) else { return }
        terminalSessions[index].commandDraft = draft
        if selectedSessionID == sessionID {
            commandInput = draft
        }
    }

    @MainActor
    func sendTerminalKeyboardShortcut(_ shortcut: TerminalKeyboardShortcut) async {
        guard let selectedSessionID,
              let index = terminalSessions.firstIndex(where: { $0.id == selectedSessionID })
        else { return }

        if let shell = activeTerminalShellSessions[selectedSessionID] {
            do {
                try await shell.send(shortcut.input)
            } catch {
                markTerminalSessionDisconnected(selectedSessionID, reason: error.localizedDescription)
            }
            return
        }

        guard shortcut.appendsToDraftWithoutLiveShell else { return }
        updateCommandDraft(terminalSessions[index].commandDraft + shortcut.input, for: selectedSessionID)
    }

    func closeTerminalSession(_ sessionID: TerminalSession.ID) {
        guard let index = terminalSessions.firstIndex(where: { $0.id == sessionID }) else { return }
        let closedSession = terminalSessions.remove(at: index)
        stopTerminalShell(for: closedSession.id)
        terminalConnectionRequests[closedSession.id] = nil
        closeSessionLog(for: closedSession.id)
        removeTerminalSessionFromWorkspaces(closedSession.id)
        history.insert("Closed terminal \(closedSession.hostName)", at: 0)
        try? persistSnapshot()

        guard selectedSessionID == sessionID else { return }
        let replacementSessions = visibleTerminalSessions()
        if replacementSessions.isEmpty {
            selectedSessionID = nil
            commandInput = ""
        } else {
            let replacementIndex = min(index, replacementSessions.count - 1)
            selectTerminalSession(replacementSessions[replacementIndex].id)
        }
    }

    func markTerminalSessionDisconnected(_ sessionID: TerminalSession.ID, reason: String) {
        guard let index = terminalSessions.firstIndex(where: { $0.id == sessionID }) else { return }
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let line = "Disconnected: \(trimmedReason.isEmpty ? "Connection closed" : trimmedReason)"
        terminalSessions[index].state = .disconnected
        terminalSessions[index].lines.append(line)
        appendSessionLogLines([line], for: sessionID)
        terminalConnectionRequests[sessionID] = nil
    }

    func runCommand(_ command: String) {
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCommand.isEmpty,
              let selectedSessionID,
              let index = terminalSessions.firstIndex(where: { $0.id == selectedSessionID })
        else { return }

        let promptLine = "$ \(trimmedCommand)"
        let outputLines = connectionClient.output(for: trimmedCommand, in: terminalSessions[index])
        terminalSessions[index].lines.append(promptLine)
        terminalSessions[index].lines.append(contentsOf: outputLines)
        appendSessionLogLines([promptLine] + outputLines, for: selectedSessionID)
        history.insert(trimmedCommand, at: 0)
        commandInput = ""
        terminalSessions[index].commandDraft = ""
        try? persistSnapshot()
    }

    @MainActor
    func runRemoteCommand(_ command: String) async {
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCommand.isEmpty,
              let selectedSessionID
        else { return }

        await sendRemoteCommand(
            trimmedCommand,
            in: selectedSessionID,
            recordHistory: true,
            clearDraft: true
        )
    }

    @MainActor
    func broadcastCommand(_ command: String) async {
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetSessionIDs = visibleTerminalSessions().map(\.id)
        guard !trimmedCommand.isEmpty, !targetSessionIDs.isEmpty else { return }

        for sessionID in targetSessionIDs {
            await sendRemoteCommand(
                trimmedCommand,
                in: sessionID,
                recordHistory: false,
                clearDraft: false
            )
        }

        if let selectedSessionID {
            updateCommandDraft("", for: selectedSessionID)
        } else {
            commandInput = ""
        }

        history.insert("Broadcast \(trimmedCommand) to \(selectedTerminalWorkspace?.name ?? "All terminals")", at: 0)
        try? persistSnapshot()
    }
}
