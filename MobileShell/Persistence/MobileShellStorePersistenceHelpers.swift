import Foundation

extension MobileShellStore {
    func storedPassword(for hostID: ShellHost.ID) -> String? {
        guard let credentialVault else { return nil }

        do {
            guard let password = try credentialVault.password(forHostID: hostID)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !password.isEmpty
            else {
                return nil
            }
            return password
        } catch {
            return nil
        }
    }

    func storedIdentityPassword(for identityID: SSHIdentity.ID) -> String? {
        guard let credentialVault else { return nil }

        do {
            guard let password = try credentialVault.password(forIdentityID: identityID)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !password.isEmpty
            else {
                return nil
            }
            return password
        } catch {
            return nil
        }
    }

    func storedPrivateKey(for keyID: SSHKey.ID) -> String? {
        guard let credentialVault else { return nil }

        do {
            guard let privateKey = try credentialVault.privateKey(forKeyID: keyID)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !privateKey.isEmpty
            else {
                return nil
            }
            return privateKey
        } catch {
            return nil
        }
    }

    func storedCertificate(for certificateID: SSHCertificate.ID) -> String? {
        guard let credentialVault else { return nil }

        do {
            guard let certificate = try credentialVault.certificate(forCertificateID: certificateID)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !certificate.isEmpty
            else {
                return nil
            }
            return certificate
        } catch {
            return nil
        }
    }

    func persistSnapshot() throws {
        guard let repository else { return }
        try repository.save(
            HostPersistenceSnapshot(
                hosts: hosts,
                portForwardRules: portForwardRules,
                snippets: snippets,
                sftpItems: sftpItems,
                keys: keys,
                certificates: certificates,
                identities: identities,
                hostGroupProfiles: hostGroupProfiles,
                sessionLogs: sessionLogs,
                terminalWorkspaces: terminalWorkspaces,
                terminalWorkspaceTemplates: terminalWorkspaceTemplates,
                history: history,
                knownHosts: knownHosts
            )
        )
    }
}
