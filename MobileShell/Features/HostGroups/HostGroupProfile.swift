import Foundation

struct HostGroupProfile: Identifiable, Equatable, Codable {
    var name: String
    var identityID: SSHIdentity.ID?
    var jumpHostID: ShellHost.ID? = nil
    var startupSnippetID: ShellSnippet.ID? = nil
    var terminalTheme: TerminalTheme? = nil
    var terminalFontSize: TerminalFontSize? = nil
    var environmentVariables: [ShellEnvironmentVariable] = []

    var id: String { name }

    init(
        name: String,
        identityID: SSHIdentity.ID?,
        jumpHostID: ShellHost.ID? = nil,
        startupSnippetID: ShellSnippet.ID? = nil,
        terminalTheme: TerminalTheme? = nil,
        terminalFontSize: TerminalFontSize? = nil,
        environmentVariables: [ShellEnvironmentVariable] = []
    ) {
        self.name = name
        self.identityID = identityID
        self.jumpHostID = jumpHostID
        self.startupSnippetID = startupSnippetID
        self.terminalTheme = terminalTheme
        self.terminalFontSize = terminalFontSize
        self.environmentVariables = ShellEnvironmentVariable.sanitized(environmentVariables)
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case identityID
        case jumpHostID
        case startupSnippetID
        case terminalTheme
        case terminalFontSize
        case environmentVariables
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        name = try container.decode(String.self, forKey: .name)
        identityID = try container.decodeIfPresent(SSHIdentity.ID.self, forKey: .identityID)
        jumpHostID = try container.decodeIfPresent(ShellHost.ID.self, forKey: .jumpHostID)
        startupSnippetID = try container.decodeIfPresent(ShellSnippet.ID.self, forKey: .startupSnippetID)
        terminalTheme = try container.decodeIfPresent(TerminalTheme.self, forKey: .terminalTheme)
        terminalFontSize = try container.decodeIfPresent(TerminalFontSize.self, forKey: .terminalFontSize)
        environmentVariables = ShellEnvironmentVariable.sanitized(
            try container.decodeIfPresent([ShellEnvironmentVariable].self, forKey: .environmentVariables) ?? []
        )
    }
}
