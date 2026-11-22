import SwiftUI

struct KeychainView: View {
    @Bindable var store: MobileShellStore
    @State private var isShowingIdentityEditor = false
    @State private var editingIdentity: SSHIdentity?
    @State private var identityPendingDelete: SSHIdentity?
    @State private var isShowingKeyEditor = false
    @State private var editingKey: SSHKey?
    @State private var keyPendingDelete: SSHKey?
    @State private var isShowingCertificateEditor = false
    @State private var editingCertificate: SSHCertificate?
    @State private var certificatePendingDelete: SSHCertificate?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Identities")
                            .font(.headline.weight(.semibold))
                        Text("Reuse personal SSH login profiles across hosts.")
                            .font(.caption)
                            .foregroundStyle(ShellColor.secondaryText)
                    }

                    Spacer()

                    Button {
                        editingIdentity = nil
                        isShowingIdentityEditor = true
                    } label: {
                        Label("Add", systemImage: "plus")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(ShellColor.accent.opacity(0.18))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(13)
                .background(ShellColor.deepPanel)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(ShellColor.pink)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(ShellColor.panel)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                if store.identities.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "person.text.rectangle")
                            .font(.title2)
                            .foregroundStyle(ShellColor.secondaryText)
                        Text("No identities yet")
                            .font(.subheadline.weight(.semibold))
                        Text("Create an identity to share a username, password, and optional SSH key across hosts.")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(ShellColor.secondaryText)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity)
                    .background(ShellColor.deepPanel)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                ForEach(store.identities) { identity in
                    SSHIdentityRow(
                        identity: identity,
                        key: identity.sshKeyID.flatMap { keyID in
                            store.keys.first(where: { $0.id == keyID })
                        },
                        certificate: identity.sshKeyID
                            .flatMap { keyID in store.keys.first(where: { $0.id == keyID }) }
                            .flatMap { store.linkedCertificate(for: $0) },
                        linkedHosts: store.linkedHosts(for: identity),
                        editAction: {
                            editingIdentity = identity
                            isShowingIdentityEditor = true
                        },
                        deleteAction: {
                            identityPendingDelete = identity
                        }
                    )
                }

                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SSH Keys")
                            .font(.headline.weight(.semibold))
                        Text("Import private keys into the local iOS Keychain.")
                            .font(.caption)
                            .foregroundStyle(ShellColor.secondaryText)
                    }

                    Spacer()

                    Button {
                        editingKey = nil
                        isShowingKeyEditor = true
                    } label: {
                        Label("Add", systemImage: "plus")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(ShellColor.accent.opacity(0.18))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(13)
                .background(ShellColor.deepPanel)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                if store.keys.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "key.fill")
                            .font(.title2)
                            .foregroundStyle(ShellColor.secondaryText)
                        Text("No SSH keys yet")
                            .font(.subheadline.weight(.semibold))
                        Text("Import a private key to keep credentials local and separate from host JSON.")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(ShellColor.secondaryText)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity)
                    .background(ShellColor.deepPanel)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                ForEach(store.keys) { key in
                    SSHKeyRow(
                        key: key,
                        certificate: store.linkedCertificate(for: key),
                        linkedHosts: store.linkedHosts(for: key),
                        editAction: {
                            editingKey = key
                            isShowingKeyEditor = true
                        },
                        deleteAction: {
                            keyPendingDelete = key
                        }
                    )
                }

                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SSH Certificates")
                            .font(.headline.weight(.semibold))
                        Text("Attach personal OpenSSH user certificates to imported keys.")
                            .font(.caption)
                            .foregroundStyle(ShellColor.secondaryText)
                    }

                    Spacer()

                    Button {
                        editingCertificate = nil
                        isShowingCertificateEditor = true
                    } label: {
                        Label("Add", systemImage: "plus")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(ShellColor.accent.opacity(0.18))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(13)
                .background(ShellColor.deepPanel)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                if store.certificates.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "seal.fill")
                            .font(.title2)
                            .foregroundStyle(ShellColor.secondaryText)
                        Text("No SSH certificates yet")
                            .font(.subheadline.weight(.semibold))
                        Text("Import a user certificate and link it to an SSH key for certificate-based environments.")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(ShellColor.secondaryText)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity)
                    .background(ShellColor.deepPanel)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                ForEach(store.certificates) { certificate in
                    SSHCertificateRow(
                        certificate: certificate,
                        linkedKey: store.linkedKey(for: certificate),
                        editAction: {
                            editingCertificate = certificate
                            isShowingCertificateEditor = true
                        },
                        deleteAction: {
                            certificatePendingDelete = certificate
                        }
                    )
                }
            }
            .padding(18)
        }
        .sheet(isPresented: $isShowingIdentityEditor) {
            SSHIdentityEditorSheet(store: store, identity: editingIdentity)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $isShowingKeyEditor) {
            SSHKeyEditorSheet(store: store, key: editingKey)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $isShowingCertificateEditor) {
            SSHCertificateEditorSheet(store: store, certificate: editingCertificate)
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog(
            "Delete Identity?",
            isPresented: Binding(
                get: { identityPendingDelete != nil },
                set: { isPresented in
                    if !isPresented {
                        identityPendingDelete = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let identity = identityPendingDelete {
                Button("Delete \(identity.name)", role: .destructive) {
                    do {
                        try store.deleteIdentity(identity)
                        identityPendingDelete = nil
                        errorMessage = nil
                    } catch {
                        errorMessage = "Could not delete identity: \(error.localizedDescription)"
                    }
                }
            }
        } message: {
            if let identity = identityPendingDelete {
                Text("This removes \(identity.name), deletes its saved password, and detaches linked hosts.")
            }
        }
        .confirmationDialog(
            "Delete SSH Key?",
            isPresented: Binding(
                get: { keyPendingDelete != nil },
                set: { isPresented in
                    if !isPresented {
                        keyPendingDelete = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let key = keyPendingDelete {
                Button("Delete \(key.name)", role: .destructive) {
                    do {
                        try store.deleteSSHKey(key)
                        keyPendingDelete = nil
                        errorMessage = nil
                    } catch {
                        errorMessage = "Could not delete key: \(error.localizedDescription)"
                    }
                }
            }
        } message: {
            if let key = keyPendingDelete {
                Text("This removes \(key.name) and its private key material from the local vault.")
            }
        }
        .confirmationDialog(
            "Delete SSH Certificate?",
            isPresented: Binding(
                get: { certificatePendingDelete != nil },
                set: { isPresented in
                    if !isPresented {
                        certificatePendingDelete = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let certificate = certificatePendingDelete {
                Button("Delete \(certificate.name)", role: .destructive) {
                    do {
                        try store.deleteSSHCertificate(certificate)
                        certificatePendingDelete = nil
                        errorMessage = nil
                    } catch {
                        errorMessage = "Could not delete certificate: \(error.localizedDescription)"
                    }
                }
            }
        } message: {
            if let certificate = certificatePendingDelete {
                Text("This removes \(certificate.name), deletes its certificate material, and clears linked SSH keys.")
            }
        }
    }
}

private struct SSHIdentityRow: View {
    let identity: SSHIdentity
    let key: SSHKey?
    let certificate: SSHCertificate?
    let linkedHosts: [ShellHost]
    let editAction: () -> Void
    let deleteAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.text.rectangle.fill")
                .font(.title3)
                .foregroundStyle(ShellColor.accent)
                .frame(width: 42, height: 42)
                .background(ShellColor.panel)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(identity.name)
                    .font(.subheadline.weight(.semibold))
                Text(credentialSummary)
                    .font(.caption)
                    .foregroundStyle(ShellColor.secondaryText)
                    .lineLimit(2)
                Text(linkedHostsSummary)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(linkedHosts.isEmpty ? ShellColor.secondaryText : ShellColor.accent)
                    .lineLimit(1)
            }

            Spacer()

            Menu {
                Button {
                    editAction()
                } label: {
                    Label("Edit", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    deleteAction()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(ShellColor.secondaryText)
                    .frame(width: 34, height: 42)
            }
            .buttonStyle(.plain)
        }
        .padding(13)
        .background(ShellColor.deepPanel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var credentialSummary: String {
        guard let key else { return "\(identity.username) · Password-capable" }
        let certificateText = certificate.map { " + cert: \($0.name)" } ?? ""
        return "\(identity.username) · SSH key: \(key.name)\(certificateText)"
    }

    private var linkedHostsSummary: String {
        guard !linkedHosts.isEmpty else { return "No linked hosts" }
        let names = linkedHosts.map(\.name)
        if names.count <= 2 {
            return "Used by \(names.joined(separator: ", "))"
        }
        return "Used by \(names.prefix(2).joined(separator: ", ")) + \(names.count - 2) more"
    }
}

private struct SSHIdentityEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    var store: MobileShellStore
    let identity: SSHIdentity?
    @State private var name: String
    @State private var username: String
    @State private var password: String
    @State private var sshKeyID: SSHKey.ID?
    @State private var errorMessage: String?

    init(store: MobileShellStore, identity: SSHIdentity?) {
        self.store = store
        self.identity = identity
        _name = State(initialValue: identity?.name ?? "")
        _username = State(initialValue: identity?.username ?? "")
        _password = State(initialValue: "")
        _sshKeyID = State(initialValue: identity?.sshKeyID)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    TextField("Name", text: $name)
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Credentials") {
                    SecureField(identity == nil ? "Password" : "New password", text: $password)

                    if store.keys.isEmpty {
                        Text("Import an SSH key first if this identity should use key-based auth.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("SSH Key", selection: $sshKeyID) {
                            Text("No key").tag(SSHKey.ID?.none)
                            ForEach(store.keys) { key in
                                Text("\(key.name) (\(key.kind))").tag(Optional(key.id))
                            }
                        }
                    }

                    Text(identity == nil ? "Identity passwords are stored in the iOS Keychain, not host JSON." : "Leave password blank to keep the current saved credential.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(identity == nil ? "Add Identity" : "Edit Identity")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(identity == nil ? "Add" : "Save") {
                        saveIdentity()
                    }
                }
            }
        }
    }

    private func saveIdentity() {
        do {
            let savedIdentity: SSHIdentity?
            if let identity {
                savedIdentity = try store.updateIdentity(
                    identity,
                    name: name,
                    username: username,
                    password: password,
                    sshKeyID: sshKeyID
                )
            } else {
                savedIdentity = try store.addIdentity(
                    name: name,
                    username: username,
                    password: password,
                    sshKeyID: sshKeyID
                )
            }

            if savedIdentity != nil {
                dismiss()
            } else {
                errorMessage = "Enter a name and username before saving."
            }
        } catch {
            errorMessage = "Could not save identity: \(error.localizedDescription)"
        }
    }
}

private struct SSHKeyRow: View {
    let key: SSHKey
    let certificate: SSHCertificate?
    let linkedHosts: [ShellHost]
    let editAction: () -> Void
    let deleteAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: key.kind == "hardware" ? "key.radiowaves.forward" : "key.fill")
                .font(.title3)
                .foregroundStyle(ShellColor.accent)
                .frame(width: 42, height: 42)
                .background(ShellColor.panel)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                Text(key.name)
                    .font(.subheadline.weight(.semibold))
                Text(metadataSummary)
                    .font(.caption)
                    .foregroundStyle(ShellColor.secondaryText)
                    .lineLimit(2)
                Text(linkedHostsSummary)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(linkedHosts.isEmpty ? ShellColor.secondaryText : ShellColor.accent)
                    .lineLimit(1)
            }
            Spacer()
            Menu {
                Button {
                    editAction()
                } label: {
                    Label("Edit", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    deleteAction()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(ShellColor.secondaryText)
                    .frame(width: 34, height: 42)
            }
            .buttonStyle(.plain)
        }
        .padding(13)
        .background(ShellColor.deepPanel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var metadataSummary: String {
        guard let certificate else { return "\(key.kind.uppercased()) · \(key.fingerprint)" }
        return "\(key.kind.uppercased()) · \(key.fingerprint) · cert: \(certificate.name)"
    }

    private var linkedHostsSummary: String {
        guard !linkedHosts.isEmpty else { return "No linked hosts" }
        let names = linkedHosts.map(\.name)
        if names.count <= 2 {
            return "Linked to \(names.joined(separator: ", "))"
        }
        return "Linked to \(names.prefix(2).joined(separator: ", ")) + \(names.count - 2) more"
    }
}

private struct SSHKeyEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    var store: MobileShellStore
    let key: SSHKey?
    @State private var name: String
    @State private var kind: String
    @State private var privateKey: String
    @State private var errorMessage: String?

    init(store: MobileShellStore, key: SSHKey?) {
        self.store = store
        self.key = key
        _name = State(initialValue: key?.name ?? "")
        _kind = State(initialValue: key?.kind ?? "ed25519")
        _privateKey = State(initialValue: "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Metadata") {
                    TextField("Name", text: $name)
                    TextField("Kind", text: $kind)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Private Key") {
                    TextEditor(text: $privateKey)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(minHeight: 180)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text(key == nil ? "Private key material is stored in the iOS Keychain, not host JSON." : "Leave private key blank to keep the current key material.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(key == nil ? "Import SSH Key" : "Edit SSH Key")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(key == nil ? "Import" : "Save") {
                        saveKey()
                    }
                }
            }
        }
    }

    private func saveKey() {
        do {
            let savedKey: SSHKey?
            if let key {
                savedKey = try store.updateSSHKey(key, name: name, kind: kind, privateKey: privateKey)
            } else {
                savedKey = try store.addSSHKey(name: name, kind: kind, privateKey: privateKey)
            }

            if savedKey != nil {
                dismiss()
            } else {
                errorMessage = key == nil
                    ? "Enter a name, kind, and private key before importing."
                    : "Enter a name and kind before saving."
            }
        } catch {
            errorMessage = "Could not save key: \(error.localizedDescription)"
        }
    }
}

private struct SSHCertificateRow: View {
    let certificate: SSHCertificate
    let linkedKey: SSHKey?
    let editAction: () -> Void
    let deleteAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "seal.fill")
                .font(.title3)
                .foregroundStyle(ShellColor.accent)
                .frame(width: 42, height: 42)
                .background(ShellColor.panel)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(certificate.name)
                    .font(.subheadline.weight(.semibold))
                Text("\(certificate.kind.uppercased()) · \(certificate.fingerprint)")
                    .font(.caption)
                    .foregroundStyle(ShellColor.secondaryText)
                    .lineLimit(2)
                Text(linkedKeySummary)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(linkedKey == nil ? ShellColor.secondaryText : ShellColor.accent)
                    .lineLimit(1)
            }

            Spacer()

            Menu {
                Button {
                    editAction()
                } label: {
                    Label("Edit", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    deleteAction()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(ShellColor.secondaryText)
                    .frame(width: 34, height: 42)
            }
            .buttonStyle(.plain)
        }
        .padding(13)
        .background(ShellColor.deepPanel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var linkedKeySummary: String {
        guard let linkedKey else { return "No linked SSH key" }
        return "Attached to \(linkedKey.name)"
    }
}

private struct SSHCertificateEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    var store: MobileShellStore
    let certificate: SSHCertificate?
    @State private var name: String
    @State private var kind: String
    @State private var certificateMaterial: String
    @State private var sshKeyID: SSHKey.ID?
    @State private var errorMessage: String?

    init(store: MobileShellStore, certificate: SSHCertificate?) {
        self.store = store
        self.certificate = certificate
        _name = State(initialValue: certificate?.name ?? "")
        _kind = State(initialValue: certificate?.kind ?? "user-cert")
        _certificateMaterial = State(initialValue: "")
        _sshKeyID = State(initialValue: certificate.flatMap { store.linkedKey(for: $0)?.id })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Metadata") {
                    TextField("Name", text: $name)
                    TextField("Kind", text: $kind)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Linked SSH Key") {
                    if store.keys.isEmpty {
                        Text("Import an SSH key first before attaching a certificate.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("SSH Key", selection: $sshKeyID) {
                            Text("No key").tag(SSHKey.ID?.none)
                            ForEach(store.keys) { key in
                                Text("\(key.name) (\(key.kind))").tag(Optional(key.id))
                            }
                        }
                    }

                    Text("Hosts and identities use certificates through their selected SSH key.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Certificate") {
                    TextEditor(text: $certificateMaterial)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(minHeight: 160)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text(certificate == nil ? "Certificate material is stored in the iOS Keychain, not host JSON." : "Leave certificate blank to keep the current material.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(certificate == nil ? "Import Certificate" : "Edit Certificate")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(certificate == nil ? "Import" : "Save") {
                        saveCertificate()
                    }
                }
            }
        }
    }

    private func saveCertificate() {
        do {
            let savedCertificate: SSHCertificate?
            if let certificate {
                savedCertificate = try store.updateSSHCertificate(
                    certificate,
                    name: name,
                    kind: kind,
                    certificate: certificateMaterial,
                    sshKeyID: sshKeyID
                )
            } else {
                savedCertificate = try store.addSSHCertificate(
                    name: name,
                    kind: kind,
                    certificate: certificateMaterial,
                    sshKeyID: sshKeyID
                )
            }

            if savedCertificate != nil {
                dismiss()
            } else {
                errorMessage = certificate == nil
                    ? "Enter a name, kind, and certificate before importing."
                    : "Enter a name and kind before saving."
            }
        } catch {
            errorMessage = "Could not save certificate: \(error.localizedDescription)"
        }
    }
}

