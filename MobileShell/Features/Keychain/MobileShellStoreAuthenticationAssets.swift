import Foundation
import Crypto

extension MobileShellStore {
    func linkedHosts(for key: SSHKey) -> [ShellHost] {
        hosts
            .filter { $0.sshKeyID == key.id }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func linkedCertificate(for key: SSHKey) -> SSHCertificate? {
        guard let certificateID = key.certificateID else { return nil }
        return certificates.first { $0.id == certificateID }
    }

    func linkedKey(for certificate: SSHCertificate) -> SSHKey? {
        keys.first { $0.certificateID == certificate.id }
    }

    func linkedHosts(for identity: SSHIdentity) -> [ShellHost] {
        hosts
            .filter { $0.identityID == identity.id }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    @discardableResult
    func addSSHKey(name: String, kind: String, privateKey: String) throws -> SSHKey? {
        let trimmedPrivateKey = privateKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let key = makeSSHKey(name: name, kind: kind, privateKey: trimmedPrivateKey) else { return nil }

        try credentialVault?.savePrivateKey(trimmedPrivateKey, forKeyID: key.id)
        keys.append(key)
        history.insert("Added SSH key \(key.name)", at: 0)
        try persistSnapshot()
        return key
    }

    @discardableResult
    func updateSSHKey(_ key: SSHKey, name: String, kind: String, privateKey: String) throws -> SSHKey? {
        guard let index = keys.firstIndex(where: { $0.id == key.id }) else { return nil }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKind = kind.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrivateKey = privateKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedKind.isEmpty else { return nil }

        var updatedKey = key
        updatedKey.name = trimmedName
        updatedKey.kind = trimmedKind
        if !trimmedPrivateKey.isEmpty {
            updatedKey.fingerprint = fingerprint(forPrivateKey: trimmedPrivateKey)
            try credentialVault?.savePrivateKey(trimmedPrivateKey, forKeyID: key.id)
        }

        keys[index] = updatedKey
        history.insert("Updated SSH key \(updatedKey.name)", at: 0)
        try persistSnapshot()
        return updatedKey
    }

    func deleteSSHKey(_ key: SSHKey) throws {
        guard let index = keys.firstIndex(where: { $0.id == key.id }) else { return }
        let storedKey = keys[index]
        let affectedHostIDs = Set(hosts.filter { $0.sshKeyID == storedKey.id }.map(\.id))
        let affectedIdentityIDs = Set(identities.filter { $0.sshKeyID == storedKey.id }.map(\.id))
        let linkedCertificateID = storedKey.certificateID

        keys.remove(at: index)
        if let linkedCertificateID {
            certificates.removeAll { $0.id == linkedCertificateID }
        }
        hosts = hosts.map { host in
            guard host.sshKeyID == storedKey.id else { return host }
            var detachedHost = host
            detachedHost.sshKeyID = nil
            return detachedHost
        }
        identities = identities.map { identity in
            guard identity.sshKeyID == storedKey.id else { return identity }
            var detachedIdentity = identity
            detachedIdentity.sshKeyID = nil
            return detachedIdentity
        }
        for host in hosts where affectedHostIDs.contains(host.id) || host.identityID.map(affectedIdentityIDs.contains) == true {
            updateOpenTerminalSessions(for: host)
        }
        try credentialVault?.deletePrivateKey(forKeyID: storedKey.id)
        if let linkedCertificateID {
            try credentialVault?.deleteCertificate(forCertificateID: linkedCertificateID)
        }
        history.insert("Deleted SSH key \(storedKey.name)", at: 0)
        try persistSnapshot()
    }

    @discardableResult
    func addSSHCertificate(
        name: String,
        kind: String,
        certificate: String,
        sshKeyID: SSHKey.ID? = nil
    ) throws -> SSHCertificate? {
        let trimmedCertificate = certificate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let sshCertificate = makeSSHCertificate(
            name: name,
            kind: kind,
            certificate: trimmedCertificate
        ) else {
            return nil
        }

        try credentialVault?.saveCertificate(trimmedCertificate, forCertificateID: sshCertificate.id)
        certificates.append(sshCertificate)
        setLinkedCertificate(sshCertificate.id, forKeyID: sshKeyID)
        if let sshKeyID {
            refreshOpenTerminalSessionsForKey(sshKeyID)
        }
        history.insert("Added SSH certificate \(sshCertificate.name)", at: 0)
        try persistSnapshot()
        return sshCertificate
    }

    @discardableResult
    func updateSSHCertificate(
        _ certificate: SSHCertificate,
        name: String,
        kind: String,
        certificate certificateMaterial: String,
        sshKeyID: SSHKey.ID? = nil
    ) throws -> SSHCertificate? {
        guard let index = certificates.firstIndex(where: { $0.id == certificate.id }) else { return nil }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKind = kind.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCertificate = certificateMaterial.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedKind.isEmpty else { return nil }

        let previouslyLinkedKeyIDs = Set(keys.filter { $0.certificateID == certificate.id }.map(\.id))
        var updatedCertificate = certificate
        updatedCertificate.name = trimmedName
        updatedCertificate.kind = trimmedKind
        if !trimmedCertificate.isEmpty {
            updatedCertificate.fingerprint = fingerprint(forKeyMaterial: trimmedCertificate)
            try credentialVault?.saveCertificate(trimmedCertificate, forCertificateID: certificate.id)
        }

        certificates[index] = updatedCertificate
        setLinkedCertificate(certificate.id, forKeyID: sshKeyID)
        let affectedKeyIDs = previouslyLinkedKeyIDs.union(sshKeyID.map { [$0] } ?? [])
        for keyID in affectedKeyIDs {
            refreshOpenTerminalSessionsForKey(keyID)
        }
        history.insert("Updated SSH certificate \(updatedCertificate.name)", at: 0)
        try persistSnapshot()
        return updatedCertificate
    }

    func deleteSSHCertificate(_ certificate: SSHCertificate) throws {
        guard let index = certificates.firstIndex(where: { $0.id == certificate.id }) else { return }
        let storedCertificate = certificates[index]
        let affectedKeyIDs = Set(keys.filter { $0.certificateID == storedCertificate.id }.map(\.id))

        certificates.remove(at: index)
        setLinkedCertificate(nil, forKeyID: nil, clearingCertificateID: storedCertificate.id)
        for keyID in affectedKeyIDs {
            refreshOpenTerminalSessionsForKey(keyID)
        }
        try credentialVault?.deleteCertificate(forCertificateID: storedCertificate.id)
        history.insert("Deleted SSH certificate \(storedCertificate.name)", at: 0)
        try persistSnapshot()
    }

    @discardableResult
    func addIdentity(
        name: String,
        username: String,
        password: String,
        sshKeyID: SSHKey.ID? = nil
    ) throws -> SSHIdentity? {
        guard let identity = makeIdentity(name: name, username: username, sshKeyID: sshKeyID) else { return nil }

        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPassword.isEmpty {
            try credentialVault?.savePassword(trimmedPassword, forIdentityID: identity.id)
        }
        identities.append(identity)
        history.insert("Added identity \(identity.name)", at: 0)
        try persistSnapshot()
        return identity
    }

    @discardableResult
    func updateIdentity(
        _ identity: SSHIdentity,
        name: String,
        username: String,
        password: String,
        sshKeyID: SSHKey.ID? = nil
    ) throws -> SSHIdentity? {
        guard let index = identities.firstIndex(where: { $0.id == identity.id }),
              let updatedIdentity = makeIdentity(
                id: identity.id,
                name: name,
                username: username,
                sshKeyID: sshKeyID
              )
        else { return nil }

        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPassword.isEmpty {
            try credentialVault?.savePassword(trimmedPassword, forIdentityID: identity.id)
        }
        identities[index] = updatedIdentity
        refreshOpenTerminalSessionsForIdentity(updatedIdentity.id)
        history.insert("Updated identity \(updatedIdentity.name)", at: 0)
        try persistSnapshot()
        return updatedIdentity
    }

    func deleteIdentity(_ identity: SSHIdentity) throws {
        guard let index = identities.firstIndex(where: { $0.id == identity.id }) else { return }
        let storedIdentity = identities[index]
        let affectedHostIDs = Set(hosts.filter { $0.identityID == storedIdentity.id }.map(\.id))

        identities.remove(at: index)
        hosts = hosts.map { host in
            guard host.identityID == storedIdentity.id else { return host }
            var detachedHost = host
            detachedHost.identityID = nil
            return detachedHost
        }
        hostGroupProfiles = hostGroupProfiles.map { profile in
            guard profile.identityID == storedIdentity.id else { return profile }
            var detachedProfile = profile
            detachedProfile.identityID = nil
            return detachedProfile
        }
        for host in hosts where affectedHostIDs.contains(host.id) {
            updateOpenTerminalSessions(for: host)
        }
        try credentialVault?.deletePassword(forIdentityID: storedIdentity.id)
        history.insert("Deleted identity \(storedIdentity.name)", at: 0)
        try persistSnapshot()
    }

    private func makeIdentity(
        id: UUID = UUID(),
        name: String,
        username: String,
        sshKeyID: SSHKey.ID?
    ) -> SSHIdentity? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedUsername.isEmpty else { return nil }

        return SSHIdentity(
            id: id,
            name: trimmedName,
            username: trimmedUsername,
            sshKeyID: sshKeyID
        )
    }

    private func makeSSHKey(id: UUID = UUID(), name: String, kind: String, privateKey: String) -> SSHKey? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKind = kind.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrivateKey = privateKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedKind.isEmpty, !trimmedPrivateKey.isEmpty else { return nil }

        return SSHKey(
            id: id,
            name: trimmedName,
            fingerprint: fingerprint(forPrivateKey: trimmedPrivateKey),
            kind: trimmedKind
        )
    }

