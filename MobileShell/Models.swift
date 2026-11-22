import Foundation
import CoreTransferable
import CryptoKit
import Observation
import UniformTypeIdentifiers

enum ShellSection: String, CaseIterable, Identifiable {
    case hosts
    case terminals
    case logs
    case sftp
    case portForwarding
    case snippets
    case keychain
    case history
    case knownHosts
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hosts: return "Hosts"
        case .terminals: return "Terminals"
        case .logs: return "Logs"
        case .sftp: return "SFTP"
        case .portForwarding: return "Port Forwarding"
        case .snippets: return "Snippets"
        case .keychain: return "Keychain"
        case .history: return "History"
        case .knownHosts: return "Known Hosts"
        case .settings: return "Settings"
        }
    }

    var symbolName: String {
        switch self {
        case .hosts: return "server.rack"
        case .terminals: return "terminal"
        case .logs: return "doc.text.magnifyingglass"
        case .sftp: return "folder"
        case .portForwarding: return "arrow.triangle.branch"
        case .snippets: return "curlybraces"
        case .keychain: return "key"
        case .history: return "clock.arrow.circlepath"
        case .knownHosts: return "checkmark.shield"
        case .settings: return "gearshape"
        }
    }

    var compactTitle: String {
        switch self {
        case .hosts: return "Hosts"
        case .terminals: return "Terminal"
        case .logs: return "Logs"
        case .sftp: return "SFTP"
        case .portForwarding: return "Ports"
        case .snippets: return "Snippets"
        case .keychain: return "Keys"
        case .history: return "History"
        case .knownHosts: return "Known"
        case .settings: return "Settings"
        }
    }
}

enum HostStatus: String, Codable {
    case online
    case idle
    case locked
}

struct ShellHost: Identifiable, Equatable, Codable {
    let id: UUID
    var name: String
    var address: String
    var port: Int
    var username: String
    var group: String
    var tags: [String]
    var status: HostStatus
    var sshKeyID: SSHKey.ID?
    var identityID: SSHIdentity.ID?
    var jumpHostID: ShellHost.ID?
    var `protocol`: RemoteAccessProtocol
    var moshConfiguration: MoshHostConfiguration?
    var startupSnippetID: ShellSnippet.ID?
    var terminalTheme: TerminalTheme?
    var terminalFontSize: TerminalFontSize?
    var environmentVariables: [ShellEnvironmentVariable]

    var subtitle: String {
        ([username, endpoint] + tags).joined(separator: ", ")
    }

    var endpoint: String {
        port == 22 ? address : "\(address):\(port)"
    }

    private static func normalizedMoshConfiguration(
        for protocol: RemoteAccessProtocol,
        moshConfiguration: MoshHostConfiguration?
    ) -> MoshHostConfiguration? {
        switch `protocol` {
        case .ssh:
            return nil
        case .mosh:
            return moshConfiguration ?? .default
        }
    }

