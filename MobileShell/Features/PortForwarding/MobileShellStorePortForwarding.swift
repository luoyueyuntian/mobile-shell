import Foundation

extension MobileShellStore {
    @MainActor
    func togglePortForwardRule(_ rule: PortForwardRule) async {
        guard let index = portForwardRules.firstIndex(where: { $0.id == rule.id }) else { return }
        let storedRule = portForwardRules[index]

        if activePortForwardSessions[storedRule.id] != nil {
            await stopPortForwardSession(for: storedRule.id)
            portForwardRules[index].isActive = false
            portForwardErrorMessage = nil
            history.insert("Stopped port forward \(storedRule.name)", at: 0)
            return
        }

        guard let host = portForwardHost(for: storedRule) else {
            portForwardRules[index].isActive = false
            portForwardErrorMessage = "Port forward error: No SSH host is linked to \(storedRule.name)"
            return
        }

        do {
            let request = try SSHConnectionRequestBuilder(
                credentialVault: credentialVault,
                hosts: hosts,
                identities: identities,
                keys: keys,
                certificates: certificates,
                hostGroupProfiles: hostGroupProfiles,
                knownHosts: knownHosts
            ).request(for: host)
            let session = try await portForwardingClient.start(rule: storedRule, using: request)
            activePortForwardSessions[storedRule.id] = session
            portForwardRules[index].isActive = true
            portForwardErrorMessage = nil
            history.insert("Started port forward \(storedRule.name)", at: 0)
        } catch {
            if recordHostKeyChallenge(error, action: .portForward(ruleID: storedRule.id)) {
                portForwardRules[index].isActive = false
                activePortForwardSessions[storedRule.id] = nil
                portForwardErrorMessage = nil
                return
            }
            portForwardRules[index].isActive = false
            activePortForwardSessions[storedRule.id] = nil
            portForwardErrorMessage = "Port forward error: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func addPortForwardRule(
        kind: PortForwardKind = .local,
        name: String,
        sshHostID: ShellHost.ID?,
        localHost: String = "127.0.0.1",
        localPort: Int,
        remoteHost: String,
        remotePort: Int
    ) -> PortForwardRule? {
        guard let rule = makePortForwardRule(
            kind: kind,
            name: name,
            sshHostID: sshHostID,
            localHost: localHost,
            localPort: localPort,
            remoteHost: remoteHost,
            remotePort: remotePort
        ) else { return nil }

        portForwardRules.append(rule)
        portForwardErrorMessage = nil
        history.insert("Added port forward \(rule.name)", at: 0)
        try? persistSnapshot()
        return rule
    }

    @MainActor
    @discardableResult
    func updatePortForwardRule(
        _ rule: PortForwardRule,
        kind: PortForwardKind = .local,
        name: String,
        sshHostID: ShellHost.ID?,
        localHost: String = "127.0.0.1",
        localPort: Int,
        remoteHost: String,
        remotePort: Int
    ) async -> PortForwardRule? {
        guard let index = portForwardRules.firstIndex(where: { $0.id == rule.id }),
              let updatedRule = makePortForwardRule(
                id: rule.id,
                kind: kind,
                name: name,
                sshHostID: sshHostID,
                localHost: localHost,
                localPort: localPort,
                remoteHost: remoteHost,
                remotePort: remotePort
              )
        else { return nil }

        await stopPortForwardSession(for: rule.id)
        portForwardRules[index] = updatedRule
        portForwardErrorMessage = nil
        history.insert("Updated port forward \(updatedRule.name)", at: 0)
        try? persistSnapshot()
        return updatedRule
    }

    @MainActor
    func deletePortForwardRule(_ rule: PortForwardRule) async {
        guard let index = portForwardRules.firstIndex(where: { $0.id == rule.id }) else { return }
        let storedRule = portForwardRules[index]

        await stopPortForwardSession(for: storedRule.id)
        portForwardRules.remove(at: index)
        portForwardErrorMessage = nil
        history.insert("Deleted port forward \(storedRule.name)", at: 0)
        try? persistSnapshot()
    }

    @MainActor
    func stopPortForwardSession(for ruleID: PortForwardRule.ID) async {
        guard let session = activePortForwardSessions[ruleID] else { return }
        await session.stop()
        activePortForwardSessions[ruleID] = nil
    }

    private func portForwardHost(for rule: PortForwardRule) -> ShellHost? {
        if let sshHostID = rule.sshHostID,
           let host = hosts.first(where: { $0.id == sshHostID }) {
            return host
        }

        let target = rule.remoteHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return hosts.first { host in
            host.name.lowercased() == target ||
                host.address.lowercased() == target ||
                host.endpoint.lowercased() == target
        }
    }

    private func makePortForwardRule(
        id: UUID = UUID(),
        kind: PortForwardKind = .local,
        name: String,
        sshHostID: ShellHost.ID?,
        localHost: String = "127.0.0.1",
        localPort: Int,
        remoteHost: String,
        remotePort: Int
    ) -> PortForwardRule? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLocalHost = localHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRemoteHost = remoteHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !trimmedName.isEmpty,
            (1...65_535).contains(localPort)
        else {
            portForwardErrorMessage = "Port forward error: Enter a name, host, and valid ports."
            return nil
        }
        if kind != .dynamic {
            guard !trimmedRemoteHost.isEmpty, (1...65_535).contains(remotePort) else {
                portForwardErrorMessage = "Port forward error: Enter a name, host, and valid ports."
                return nil
            }
        }

        return PortForwardRule(
            id: id,
            kind: kind,
            name: trimmedName,
            sshHostID: sshHostID,
            localHost: trimmedLocalHost.isEmpty ? "127.0.0.1" : trimmedLocalHost,
            localPort: localPort,
            remoteHost: trimmedRemoteHost,
            remotePort: remotePort,
            isActive: false
        )
    }
}
