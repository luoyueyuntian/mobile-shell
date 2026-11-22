# SSH Certificates Design

Add personal Termius-style SSH certificate management to the local Keychain area. Termius documents SSH keys and certificates together in Keychain; MobileShell already has personal SSH keys, identities, host key references, and local Keychain-backed private material, so certificates should extend that same personal credential model without adding team vaults, cloud sync, or shared access control.

## Scope

This slice adds local SSH user certificate metadata, stores certificate material outside host JSON, links one active certificate to an SSH key, and carries the certificate material into `SSHConnectionRequest`. Hosts and identities continue to select an SSH key; when the selected key has an active linked certificate, summaries and connection requests include the certificate automatically.

This slice does not implement team certificate sharing, CA issuance flows, expiration parsing, hardware/FIDO2 support, or full Citadel/NIOSSH certificate-auth signing. Current Citadel convenience APIs expose password and private-key methods; the app will preserve certificate material on the request so a later custom authentication delegate can use it.

## Data Model

`SSHCertificate` is local metadata:

- `id`: stable UUID.
- `name`: user-facing label.
- `fingerprint`: SHA256 digest of the stored certificate material, matching the existing private-key fingerprint style.
- `kind`: certificate type label such as `user-cert` or `ed25519-cert`.

`SSHKey` gains `certificateID: SSHCertificate.ID?`, representing the one active certificate paired with that key. This keeps host and identity configuration unchanged: they select keys, and the key decides whether a certificate travels with it.

`MobileShellStore` gains `certificates: [SSHCertificate]`. `HostPersistenceSnapshot` persists certificate metadata and key links, but never persists certificate material.

## Credential Storage

`CredentialVault` gains certificate material methods:

- `saveCertificate(_:forCertificateID:)`
- `certificate(forCertificateID:)`
- `deleteCertificate(forCertificateID:)`

`InMemoryCredentialVault` stores certificates for tests. `KeychainCredentialVault` stores them under `ssh-certificate-<UUID>`, parallel to `ssh-key-<UUID>`.

## Store Behavior

Adding a certificate trims name, kind, and material; rejects empty required fields; saves material in the vault; appends metadata; and optionally links it to a key. Linking a certificate to a key replaces that key's previous `certificateID`, so request construction has one deterministic active certificate per key.

Updating a certificate keeps the ID, trims name/kind, optionally rotates material and fingerprint, and updates the key link. Deleting a certificate removes metadata, deletes vault material, clears any key link that references it, updates open sessions that depend on affected keys, records history, and persists.

Deleting an SSH key also deletes any certificate linked from that key and removes both private-key and certificate material.

## Connection Requests And Summaries

`SSHConnectionRequest` gains `certificate: String? = nil`. `SSHConnectionRequestBuilder` receives `keys` and `certificates` and resolves certificate material whenever the selected host or identity key has a linked certificate.

Authentication summaries append `+ certificate: <name>` only when both certificate metadata and certificate material are available. Missing certificate material should not hide private-key readiness, but the certificate is omitted from the positive summary so the UI does not imply it will be sent.

## UI

The Keychain screen adds a "SSH Certificates" section with add/edit/delete actions. Certificate rows show name, kind, fingerprint, and linked key. The certificate editor asks for name, kind, linked SSH key, and OpenSSH certificate text. Existing key and identity rows show certificate context when a selected key has an available linked certificate.

Host and identity editors do not gain a separate certificate picker in this slice; they keep selecting SSH keys, which keeps the interaction small and matches the active-certificate-on-key model.

## Testing

Focused tests cover:

- Certificate metadata persists separately from certificate material.
- Adding/updating/deleting certificate material in the vault.
- Key links are set and cleared deterministically.
- Host and identity connection requests include linked certificate material.
- Authentication summaries mention available linked certificates.
- Persisted JSON never contains certificate material.

## References

- Official Termius docs: https://docs.termius.com/keychain/ssh-keys-and-certificates

## Self-Review

No placeholders remain. The scope is a single personal Keychain slice. The design explicitly avoids team vaults and live certificate signing because those are larger independent subsystems.