    init(
        id: UUID,
        name: String,
        address: String,
        port: Int = 22,
        username: String,
        group: String,
        tags: [String],
        status: HostStatus,
        sshKeyID: SSHKey.ID? = nil,
        identityID: SSHIdentity.ID? = nil,
        jumpHostID: ShellHost.ID? = nil,
        protocol: RemoteAccessProtocol = .ssh,
        moshConfiguration: MoshHostConfiguration? = nil,
        startupSnippetID: ShellSnippet.ID? = nil,
        terminalTheme: TerminalTheme? = nil,
        terminalFontSize: TerminalFontSize? = nil,
        environmentVariables: [ShellEnvironmentVariable] = []
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.port = port
        self.username = username
        self.group = group
        self.tags = tags
        self.status = status
        self.sshKeyID = sshKeyID
        self.identityID = identityID
        self.jumpHostID = jumpHostID
        self.`protocol` = `protocol`
        self.moshConfiguration = Self.normalizedMoshConfiguration(for: `protocol`, moshConfiguration: moshConfiguration)
        self.startupSnippetID = startupSnippetID
        self.terminalTheme = terminalTheme
        self.terminalFontSize = terminalFontSize
        self.environmentVariables = ShellEnvironmentVariable.sanitized(environmentVariables)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case address
        case port
        case username
        case group
        case tags
        case status
        case sshKeyID
        case identityID
        case jumpHostID
        case `protocol`
        case moshConfiguration
        case startupSnippetID
        case terminalTheme
        case terminalFontSize
        case environmentVariables
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        address = try container.decode(String.self, forKey: .address)
        port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 22
        username = try container.decode(String.self, forKey: .username)
        group = try container.decode(String.self, forKey: .group)
        tags = try container.decode([String].self, forKey: .tags)
        status = try container.decode(HostStatus.self, forKey: .status)
        sshKeyID = try container.decodeIfPresent(SSHKey.ID.self, forKey: .sshKeyID)
        identityID = try container.decodeIfPresent(SSHIdentity.ID.self, forKey: .identityID)
        jumpHostID = try container.decodeIfPresent(ShellHost.ID.self, forKey: .jumpHostID)
        self.`protocol` = try container.decodeIfPresent(RemoteAccessProtocol.self, forKey: .protocol) ?? .ssh
        moshConfiguration = Self.normalizedMoshConfiguration(
            for: self.`protocol`,
            moshConfiguration: try container.decodeIfPresent(MoshHostConfiguration.self, forKey: .moshConfiguration)
        )
        startupSnippetID = try container.decodeIfPresent(ShellSnippet.ID.self, forKey: .startupSnippetID)
        terminalTheme = try container.decodeIfPresent(TerminalTheme.self, forKey: .terminalTheme)
        terminalFontSize = try container.decodeIfPresent(TerminalFontSize.self, forKey: .terminalFontSize)
        environmentVariables = ShellEnvironmentVariable.sanitized(
            try container.decodeIfPresent([ShellEnvironmentVariable].self, forKey: .environmentVariables) ?? []
        )
    }
}

enum TerminalSessionState: String, Codable {
    case connected
    case disconnected
    case reconnecting
}

enum TerminalKeyboardShortcut: String, CaseIterable, Identifiable, Equatable, Sendable {
    case escape
    case tab
    case controlC
    case controlD
    case dash
    case slash
    case tilde
    case pipe

    var id: String { rawValue }

    var label: String {
        switch self {
        case .escape: "esc"
        case .tab: "tab"
        case .controlC: "ctrl-c"
        case .controlD: "ctrl-d"
        case .dash: "-"
        case .slash: "/"
        case .tilde: "~"
        case .pipe: "|"
        }
    }

    var input: String {
        switch self {
        case .escape: "\u{1B}"
        case .tab: "\t"
        case .controlC: "\u{03}"
        case .controlD: "\u{04}"
        case .dash: "-"
        case .slash: "/"
        case .tilde: "~"
        case .pipe: "|"
        }
    }

    var appendsToDraftWithoutLiveShell: Bool {
        switch self {
        case .dash, .slash, .tilde, .pipe:
            true
        case .escape, .tab, .controlC, .controlD:
            false
        }
    }
}

struct TerminalSession: Identifiable, Equatable, Codable {
    let id: UUID
    var hostID: ShellHost.ID
    var hostName: String
    var prompt: String
    var lines: [String]
    var state: TerminalSessionState
    var commandDraft: String = ""

    init(
        id: UUID,
        hostID: ShellHost.ID,
        hostName: String,
        prompt: String,
        lines: [String],
        state: TerminalSessionState = .connected,
        commandDraft: String = ""
    ) {
        self.id = id
        self.hostID = hostID
        self.hostName = hostName
        self.prompt = prompt
        self.lines = lines
        self.state = state
        self.commandDraft = commandDraft
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case hostID
        case hostName
        case prompt
        case lines
        case state
        case commandDraft
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        hostID = try container.decode(ShellHost.ID.self, forKey: .hostID)
        hostName = try container.decode(String.self, forKey: .hostName)
        prompt = try container.decode(String.self, forKey: .prompt)
        lines = try container.decode([String].self, forKey: .lines)
        state = try container.decodeIfPresent(TerminalSessionState.self, forKey: .state) ?? .connected
        commandDraft = try container.decodeIfPresent(String.self, forKey: .commandDraft) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(hostID, forKey: .hostID)
        try container.encode(hostName, forKey: .hostName)
        try container.encode(prompt, forKey: .prompt)
        try container.encode(lines, forKey: .lines)
        try container.encode(state, forKey: .state)
        try container.encode(commandDraft, forKey: .commandDraft)
    }
}