    private func makeSSHCertificate(
        id: UUID = UUID(),
        name: String,
        kind: String,
        certificate: String
    ) -> SSHCertificate? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKind = kind.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCertificate = certificate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedKind.isEmpty, !trimmedCertificate.isEmpty else { return nil }

        return SSHCertificate(
            id: id,
            name: trimmedName,
            fingerprint: fingerprint(forKeyMaterial: trimmedCertificate),
            kind: trimmedKind
        )
    }

    private func fingerprint(forPrivateKey privateKey: String) -> String {
        fingerprint(forKeyMaterial: privateKey)
    }

    private func fingerprint(forKeyMaterial material: String) -> String {
        let digest = SHA256.hash(data: Data(material.utf8))
        let encodedDigest = Data(digest).base64EncodedString().trimmingCharacters(in: CharacterSet(charactersIn: "="))
        return "SHA256:\(encodedDigest)"
    }

    private func setLinkedCertificate(
        _ certificateID: SSHCertificate.ID?,
        forKeyID keyID: SSHKey.ID?,
        clearingCertificateID: SSHCertificate.ID? = nil
    ) {
        for index in keys.indices {
            if let clearingCertificateID, keys[index].certificateID == clearingCertificateID {
                keys[index].certificateID = nil
            }
            if let certificateID, keys[index].certificateID == certificateID {
                keys[index].certificateID = nil
            }
            if let keyID, keys[index].id == keyID {
                keys[index].certificateID = certificateID
            }
        }
    }

    private func refreshOpenTerminalSessionsForIdentity(_ identityID: SSHIdentity.ID) {
        for host in hosts where host.identityID == identityID {
            updateOpenTerminalSessions(for: host)
        }
    }

    private func refreshOpenTerminalSessionsForKey(_ keyID: SSHKey.ID) {
        let identityIDs = Set(identities.filter { $0.sshKeyID == keyID }.map(\.id))
        for host in hosts where host.sshKeyID == keyID ||
            host.identityID.map(identityIDs.contains) == true ||
            hostGroupProfile(for: host)?.identityID.map(identityIDs.contains) == true {
            updateOpenTerminalSessions(for: host)
        }
    }
}
