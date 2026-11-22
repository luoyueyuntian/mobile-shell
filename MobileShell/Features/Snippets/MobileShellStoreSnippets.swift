import Foundation

extension MobileShellStore {
    func commandSuggestions(for draft: String) -> [CommandSuggestion] {
        CommandAutocompleteEngine().suggestions(
            for: draft,
            snippets: snippets,
            history: history
        )
    }

    func applyCommandSuggestion(_ suggestion: CommandSuggestion) {
        setTerminalCommandDraft(suggestion.command)
    }

    func useSnippet(_ snippet: ShellSnippet) {
        setTerminalCommandDraft(snippet.command)
    }

    @MainActor
    @discardableResult
    func runSnippetInVisibleTerminals(_ snippet: ShellSnippet) async -> Int {
        guard snippets.contains(where: { $0.id == snippet.id }) else { return 0 }

        let command = snippet.command.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetSessionIDs = visibleTerminalSessions().map(\.id)
        guard !command.isEmpty, !targetSessionIDs.isEmpty else { return 0 }

        for sessionID in targetSessionIDs {
            await sendRemoteCommand(
                command,
                in: sessionID,
                recordHistory: false,
                clearDraft: false
            )
        }

        history.insert("Ran snippet \(snippet.title) on \(targetSessionIDs.count) terminals", at: 0)
        try? persistSnapshot()
        return targetSessionIDs.count
    }

    func startupSnippetTitle(for host: ShellHost) -> String? {
        startupSnippet(for: host)?.title
    }

    @discardableResult
    func addSnippet(
        title: String,
        command: String,
        packageName: String = ShellSnippet.defaultPackageName
    ) -> ShellSnippet? {
        guard let snippet = makeSnippet(title: title, command: command, packageName: packageName) else { return nil }

        snippets.append(snippet)
        history.insert("Added snippet \(snippet.title)", at: 0)
        try? persistSnapshot()
        return snippet
    }

    @discardableResult
    func updateSnippet(
        _ snippet: ShellSnippet,
        title: String,
        command: String,
        packageName: String? = nil
    ) -> ShellSnippet? {
        guard let index = snippets.firstIndex(where: { $0.id == snippet.id }),
              let updatedSnippet = makeSnippet(
                id: snippet.id,
                title: title,
                command: command,
                packageName: packageName ?? snippet.packageName
              )
        else { return nil }

        snippets[index] = updatedSnippet
        history.insert("Updated snippet \(updatedSnippet.title)", at: 0)
        try? persistSnapshot()
        return updatedSnippet
    }

    func deleteSnippet(_ snippet: ShellSnippet) {
        guard let index = snippets.firstIndex(where: { $0.id == snippet.id }) else { return }
        let storedSnippet = snippets[index]

        snippets.remove(at: index)
        hosts = hosts.map { host in
            guard host.startupSnippetID == storedSnippet.id else { return host }
            var detachedHost = host
            detachedHost.startupSnippetID = nil
            return detachedHost
        }
        hostGroupProfiles = hostGroupProfiles.map { profile in
            guard profile.startupSnippetID == storedSnippet.id else { return profile }
            var detachedProfile = profile
            detachedProfile.startupSnippetID = nil
            return detachedProfile
        }
        history.insert("Deleted snippet \(storedSnippet.title)", at: 0)
        try? persistSnapshot()
    }

    func snippetPackages() -> [SnippetPackageSection] {
        var packageSectionsByKey: [String: SnippetPackageSection] = [:]

        for snippet in snippets {
            let packageName = ShellSnippet.normalizedPackageName(snippet.packageName)
            let key = packageName.lowercased()
            if var packageSection = packageSectionsByKey[key] {
                packageSection.snippets.append(snippet)
                packageSectionsByKey[key] = packageSection
            } else {
                packageSectionsByKey[key] = SnippetPackageSection(name: packageName, snippets: [snippet])
            }
        }

        return packageSectionsByKey.values
            .map { section in
                SnippetPackageSection(
                    name: section.name,
                    snippets: section.snippets.sorted {
                        $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                    }
                )
            }
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    func startupSnippet(for host: ShellHost) -> ShellSnippet? {
        guard let startupSnippetID = host.startupSnippetID ?? hostGroupProfile(for: host)?.startupSnippetID else { return nil }
        return snippets.first { $0.id == startupSnippetID }
    }

    func makeSnippet(
        id: UUID = UUID(),
        title: String,
        command: String,
        packageName: String = ShellSnippet.defaultPackageName
    ) -> ShellSnippet? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedCommand.isEmpty else { return nil }

        return ShellSnippet(
            id: id,
            title: trimmedTitle,
            command: trimmedCommand,
            packageName: packageName
        )
    }

    func setTerminalCommandDraft(_ command: String) {
        if let selectedSessionID {
            updateCommandDraft(command, for: selectedSessionID)
        } else {
            commandInput = command
        }
        selectedSection = .terminals
    }

    func runEnvironmentVariableExportsPreview(for host: ShellHost, in sessionID: TerminalSession.ID) {
        for variable in environmentVariables(for: host) {
            runPreviewCommand(variable.exportCommand, in: sessionID)
        }
    }

    func runStartupSnippetPreview(for host: ShellHost, in sessionID: TerminalSession.ID) {
        guard let snippet = startupSnippet(for: host) else { return }
        let command = snippet.command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }

        runPreviewCommand(command, in: sessionID)
        history.insert("Ran startup snippet \(snippet.title) on \(host.name)", at: 0)
    }

    func runPreviewCommand(_ command: String, in sessionID: TerminalSession.ID) {
        guard let index = terminalSessions.firstIndex(where: { $0.id == sessionID }) else { return }

        let promptLine = "$ \(command)"
        let outputLines = connectionClient.output(for: command, in: terminalSessions[index])
        terminalSessions[index].lines.append(promptLine)
        terminalSessions[index].lines.append(contentsOf: outputLines)
        appendSessionLogLines([promptLine] + outputLines, for: sessionID)
    }
}