enum PortForwardKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case local
    case remote
    case dynamic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .local: "Local"
        case .remote: "Remote"
        case .dynamic: "Dynamic"
        }
    }

    var description: String {
        switch self {
        case .local:
            "Forward a local listener to a remote service through SSH."
        case .remote:
            "Expose a local service through a listener on the SSH server."
        case .dynamic:
            "Run a local SOCKS5 tunnel through SSH for browser and CLI traffic."
        }
    }
}

struct PortForwardRule: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    var kind: PortForwardKind
    var name: String
    var sshHostID: ShellHost.ID?
    var localHost: String
    var localPort: Int
    var remoteHost: String
    var remotePort: Int
    var isActive: Bool

    var routeSummary: String {
        switch kind {
        case .local:
            "\(localHost):\(localPort) -> \(remoteHost):\(remotePort)"
        case .remote:
            "\(remoteHost):\(remotePort) -> \(localHost):\(localPort)"
        case .dynamic:
            "SOCKS \(localHost):\(localPort)"
        }
    }

    init(
        id: UUID,
        kind: PortForwardKind = .local,
        name: String,
        sshHostID: ShellHost.ID? = nil,
        localHost: String = "127.0.0.1",
        localPort: Int,
        remoteHost: String,
        remotePort: Int,
        isActive: Bool
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.sshHostID = sshHostID
        self.localHost = localHost
        self.localPort = localPort
        self.remoteHost = remoteHost
        self.remotePort = remotePort
        self.isActive = isActive
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case name
        case sshHostID
        case localHost
        case localPort
        case remoteHost
        case remotePort
        case isActive
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decodeIfPresent(PortForwardKind.self, forKey: .kind) ?? .local
        name = try container.decode(String.self, forKey: .name)
        sshHostID = try container.decodeIfPresent(ShellHost.ID.self, forKey: .sshHostID)
        localHost = try container.decodeIfPresent(String.self, forKey: .localHost) ?? "127.0.0.1"
        localPort = try container.decode(Int.self, forKey: .localPort)
        remoteHost = try container.decode(String.self, forKey: .remoteHost)
        remotePort = try container.decode(Int.self, forKey: .remotePort)
        isActive = false
    }
}

struct SnippetPackageSection: Identifiable, Equatable {
    var id: String { name.lowercased() }
    var name: String
    var snippets: [ShellSnippet]
}

struct ShellSnippet: Identifiable, Equatable, Codable {
    static let defaultPackageName = "Personal"

    let id: UUID
    var title: String
    var command: String
    var packageName: String

    init(
        id: UUID,
        title: String,
        command: String,
        packageName: String = ShellSnippet.defaultPackageName
    ) {
        self.id = id
        self.title = title
        self.command = command
        self.packageName = ShellSnippet.normalizedPackageName(packageName)
    }

    static func normalizedPackageName(_ packageName: String) -> String {
        let trimmedPackageName = packageName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedPackageName.isEmpty ? defaultPackageName : trimmedPackageName
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case command
        case packageName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        command = try container.decode(String.self, forKey: .command)
        packageName = ShellSnippet.normalizedPackageName(
            try container.decodeIfPresent(String.self, forKey: .packageName) ?? ShellSnippet.defaultPackageName
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(command, forKey: .command)
        try container.encode(packageName, forKey: .packageName)
    }
}

struct SSHIdentity: Identifiable, Equatable, Codable {
    let id: UUID
    var name: String
    var username: String
    var sshKeyID: SSHKey.ID?
}

struct SFTPItem: Identifiable, Equatable, Codable {
    let id: UUID
    var name: String
    var kind: String
    var size: String
}

struct SFTPDownloadedFile: Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var remotePath: String
    var data: Data

