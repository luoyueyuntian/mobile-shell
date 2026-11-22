import Foundation

extension MobileShellStore {
    func filteredHosts() -> [ShellHost] {
        var filteredHosts = hosts

        if let selectedHostTag {
            filteredHosts = filteredHosts.filter { host in
                host.tags.contains {
                    $0.caseInsensitiveCompare(selectedHostTag) == .orderedSame
                }
            }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return filteredHosts }

        return filteredHosts.filter { host in
            let searchableParts = [
                host.name,
                host.address,
                host.username,
                host.group
            ] + host.tags

            return searchableParts.contains { $0.lowercased().contains(query) }
        }
    }

    func hostTags() -> [String] {
        var tagsByLowercase: [String: String] = [:]

        for tag in hosts.flatMap(\.tags) {
            let trimmedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTag.isEmpty else { continue }

            let key = trimmedTag.lowercased()
            if tagsByLowercase[key] == nil {
                tagsByLowercase[key] = trimmedTag
            }
        }

        return tagsByLowercase.values.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    func selectHostTag(_ tag: String) {
        let trimmedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        selectedHostTag = trimmedTag.isEmpty ? nil : trimmedTag
    }

    func clearSelectedHostTag() {
        selectedHostTag = nil
    }

    func authenticationSummary(for host: ShellHost) -> HostAuthenticationSummary {
        if let identityID = host.identityID {
            return identityAuthenticationSummary(
                identityID: identityID,
                prefix: "Identity",
                missingText: "Missing identity"
            )
        }

        if let identityID = hostGroupProfile(for: host)?.identityID {
            return identityAuthenticationSummary(
                identityID: identityID,
                prefix: "Group Identity",
                missingText: "Missing group identity"
            )
        }

        let hasPassword = storedPassword(for: host.id) != nil

        guard let sshKeyID = host.sshKeyID else {
            return hasPassword
                ? HostAuthenticationSummary(text: "Password", symbolName: "lock.fill", isReady: true)
                : HostAuthenticationSummary(text: "No credential", symbolName: "exclamationmark.lock.fill", isReady: false)
        }

        guard let key = keys.first(where: { $0.id == sshKeyID }) else {
            return hasPassword
                ? HostAuthenticationSummary(text: "Password (missing SSH key)", symbolName: "exclamationmark.triangle.fill", isReady: true)
                : HostAuthenticationSummary(text: "Missing SSH key", symbolName: "exclamationmark.triangle.fill", isReady: false)
        }

        guard storedPrivateKey(for: key.id) != nil else {
            return hasPassword
                ? HostAuthenticationSummary(text: "Password (key unavailable)", symbolName: "exclamationmark.triangle.fill", isReady: true)
                : HostAuthenticationSummary(text: "Missing private key", symbolName: "exclamationmark.triangle.fill", isReady: false)
        }

        let certificateText = availableCertificateSummary(for: key).map { " + \($0)" } ?? ""
        if hasPassword {
            return HostAuthenticationSummary(
                text: "Password + SSH key: \(key.name)\(certificateText)",
                symbolName: "key.horizontal.fill",
                isReady: true
            )
        }

        return HostAuthenticationSummary(
            text: "SSH key: \(key.name)\(certificateText)",
            symbolName: "key.fill",
            isReady: true
        )
    }

    func hostGroupProfile(for host: ShellHost) -> HostGroupProfile? {
        hostGroupProfiles.first {
            $0.name.caseInsensitiveCompare(host.group) == .orderedSame
        }
    }

    func routeSummary(for host: ShellHost) -> String? {
        guard let jumpHostID = jumpHostID(for: host) else { return nil }

        guard let jumpHost = hosts.first(where: { $0.id == jumpHostID }) else {
            return "Missing jump host"
        }

        return "Via \(jumpHost.name)"
    }

    func terminalTheme(for host: ShellHost) -> TerminalTheme {
        host.terminalTheme ?? hostGroupProfile(for: host)?.terminalTheme ?? .obsidianNeon
    }

    func terminalFontSize(for host: ShellHost) -> TerminalFontSize {
        host.terminalFontSize ?? hostGroupProfile(for: host)?.terminalFontSize ?? .standard
    }

    func environmentVariables(for host: ShellHost) -> [ShellEnvironmentVariable] {
        let groupVariables = hostGroupProfile(for: host)?.environmentVariables ?? []
        var valuesByKey = Dictionary(uniqueKeysWithValues: groupVariables.map { ($0.key, $0.value) })

        for variable in host.environmentVariables {
            valuesByKey[variable.key] = variable.value
        }

        return valuesByKey.keys
            .sorted()
            .compactMap { key in
                valuesByKey[key].map { ShellEnvironmentVariable(key: key, value: $0) }
            }
    }

    @discardableResult
    func addHost(
        name: String,
        address: String,
        username: String,
        group: String,
        tags: String,
        protocol: RemoteAccessProtocol = .ssh,
        moshConfiguration: MoshHostConfiguration? = nil,
        sshKeyID: SSHKey.ID? = nil,
        identityID: SSHIdentity.ID? = nil,
        jumpHostID: ShellHost.ID? = nil,
        startupSnippetID: ShellSnippet.ID? = nil,
        terminalTheme: TerminalTheme? = nil,
        terminalFontSize: TerminalFontSize? = nil,
        environmentVariables: [ShellEnvironmentVariable] = []
    ) -> ShellHost {
        let host = makeHost(
            name: name,
            address: address,
            username: username,
            group: group,
            tags: tags,
            protocol: `protocol`,
            moshConfiguration: moshConfiguration,
            sshKeyID: sshKeyID,
            identityID: identityID,
            jumpHostID: jumpHostID,
            startupSnippetID: startupSnippetID,
            terminalTheme: terminalTheme,
            terminalFontSize: terminalFontSize,
            environmentVariables: environmentVariables
        )
        hosts.append(host)
        try? persistSnapshot()
        return host
    }

    @discardableResult
    func addHost(
        name: String,
        address: String,
        username: String,
        group: String,
        tags: String,
        password: String,
        protocol: RemoteAccessProtocol = .ssh,
        moshConfiguration: MoshHostConfiguration? = nil,
        sshKeyID: SSHKey.ID? = nil,
        identityID: SSHIdentity.ID? = nil,
        jumpHostID: ShellHost.ID? = nil,
        startupSnippetID: ShellSnippet.ID? = nil,
        terminalTheme: TerminalTheme? = nil,
        terminalFontSize: TerminalFontSize? = nil,
        environmentVariables: [ShellEnvironmentVariable] = []
    ) throws -> ShellHost {
        let host = makeHost(
            name: name,
            address: address,
            username: username,
            group: group,
            tags: tags,
            protocol: `protocol`,
            moshConfiguration: moshConfiguration,
            sshKeyID: sshKeyID,
            identityID: identityID,
            jumpHostID: jumpHostID,
            startupSnippetID: startupSnippetID,
            terminalTheme: terminalTheme,
            terminalFontSize: terminalFontSize,
            environmentVariables: environmentVariables
        )
        hosts.append(host)
        if !password.isEmpty {
            try credentialVault?.savePassword(password, forHostID: host.id)
        }
        try persistSnapshot()
        return host
    }

    @discardableResult
    func addHost(
        name: String,
        address: String,
        port: Int,
        username: String,
        group: String,
        tags: String,
        password: String,
        protocol: RemoteAccessProtocol = .ssh,
        moshConfiguration: MoshHostConfiguration? = nil,
        sshKeyID: SSHKey.ID? = nil,
        identityID: SSHIdentity.ID? = nil,
        jumpHostID: ShellHost.ID? = nil,
        startupSnippetID: ShellSnippet.ID? = nil,
        terminalTheme: TerminalTheme? = nil,
        terminalFontSize: TerminalFontSize? = nil,
        environmentVariables: [ShellEnvironmentVariable] = []
    ) throws -> ShellHost {
        let host = makeHost(
            name: name,
            address: address,
            port: port,
            username: username,
            group: group,
            tags: tags,
            protocol: `protocol`,
            moshConfiguration: moshConfiguration,
            sshKeyID: sshKeyID,
            identityID: identityID,
            jumpHostID: jumpHostID,
            startupSnippetID: startupSnippetID,
            terminalTheme: terminalTheme,
            terminalFontSize: terminalFontSize,
            environmentVariables: environmentVariables
        )
        hosts.append(host)
        if !password.isEmpty {
            try credentialVault?.savePassword(password, forHostID: host.id)
        }
        try persistSnapshot()
        return host
    }

    @discardableResult
    func updateHost(
        _ host: ShellHost,
        name: String,
        address: String,
        port: Int,
        username: String,
        group: String,
        tags: String,
        password: String,
        protocol: RemoteAccessProtocol = .ssh,
        moshConfiguration: MoshHostConfiguration? = nil,
        sshKeyID: SSHKey.ID? = nil,
        identityID: SSHIdentity.ID? = nil,
        jumpHostID: ShellHost.ID? = nil,
        startupSnippetID: ShellSnippet.ID? = nil,
        terminalTheme: TerminalTheme? = nil,
        terminalFontSize: TerminalFontSize? = nil,
        environmentVariables: [ShellEnvironmentVariable] = []
    ) throws -> ShellHost? {
        guard let index = hosts.firstIndex(where: { $0.id == host.id }) else { return nil }
        let previousProtocol = hosts[index].protocol
        let updatedHost = makeHost(
            id: host.id,
            name: name,
            address: address,
            port: port,
            username: username,
            group: group,
            tags: tags,
            protocol: `protocol`,
            moshConfiguration: moshConfiguration,
            status: hosts[index].status,
            sshKeyID: sshKeyID,
            identityID: identityID,
            jumpHostID: jumpHostID,
            startupSnippetID: startupSnippetID,
            terminalTheme: terminalTheme,
            terminalFontSize: terminalFontSize,
            environmentVariables: environmentVariables
        )

        hosts[index] = updatedHost
        if previousProtocol != .mosh, updatedHost.protocol == .mosh {
            clearTerminalState(forHostID: updatedHost.id)
        } else {
            updateOpenTerminalSessions(for: updatedHost)
        }

        if !password.isEmpty {
            try credentialVault?.savePassword(password, forHostID: updatedHost.id)
        }

        history.insert("Updated host \(updatedHost.name)", at: 0)
        try persistSnapshot()
        return updatedHost
    }

    @MainActor
    func deleteHost(_ host: ShellHost) async {
        guard let index = hosts.firstIndex(where: { $0.id == host.id }) else { return }
        let storedHost = hosts[index]
        let linkedRuleIDs = portForwardRules
            .filter { $0.sshHostID == storedHost.id }
            .map(\.id)

        for ruleID in linkedRuleIDs {
            await stopPortForwardSession(for: ruleID)
        }

        hosts.remove(at: index)
        portForwardRules.removeAll { $0.sshHostID == storedHost.id }
        clearTerminalState(forHostID: storedHost.id)
        clearSFTPStateIfNeeded(forHostID: storedHost.id)
        try? credentialVault?.deletePassword(forHostID: storedHost.id)
        portForwardErrorMessage = nil
        history.insert("Deleted host \(storedHost.name)", at: 0)
        try? persistSnapshot()
    }

    @discardableResult
    func importOpenSSHConfig(_ config: String) -> [ShellHost] {
        var importedHosts: [ShellHost] = []
        var existingNames = Set(hosts.map { $0.name.lowercased() })
        var currentAliases: [String] = []
        var currentOptions: [String: String] = [:]

        func finishCurrentBlock() {
            let aliases = currentAliases
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && !containsOpenSSHWildcard($0) }

            guard !aliases.isEmpty else { return }

            let hostName = currentOptions["hostname"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let username = currentOptions["user"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let port = currentOptions["port"].flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            let resolvedPort = normalizePort(port ?? 22)

            for alias in aliases where !existingNames.contains(alias.lowercased()) {
                let host = ShellHost(
                    id: UUID(),
                    name: alias,
                    address: hostName?.isEmpty == false ? hostName! : alias,
                    port: resolvedPort,
                    username: username?.isEmpty == false ? username! : "root",
                    group: "Imported",
                    tags: ["ssh", "imported"],
                    status: .idle
                )
                importedHosts.append(host)
                existingNames.insert(alias.lowercased())
            }
        }

        for rawLine in config.split(whereSeparator: \.isNewline) {
            guard let directive = parseOpenSSHDirective(String(rawLine)) else { continue }

            if directive.key == "host" {
                finishCurrentBlock()
                currentAliases = splitOpenSSHWords(directive.value)
                currentOptions = [:]
            } else if !currentAliases.isEmpty {
                currentOptions[directive.key] = directive.value
            }
        }

        finishCurrentBlock()

        guard !importedHosts.isEmpty else { return [] }

        hosts.append(contentsOf: importedHosts)
        history.insert(
            "Imported \(importedHosts.count) OpenSSH host\(importedHosts.count == 1 ? "" : "s")",
            at: 0
        )
        try? persistSnapshot()
        return importedHosts
    }

    private func identityAuthenticationSummary(
        identityID: SSHIdentity.ID,
        prefix: String,
        missingText: String
    ) -> HostAuthenticationSummary {
        guard let identity = identities.first(where: { $0.id == identityID })
        else {
            return HostAuthenticationSummary(
                text: missingText,
                symbolName: "exclamationmark.triangle.fill",
                isReady: false
            )
        }

        let hasPassword = storedIdentityPassword(for: identity.id) != nil
        let title = "\(prefix): \(identity.name)"

        guard let sshKeyID = identity.sshKeyID else {
            return hasPassword
                ? HostAuthenticationSummary(text: "\(title) (Password)", symbolName: "person.text.rectangle.fill", isReady: true)
                : HostAuthenticationSummary(text: "\(title) (No credential)", symbolName: "exclamationmark.lock.fill", isReady: false)
        }

        guard let key = keys.first(where: { $0.id == sshKeyID }) else {
            return hasPassword
                ? HostAuthenticationSummary(text: "\(title) (Password; missing SSH key)", symbolName: "exclamationmark.triangle.fill", isReady: true)
                : HostAuthenticationSummary(text: "\(title) (Missing SSH key)", symbolName: "exclamationmark.triangle.fill", isReady: false)
        }

        guard storedPrivateKey(for: key.id) != nil else {
            return hasPassword
                ? HostAuthenticationSummary(text: "\(title) (Password; key unavailable)", symbolName: "exclamationmark.triangle.fill", isReady: true)
                : HostAuthenticationSummary(text: "\(title) (Missing private key)", symbolName: "exclamationmark.triangle.fill", isReady: false)
        }

        let certificateText = availableCertificateSummary(for: key).map { " + \($0)" } ?? ""
        if hasPassword {
            return HostAuthenticationSummary(
                text: "\(title) (Password + SSH key: \(key.name)\(certificateText))",
                symbolName: "person.text.rectangle.fill",
                isReady: true
            )
        }

        return HostAuthenticationSummary(
            text: "\(title) (SSH key: \(key.name)\(certificateText))",
            symbolName: "person.text.rectangle.fill",
            isReady: true
        )
    }

    private func availableCertificateSummary(for key: SSHKey) -> String? {
        guard let certificate = linkedCertificate(for: key),
              storedCertificate(for: certificate.id) != nil
        else {
            return nil
        }

        return "certificate: \(certificate.name)"
    }

    private func jumpHostID(for host: ShellHost) -> ShellHost.ID? {
        host.jumpHostID ?? hostGroupProfile(for: host)?.jumpHostID
    }

    private func parseOpenSSHDirective(_ rawLine: String) -> (key: String, value: String)? {
        let trimmedLine = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLine.isEmpty, !trimmedLine.hasPrefix("#") else { return nil }

        let uncommentedLine = trimmedLine.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !uncommentedLine.isEmpty else { return nil }

        if let equalsIndex = uncommentedLine.firstIndex(of: "=") {
            let key = uncommentedLine[..<equalsIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = uncommentedLine[uncommentedLine.index(after: equalsIndex)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return normalizedOpenSSHDirective(key: key, value: value)
        }

        guard let separator = uncommentedLine.firstIndex(where: { $0.isWhitespace }) else { return nil }

        let key = uncommentedLine[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
        let value = uncommentedLine[separator...].trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedOpenSSHDirective(key: key, value: value)
    }

    private func normalizedOpenSSHDirective(key: String, value: String) -> (key: String, value: String)? {
        let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedKey.isEmpty, !normalizedValue.isEmpty else { return nil }
        return (normalizedKey, normalizedValue)
    }

    private func splitOpenSSHWords(_ value: String) -> [String] {
        value
            .split(whereSeparator: \.isWhitespace)
            .map { word in
                String(word).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
    }

    private func containsOpenSSHWildcard(_ value: String) -> Bool {
        value.contains("*") || value.contains("?") || value.contains("!")
    }

    private func makeHost(
        id: UUID = UUID(),
        name: String,
        address: String,
        port: Int? = nil,
        username: String,
        group: String,
        tags: String,
        protocol: RemoteAccessProtocol = .ssh,
        moshConfiguration: MoshHostConfiguration? = nil,
        status: HostStatus = .idle,
        sshKeyID: SSHKey.ID? = nil,
        identityID: SSHIdentity.ID? = nil,
        jumpHostID: ShellHost.ID? = nil,
        startupSnippetID: ShellSnippet.ID? = nil,
        terminalTheme: TerminalTheme? = nil,
        terminalFontSize: TerminalFontSize? = nil,
        environmentVariables: [ShellEnvironmentVariable] = []
    ) -> ShellHost {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedAddress = parseAddressAndPort(address)
        let resolvedPort = normalizePort(port ?? parsedAddress.port)
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedGroup = group.trimmingCharacters(in: .whitespacesAndNewlines)
        let accessProtocol = `protocol`
        let parsedTags = tags
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return ShellHost(
            id: id,
            name: trimmedName.isEmpty ? parsedAddress.host : trimmedName,
            address: parsedAddress.host,
            port: resolvedPort,
            username: trimmedUsername.isEmpty ? "root" : trimmedUsername,
            group: trimmedGroup.isEmpty ? "Ungrouped" : trimmedGroup,
            tags: parsedTags.isEmpty ? [accessProtocol == .mosh ? "mosh" : "ssh"] : parsedTags,
            status: status,
            sshKeyID: sshKeyID,
            identityID: identityID,
            jumpHostID: jumpHostID,
            protocol: accessProtocol,
            moshConfiguration: moshConfiguration,
            startupSnippetID: startupSnippetID,
            terminalTheme: terminalTheme,
            terminalFontSize: terminalFontSize,
            environmentVariables: environmentVariables
        )
    }

    private func parseAddressAndPort(_ address: String) -> (host: String, port: Int) {
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultPort = 22

        guard
            let separator = trimmedAddress.lastIndex(of: ":"),
            trimmedAddress.firstIndex(of: ":") == separator
        else {
            return (trimmedAddress, defaultPort)
        }

        let host = trimmedAddress[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
        let portText = trimmedAddress[trimmedAddress.index(after: separator)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard
            !host.isEmpty,
            let port = Int(portText),
            (1...65_535).contains(port)
        else {
            return (trimmedAddress, defaultPort)
        }

        return (host, port)
    }

    private func normalizePort(_ port: Int) -> Int {
        (1...65_535).contains(port) ? port : 22
    }
}
