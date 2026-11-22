import Foundation

extension MobileShellStore {
    func cancelPendingHostKeyChallenge() {
        pendingHostKeyChallenge = nil
        pendingHostKeyAction = nil
    }

    @MainActor
    func trustPendingHostKey() async {
        guard let challenge = pendingHostKeyChallenge else { return }
        let action = pendingHostKeyAction

        _ = trustKnownHost(
            host: challenge.knownHostHost,
            keyType: challenge.keyType,
            fingerprint: challenge.fingerprint
        )
        pendingHostKeyChallenge = nil
        pendingHostKeyAction = nil

        guard let action else { return }
        await retryPendingHostKeyAction(action)
    }

    @discardableResult
    func trustKnownHost(host: String, keyType: String, fingerprint: String) -> KnownHost? {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKeyType = keyType.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedFingerprint = fingerprint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty, !trimmedKeyType.isEmpty, !trimmedFingerprint.isEmpty else {
            return nil
        }

        if let index = knownHosts.firstIndex(where: {
            $0.host.caseInsensitiveCompare(trimmedHost) == .orderedSame &&
                $0.keyType.caseInsensitiveCompare(trimmedKeyType) == .orderedSame
        }) {
            let updatedKnownHost = KnownHost(
                id: knownHosts[index].id,
                host: trimmedHost,
                keyType: trimmedKeyType,
                fingerprint: trimmedFingerprint
            )
            knownHosts[index] = updatedKnownHost
            persistKnownHostsChange("Updated known host \(updatedKnownHost.host)")
            return updatedKnownHost
        }

        let knownHost = KnownHost(
            host: trimmedHost,
            keyType: trimmedKeyType,
            fingerprint: trimmedFingerprint
        )
        knownHosts.append(knownHost)
        persistKnownHostsChange("Trusted known host \(knownHost.host)")
        return knownHost
    }

    func deleteKnownHost(_ knownHost: KnownHost) {
        guard let index = knownHosts.firstIndex(where: { $0.id == knownHost.id }) else { return }
        let deletedKnownHost = knownHosts.remove(at: index)
        persistKnownHostsChange("Deleted known host \(deletedKnownHost.host)")
    }
}