    init(id: UUID = UUID(), name: String, remotePath: String, data: Data) {
        self.id = id
        self.name = name
        self.remotePath = remotePath
        self.data = data
    }

    var shareExportFileName: String {
        normalizedExportFileName(from: name)
            ?? normalizedExportFileName(from: remotePath)
            ?? "download"
    }

    func makeShareExportFile(
        in directory: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MobileShell-SFTP-Exports", isDirectory: true)
    ) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let exportURL = directory.appendingPathComponent(shareExportFileName, isDirectory: false)
        try data.write(to: exportURL, options: .atomic)
        return exportURL
    }

    private func normalizedExportFileName(from rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lastPathComponent = trimmed
            .split(separator: "/", omittingEmptySubsequences: true)
            .last
            .map(String.init) ?? trimmed
        let normalized = lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}

extension SFTPDownloadedFile: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .data) { file in
            SentTransferredFile(try file.makeShareExportFile())
        }
    }
}

struct KnownHost: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    var host: String
    var keyType: String
    var fingerprint: String

    var title: String { host }

    var subtitle: String {
        "\(keyType) · \(fingerprint)"
    }

    var knownHostLine: String {
        "\(host) \(keyType) \(fingerprint)"
    }

    func matches(hostname: String, port: Int) -> Bool {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedHostname = hostname.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedHost.isEmpty, !normalizedHostname.isEmpty else { return false }

        if port == 22 {
            return normalizedHost == normalizedHostname
        }

        return normalizedHost == "[\(normalizedHostname)]:\(port)"
    }

    static func hostToken(hostname: String, port: Int) -> String {
        let normalizedHostname = hostname.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return port == 22 ? normalizedHostname : "[\(normalizedHostname)]:\(port)"
    }

    init(id: UUID = UUID(), host: String, keyType: String, fingerprint: String) {
        self.id = id
        self.host = host
        self.keyType = keyType
        self.fingerprint = fingerprint
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case host
        case keyType
        case fingerprint
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            host = try container.decode(String.self, forKey: .host)
            keyType = try container.decode(String.self, forKey: .keyType)
            fingerprint = try container.decode(String.self, forKey: .fingerprint)
            return
        }

        let legacyLine = try decoder.singleValueContainer().decode(String.self)
        self = KnownHost.legacy(line: legacyLine)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(host, forKey: .host)
        try container.encode(keyType, forKey: .keyType)
        try container.encode(fingerprint, forKey: .fingerprint)
    }

    private static func legacy(line: String) -> KnownHost {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmedLine.split(whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count >= 3 else {
            return KnownHost(host: trimmedLine, keyType: "unknown", fingerprint: "")
        }

        return KnownHost(host: parts[0], keyType: parts[1], fingerprint: parts[2])
    }
}

struct HostKeyChallenge: Error, Identifiable, Equatable, Sendable, LocalizedError {
    let id: UUID
    let hostname: String
    let port: Int
    let keyType: String
    let fingerprint: String

    var knownHostHost: String {
        KnownHost.hostToken(hostname: hostname, port: port)
    }

    var knownHostLine: String {
        "\(knownHostHost) \(keyType) \(fingerprint)"
    }

    var errorDescription: String? {
        "Host key verification required for \(knownHostHost)"
    }

    init(
        id: UUID = UUID(),
        hostname: String,
        port: Int,
        keyType: String,
        fingerprint: String
    ) {
        self.id = id
        self.hostname = hostname
        self.port = port
        self.keyType = keyType
        self.fingerprint = fingerprint
    }
}

struct SSHKey: Identifiable, Equatable, Codable {
    let id: UUID
    var name: String
    var fingerprint: String
    var kind: String
    var certificateID: SSHCertificate.ID? = nil
}

struct SSHCertificate: Identifiable, Equatable, Codable {
    let id: UUID
    var name: String
    var fingerprint: String
    var kind: String
}

struct HostAuthenticationSummary: Equatable {
    var text: String
    var symbolName: String
    var isReady: Bool
}

@Observable
final class MobileShellStore {
    static let terminalUnavailableMoshMessage = "Mosh configuration is saved for this host, but real Mosh sessions are not available in this version yet."

