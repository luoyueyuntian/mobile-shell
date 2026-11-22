import Foundation
import Security

struct HostPersistenceSnapshot: Codable, Equatable {
    var hosts: [ShellHost]
    var portForwardRules: [PortForwardRule]
    var snippets: [ShellSnippet]
    var sftpItems: [SFTPItem]
    var keys: [SSHKey]
    var certificates: [SSHCertificate]
    var identities: [SSHIdentity]
    var hostGroupProfiles: [HostGroupProfile]
    var sessionLogs: [SessionLog]
    var terminalWorkspaces: [TerminalWorkspace]
    var terminalWorkspaceTemplates: [TerminalWorkspaceTemplate]
    var history: [String]
    var knownHosts: [KnownHost]

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
        knownHosts: [KnownHost] = []
    ) {
        self.hosts = hosts
        self.portForwardRules = portForwardRules
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
    }

    private enum CodingKeys: String, CodingKey {
        case hosts
        case portForwardRules
        case snippets
        case sftpItems
        case keys
        case certificates
        case identities
        case hostGroupProfiles
        case sessionLogs
        case terminalWorkspaces
        case terminalWorkspaceTemplates
        case history
        case knownHosts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hosts = try container.decodeIfPresent([ShellHost].self, forKey: .hosts) ?? []
        portForwardRules = try container.decodeIfPresent([PortForwardRule].self, forKey: .portForwardRules) ?? []
        snippets = try container.decodeIfPresent([ShellSnippet].self, forKey: .snippets) ?? []
        sftpItems = try container.decodeIfPresent([SFTPItem].self, forKey: .sftpItems) ?? []
        keys = try container.decodeIfPresent([SSHKey].self, forKey: .keys) ?? []
        certificates = try container.decodeIfPresent([SSHCertificate].self, forKey: .certificates) ?? []
        identities = try container.decodeIfPresent([SSHIdentity].self, forKey: .identities) ?? []
        hostGroupProfiles = try container.decodeIfPresent([HostGroupProfile].self, forKey: .hostGroupProfiles) ?? []
        sessionLogs = try container.decodeIfPresent([SessionLog].self, forKey: .sessionLogs) ?? []
        terminalWorkspaces = try container.decodeIfPresent([TerminalWorkspace].self, forKey: .terminalWorkspaces) ?? []
        terminalWorkspaceTemplates = try container.decodeIfPresent([TerminalWorkspaceTemplate].self, forKey: .terminalWorkspaceTemplates) ?? []
        history = try container.decodeIfPresent([String].self, forKey: .history) ?? []
        knownHosts = try container.decodeIfPresent([KnownHost].self, forKey: .knownHosts) ?? []
    }
}

struct JSONHostRepository {
    let fileURL: URL

    init(fileURL: URL = JSONHostRepository.defaultFileURL()) {
        self.fileURL = fileURL
    }

    func load() throws -> HostPersistenceSnapshot {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return HostPersistenceSnapshot()
        }

        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(HostPersistenceSnapshot.self, from: data)
    }

    func save(_ snapshot: HostPersistenceSnapshot) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: [.atomic])
    }

    private static func defaultFileURL() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return baseURL
            .appendingPathComponent("MobileShell", isDirectory: true)
            .appendingPathComponent("hosts.json")
    }
}

protocol CredentialVault {
    func savePassword(_ password: String, forHostID hostID: UUID) throws
    func password(forHostID hostID: UUID) throws -> String?
    func deletePassword(forHostID hostID: UUID) throws
    func savePassword(_ password: String, forIdentityID identityID: UUID) throws
    func password(forIdentityID identityID: UUID) throws -> String?
    func deletePassword(forIdentityID identityID: UUID) throws
    func savePrivateKey(_ privateKey: String, forKeyID keyID: UUID) throws
    func privateKey(forKeyID keyID: UUID) throws -> String?
    func deletePrivateKey(forKeyID keyID: UUID) throws
    func saveCertificate(_ certificate: String, forCertificateID certificateID: UUID) throws
    func certificate(forCertificateID certificateID: UUID) throws -> String?
    func deleteCertificate(forCertificateID certificateID: UUID) throws
}

enum CredentialVaultError: Error, Equatable {
    case invalidData
    case keychainStatus(OSStatus)
}

