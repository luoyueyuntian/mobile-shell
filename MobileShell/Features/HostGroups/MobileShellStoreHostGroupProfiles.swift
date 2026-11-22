import Foundation

extension MobileShellStore {
    @discardableResult
    func upsertHostGroupProfile(
        name: String,
        identityID: SSHIdentity.ID?,
        jumpHostID: ShellHost.ID? = nil,
        startupSnippetID: ShellSnippet.ID? = nil,
        terminalTheme: TerminalTheme? = nil,
        terminalFontSize: TerminalFontSize? = nil,
        environmentVariables: [ShellEnvironmentVariable] = []
    ) -> HostGroupProfile? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }

        let profile = HostGroupProfile(
            name: trimmedName,
            identityID: identityID,
            jumpHostID: jumpHostID,
            startupSnippetID: startupSnippetID,
            terminalTheme: terminalTheme,
            terminalFontSize: terminalFontSize,
            environmentVariables: environmentVariables
        )
        if let index = hostGroupProfiles.firstIndex(where: {
            $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame
        }) {
            hostGroupProfiles[index] = profile
        } else {
            hostGroupProfiles.append(profile)
            hostGroupProfiles.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        history.insert("Updated group \(profile.name)", at: 0)
        try? persistSnapshot()
        return profile
    }
}