    enum PendingHostKeyAction {
        case remoteCommand(sessionID: TerminalSession.ID, command: String)
        case terminalShell(sessionID: TerminalSession.ID)
        case sftpDirectory(hostID: ShellHost.ID, path: String)
        case portForward(ruleID: PortForwardRule.ID)
    }

    var repository: JSONHostRepository?
    var credentialVault: CredentialVault?
    var connectionClient: any ShellConnectionClient
    var commandExecutor: (any SSHCommandExecuting)?
    var terminalShellClient: (any TerminalShellClient)?
    var moshPreparationClient: (any MoshPreparationClient)?
    var moshRuntimeClient: (any MoshRuntimeClient)?
    var sftpClient: any SFTPDirectoryListingClient
    var portForwardingClient: any PortForwardingClient
    var activePortForwardSessions: [PortForwardRule.ID: any PortForwardingSession] = [:]
    var activeTerminalShellSessions: [TerminalSession.ID: any TerminalShellSession] = [:]
    var terminalShellOutputTasks: [TerminalSession.ID: Task<Void, Never>] = [:]
    var terminalConnectionRequests: [TerminalSession.ID: SSHConnectionRequest] = [:]
    var terminalSessionLogIDs: [TerminalSession.ID: SessionLog.ID] = [:]
    var pendingHostKeyAction: PendingHostKeyAction?

    var selectedSection: ShellSection = .hosts
    var searchText = ""
    var selectedHostTag: String?
    var commandInput = ""
    var hosts: [ShellHost] = []
    var terminalSessions: [TerminalSession] = []
    var selectedSessionID: TerminalSession.ID?
    var selectedSFTPHostID: ShellHost.ID?
    var sftpPath = "/home/deploy"
    var isSFTPLoading = false
    var sftpErrorMessage: String?
    var portForwardErrorMessage: String?
    var terminalUnavailableMessage: String?
    var portForwardRules: [PortForwardRule] = []
    var snippets: [ShellSnippet] = []
    var sftpItems: [SFTPItem] = []
    var downloadedSFTPFile: SFTPDownloadedFile?
    var keys: [SSHKey] = []
    var certificates: [SSHCertificate] = []
    var identities: [SSHIdentity] = []
    var hostGroupProfiles: [HostGroupProfile] = []
    var sessionLogs: [SessionLog] = []
    var terminalWorkspaces: [TerminalWorkspace] = []
    var terminalWorkspaceTemplates: [TerminalWorkspaceTemplate] = []
    var selectedWorkspaceID: TerminalWorkspace.ID?
    var history: [String] = []
    var knownHosts: [KnownHost] = []
    var pendingHostKeyChallenge: HostKeyChallenge?

    var selectedTerminalSession: TerminalSession? {
        guard let selectedSessionID else { return terminalSessions.first }
        return terminalSessions.first { $0.id == selectedSessionID }
    }

    var selectedTerminalWorkspace: TerminalWorkspace? {
        guard let selectedWorkspaceID else { return nil }
        return terminalWorkspaces.first { $0.id == selectedWorkspaceID }
    }