final class InMemoryCredentialVault: CredentialVault {
    private var passwords: [UUID: String] = [:]
    private var identityPasswords: [UUID: String] = [:]
    private var privateKeys: [UUID: String] = [:]
    private var certificates: [UUID: String] = [:]

    func savePassword(_ password: String, forHostID hostID: UUID) throws {
        passwords[hostID] = password
    }

    func password(forHostID hostID: UUID) throws -> String? {
        passwords[hostID]
    }

    func deletePassword(forHostID hostID: UUID) throws {
        passwords.removeValue(forKey: hostID)
    }

    func savePassword(_ password: String, forIdentityID identityID: UUID) throws {
        identityPasswords[identityID] = password
    }

    func password(forIdentityID identityID: UUID) throws -> String? {
        identityPasswords[identityID]
    }

    func deletePassword(forIdentityID identityID: UUID) throws {
        identityPasswords.removeValue(forKey: identityID)
    }

    func savePrivateKey(_ privateKey: String, forKeyID keyID: UUID) throws {
        privateKeys[keyID] = privateKey
    }

    func privateKey(forKeyID keyID: UUID) throws -> String? {
        privateKeys[keyID]
    }

    func deletePrivateKey(forKeyID keyID: UUID) throws {
        privateKeys.removeValue(forKey: keyID)
    }

    func saveCertificate(_ certificate: String, forCertificateID certificateID: UUID) throws {
        certificates[certificateID] = certificate
    }

    func certificate(forCertificateID certificateID: UUID) throws -> String? {
        certificates[certificateID]
    }

    func deleteCertificate(forCertificateID certificateID: UUID) throws {
        certificates.removeValue(forKey: certificateID)
    }
}

struct KeychainCredentialVault: CredentialVault {
    private let service: String

    init(service: String = "com.local.MobileShell.host-passwords") {
        self.service = service
    }

    func savePassword(_ password: String, forHostID hostID: UUID) throws {
        try saveSecret(password, account: hostID.uuidString)
    }

    func password(forHostID hostID: UUID) throws -> String? {
        try secret(account: hostID.uuidString)
    }

    func deletePassword(forHostID hostID: UUID) throws {
        try deleteSecret(account: hostID.uuidString)
    }

    func savePassword(_ password: String, forIdentityID identityID: UUID) throws {
        try saveSecret(password, account: identityPasswordAccount(for: identityID))
    }

    func password(forIdentityID identityID: UUID) throws -> String? {
        try secret(account: identityPasswordAccount(for: identityID))
    }

    func deletePassword(forIdentityID identityID: UUID) throws {
        try deleteSecret(account: identityPasswordAccount(for: identityID))
    }

    func savePrivateKey(_ privateKey: String, forKeyID keyID: UUID) throws {
        try saveSecret(privateKey, account: privateKeyAccount(for: keyID))
    }

    func privateKey(forKeyID keyID: UUID) throws -> String? {
        try secret(account: privateKeyAccount(for: keyID))
    }

    func deletePrivateKey(forKeyID keyID: UUID) throws {
        try deleteSecret(account: privateKeyAccount(for: keyID))
    }

    func saveCertificate(_ certificate: String, forCertificateID certificateID: UUID) throws {
        try saveSecret(certificate, account: certificateAccount(for: certificateID))
    }

    func certificate(forCertificateID certificateID: UUID) throws -> String? {
        try secret(account: certificateAccount(for: certificateID))
    }

    func deleteCertificate(forCertificateID certificateID: UUID) throws {
        try deleteSecret(account: certificateAccount(for: certificateID))
    }

    private func saveSecret(_ value: String, account: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw CredentialVaultError.invalidData
        }

        try deleteSecret(account: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CredentialVaultError.keychainStatus(status)
        }
    }

    private func secret(account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw CredentialVaultError.keychainStatus(status)
        }
        guard let data = result as? Data else {
            throw CredentialVaultError.invalidData
        }
        return String(data: data, encoding: .utf8)
    }

    private func deleteSecret(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialVaultError.keychainStatus(status)
        }
    }

    private func privateKeyAccount(for keyID: UUID) -> String {
        "ssh-key-\(keyID.uuidString)"
    }

    private func certificateAccount(for certificateID: UUID) -> String {
        "ssh-certificate-\(certificateID.uuidString)"
    }

    private func identityPasswordAccount(for identityID: UUID) -> String {
        "identity-\(identityID.uuidString)"
    }
}