    static func preview() -> MobileShellStore {
        MobileShellStore(
            hosts: [
                ShellHost(
                    id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                    name: "acme-api-prod",
                    address: "api-prod.acme.internal",
                    username: "deploy",
                    group: "Production",
                    tags: ["ssh", "prod", "api"],
                    status: .idle
                ),
                ShellHost(
                    id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                    name: "db-replica-eu",
                    address: "10.24.18.12",
                    username: "postgres",
                    group: "Databases",
                    tags: ["ssh", "db", "replica"],
                    status: .locked
                ),
                ShellHost(
                    id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                    name: "redis-cache-dev",
                    address: "cache-dev.acme.internal",
                    username: "ubuntu",
                    group: "Development",
                    tags: ["ssh", "dev", "cache"],
                    status: .online
                ),
                ShellHost(
                    id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
                    name: "home-lab",
                    address: "192.168.1.42",
                    username: "leah",
                    group: "Personal",
                    tags: ["ssh", "lab", "nas"],
                    status: .idle
                )
            ],
            portForwardRules: [
                PortForwardRule(
                    id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
                    name: "Postgres Tunnel",
                    sshHostID: UUID(uuidString: "22222222-2222-2222-2222-222222222222"),
                    localPort: 5433,
                    remoteHost: "db-replica-eu",
                    remotePort: 5432,
                    isActive: false
                ),
                PortForwardRule(
                    id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
                    name: "Grafana Preview",
                    sshHostID: UUID(uuidString: "11111111-1111-1111-1111-111111111111"),
                    localPort: 3001,
                    remoteHost: "acme-api-prod",
                    remotePort: 3000,
                    isActive: true
                )
            ],
            snippets: [
                ShellSnippet(
                    id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
                    title: "Service Health",
                    command: "systemctl status api.service"
                ),
                ShellSnippet(
                    id: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!,
                    title: "Disk Usage",
                    command: "df -h"
                ),
                ShellSnippet(
                    id: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!,
                    title: "Recent Logs",
                    command: "tail -n 120 /var/log/nginx/access.log"
                )
            ],
            sftpItems: [
                SFTPItem(id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!, name: "backup", kind: "folder", size: "--"),
                SFTPItem(id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!, name: "deploy.sh", kind: "shell", size: "4 KB"),
                SFTPItem(id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!, name: "app_start_logs.txt", kind: "text", size: "28 KB"),
                SFTPItem(id: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!, name: "catalog_archive.tar", kind: "archive", size: "1.2 GB")
            ],
            keys: [
                SSHKey(
                    id: UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!,
                    name: "iPhone Device Key",
                    fingerprint: "SHA256:9pP3...rQ2c",
                    kind: "ed25519"
                ),
                SSHKey(
                    id: UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!,
                    name: "Production FIDO2",
                    fingerprint: "SHA256:u2F...7Ka",
                    kind: "hardware"
                )
            ],
            identities: [
                SSHIdentity(
                    id: UUID(uuidString: "12121212-1212-1212-1212-121212121212")!,
                    name: "Production Deploy",
                    username: "deploy",
                    sshKeyID: UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")
                ),
                SSHIdentity(
                    id: UUID(uuidString: "13131313-1313-1313-1313-131313131313")!,
                    name: "Personal Lab",
                    username: "leah",
                    sshKeyID: nil
                )
            ],
            hostGroupProfiles: [
                HostGroupProfile(
                    name: "Production",
                    identityID: UUID(uuidString: "12121212-1212-1212-1212-121212121212")
                ),
                HostGroupProfile(
                    name: "Personal",
                    identityID: UUID(uuidString: "13131313-1313-1313-1313-131313131313")
                )
            ],
            history: [
                "Connected to acme-api-prod",
                "Started Grafana Preview tunnel",
                "Uploaded deploy.sh to /home/deploy"
            ],
            knownHosts: [
                KnownHost(
                    host: "api-prod.acme.internal",
                    keyType: "ssh-ed25519",
                    fingerprint: "SHA256:9pP3..."
                ),
                KnownHost(
                    host: "10.24.18.12",
                    keyType: "ecdsa-sha2-nistp256",
                    fingerprint: "SHA256:m02..."
                ),
                KnownHost(
                    host: "cache-dev.acme.internal",
                    keyType: "ssh-rsa",
                    fingerprint: "SHA256:p8Z..."
                )
            ],
            terminalShellClient: PreviewTerminalShellClient()
        )
    }

    static func live() -> MobileShellStore {
        do {
            return try persistent(repository: JSONHostRepository(), credentialVault: KeychainCredentialVault())
        } catch {
            return preview()
        }
    }

    static func persistent(repository: JSONHostRepository, credentialVault: CredentialVault) throws -> MobileShellStore {
        let stored = try MobileShellStore(repository: repository, credentialVault: credentialVault)
        if !stored.hosts.isEmpty {
            return stored
        }

        let seeded = preview()
        seeded.repository = repository
        seeded.credentialVault = credentialVault
        let commandExecutor = CitadelCommandExecutor()
        seeded.commandExecutor = commandExecutor
        seeded.terminalShellClient = CitadelTerminalShellClient()
        seeded.moshPreparationClient = CitadelMoshPreparationClient()
        seeded.moshRuntimeClient = MoshRuntimeClientBridge()
        seeded.sftpClient = CitadelSFTPDirectoryListingClient()
        seeded.portForwardingClient = CitadelPortForwardingClient()
        return seeded
    }

    init(
        hosts: [ShellHost] = [],
        portForwardRules: [PortForwardRule] = [],
        snippets: [ShellSnippet] = [],
        sftpItems: [SFTPItem] = [],
        keys: [SSHKey] = [],
        certificates: [SSHCertificate] = [],
        identities: [SSHIdentity] = [],
        hostGroupProfiles: [HostGroupProfile] = [],
        sessionLogs: [SessionLog] = [],
        terminalWorkspaces: [TerminalWorkspace] = [],
        terminalWorkspaceTemplates: [TerminalWorkspaceTemplate] = [],
        history: [String] = [],
        knownHosts: [KnownHost] = [],
        connectionClient: any ShellConnectionClient = PreviewShellConnectionClient(),
        credentialVault: CredentialVault? = nil,
        commandExecutor: (any SSHCommandExecuting)? = nil,
        terminalShellClient: (any TerminalShellClient)? = nil,
        moshPreparationClient: (any MoshPreparationClient)? = nil,
        moshRuntimeClient: (any MoshRuntimeClient)? = nil,
        sftpClient: any SFTPDirectoryListingClient = PreviewSFTPDirectoryListingClient(),
        portForwardingClient: any PortForwardingClient = PreviewPortForwardingClient()
    ) {
        self.hosts = hosts
        self.portForwardRules = portForwardRules.map { rule in
            var inactiveRule = rule
            inactiveRule.isActive = false
            return inactiveRule
        }
        self.snippets = snippets
        self.sftpItems = sftpItems
        self.keys = keys
        self.certificates = certificates
        self.identities = identities
        self.hostGroupProfiles = hostGroupProfiles
        self.sessionLogs = sessionLogs
        self.terminalWorkspaces = terminalWorkspaces
        self.terminalWorkspaceTemplates = terminalWorkspaceTemplates
        self.history = history
        self.knownHosts = knownHosts
        self.connectionClient = connectionClient
        self.credentialVault = credentialVault
        self.commandExecutor = commandExecutor
        self.terminalShellClient = terminalShellClient
        self.moshPreparationClient = moshPreparationClient
        self.moshRuntimeClient = moshRuntimeClient
        self.sftpClient = sftpClient
        self.portForwardingClient = portForwardingClient
    }

    convenience init(repository: JSONHostRepository, credentialVault: CredentialVault) throws {
        let snapshot = try repository.load()
        self.init(
            hosts: snapshot.hosts,
            portForwardRules: snapshot.portForwardRules,
            snippets: snapshot.snippets,
            sftpItems: snapshot.sftpItems,
            keys: snapshot.keys,
            certificates: snapshot.certificates,
            identities: snapshot.identities,
            hostGroupProfiles: snapshot.hostGroupProfiles,
            sessionLogs: snapshot.sessionLogs,
            terminalWorkspaces: snapshot.terminalWorkspaces,
            terminalWorkspaceTemplates: snapshot.terminalWorkspaceTemplates,
            history: snapshot.history,
            knownHosts: snapshot.knownHosts
        )
        self.repository = repository
        self.credentialVault = credentialVault
        let commandExecutor = CitadelCommandExecutor()
        self.commandExecutor = commandExecutor
        self.terminalShellClient = CitadelTerminalShellClient()
        self.moshPreparationClient = CitadelMoshPreparationClient()
        self.moshRuntimeClient = MoshRuntimeClientBridge()
        self.sftpClient = CitadelSFTPDirectoryListingClient()
        self.portForwardingClient = CitadelPortForwardingClient()
    }

    func clearSFTPStateIfNeeded(forHostID hostID: ShellHost.ID) {
        guard selectedSFTPHostID == hostID else { return }
        selectedSFTPHostID = nil
        sftpItems = []
        downloadedSFTPFile = nil
        sftpErrorMessage = nil
        isSFTPLoading = false
    }

}
