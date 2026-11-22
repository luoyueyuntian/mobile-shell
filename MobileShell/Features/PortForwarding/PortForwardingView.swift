import SwiftUI

struct PortForwardingView: View {
    @Bindable var store: MobileShellStore
    @State private var isShowingRuleEditor = false
    @State private var editingRule: PortForwardRule?
    @State private var rulePendingDelete: PortForwardRule?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Personal Tunnels")
                            .font(.headline.weight(.semibold))
                        Text("Save local, remote, and dynamic tunnel rules for personal SSH workflows.")
                            .font(.caption)
                            .foregroundStyle(ShellColor.secondaryText)
                    }

                    Spacer()

                    Button {
                        editingRule = nil
                        isShowingRuleEditor = true
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

                if let message = store.portForwardErrorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(ShellColor.pink)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(ShellColor.panel)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                if store.portForwardRules.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.title2)
                            .foregroundStyle(ShellColor.secondaryText)
                        Text("No tunnels yet")
                            .font(.subheadline.weight(.semibold))
                        Text("Add local, remote, or dynamic tunnel rules for databases, dashboards, and private web apps.")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(ShellColor.secondaryText)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity)
                    .background(ShellColor.deepPanel)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                ForEach(store.portForwardRules) { rule in
                    PortForwardRuleRow(
                        rule: rule,
                        toggleAction: {
                            Task { @MainActor in
                                await store.togglePortForwardRule(rule)
                            }
                        },
                        editAction: {
                            editingRule = rule
                            isShowingRuleEditor = true
                        },
                        deleteAction: {
                            rulePendingDelete = rule
                        }
                    )
                }
            }
            .padding(18)
        }
        .sheet(isPresented: $isShowingRuleEditor) {
            PortForwardRuleEditorSheet(store: store, rule: editingRule)
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog(
            "Delete Port Forward?",
            isPresented: Binding(
                get: { rulePendingDelete != nil },
                set: { isPresented in
                    if !isPresented {
                        rulePendingDelete = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let rule = rulePendingDelete {
                Button("Delete \(rule.name)", role: .destructive) {
                    Task { @MainActor in
                        await store.deletePortForwardRule(rule)
                        rulePendingDelete = nil
                    }
                }
            }
        } message: {
            if let rule = rulePendingDelete {
                Text("This removes \(rule.name). Active tunnels are stopped first.")
            }
        }
    }
}

private struct PortForwardRuleRow: View {
    let rule: PortForwardRule
    let toggleAction: () -> Void
    let editAction: () -> Void
    let deleteAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: rule.isActive ? "bolt.horizontal.circle.fill" : "bolt.horizontal.circle")
                .font(.title2)
                .foregroundStyle(rule.isActive ? ShellColor.accent : ShellColor.secondaryText)
                .frame(width: 42, height: 42)
                .background(ShellColor.panel)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(rule.name)
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 6) {
                    Text(rule.kind.title.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(ShellColor.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(ShellColor.accent.opacity(0.14))
                        .clipShape(Capsule())
                    Text(rule.routeSummary)
                        .font(.caption)
                        .foregroundStyle(ShellColor.secondaryText)
                }
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
            }
            .buttonStyle(.plain)

            Toggle("", isOn: Binding(
                get: { rule.isActive },
                set: { _ in toggleAction() }
            ))
            .labelsHidden()
            .tint(ShellColor.accent)
        }
        .padding(13)
        .background(ShellColor.deepPanel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct PortForwardRuleEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    var store: MobileShellStore
    let rule: PortForwardRule?
    @State private var name: String
    @State private var sshHostID: ShellHost.ID?
    @State private var kind: PortForwardKind
    @State private var localHost: String
    @State private var localPort: String
    @State private var remoteHost: String
    @State private var remotePort: String
    @State private var errorMessage: String?

    init(store: MobileShellStore, rule: PortForwardRule?) {
        self.store = store
        self.rule = rule
        _name = State(initialValue: rule?.name ?? "")
        _sshHostID = State(initialValue: rule?.sshHostID ?? store.hosts.first?.id)
        _kind = State(initialValue: rule?.kind ?? .local)
        _localHost = State(initialValue: rule?.localHost ?? "127.0.0.1")
        _localPort = State(initialValue: rule.map { String($0.localPort) } ?? "")
        _remoteHost = State(initialValue: rule?.remoteHost ?? "127.0.0.1")
        _remotePort = State(initialValue: rule.map { $0.kind == .dynamic ? "" : String($0.remotePort) } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("SSH Host") {
                    Picker("Host", selection: $sshHostID) {
                        if store.hosts.isEmpty {
                            Text("No saved hosts").tag(Optional<ShellHost.ID>.none)
                        }

                        ForEach(store.hosts) { host in
                            Text("\(host.name) (\(host.endpoint))").tag(Optional(host.id))
                        }
                    }
                }

                Section("Tunnel") {
                    TextField("Name", text: $name)
                    Picker("Type", selection: $kind) {
                        ForEach(PortForwardKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    Text(kind.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField(localHostFieldTitle, text: $localHost)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField(localPortFieldTitle, text: $localPort)
                        .keyboardType(.numberPad)
                    if kind != .dynamic {
                        TextField(remoteHostFieldTitle, text: $remoteHost)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField(remotePortFieldTitle, text: $remotePort)
                            .keyboardType(.numberPad)
                    }
                }

                Section {
                    Text("Editing an active tunnel stops the current listener and saves the updated rule inactive.")
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
            .navigationTitle(rule == nil ? "Add Tunnel" : "Edit Tunnel")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(rule == nil ? "Add" : "Save") {
                        saveRule()
                    }
                }
            }
        }
    }

    private func saveRule() {
        guard let parsedLocalPort = Int(localPort),
              (1...65_535).contains(parsedLocalPort) else {
            errorMessage = "Enter a local TCP port between 1 and 65535."
            return
        }

        let parsedRemotePort: Int
        let savedRemoteHost: String
        switch kind {
        case .local, .remote:
            guard let remotePort = Int(remotePort),
                  (1...65_535).contains(remotePort) else {
                errorMessage = "Enter a remote TCP port between 1 and 65535."
                return
            }
            let trimmedRemoteHost = remoteHost.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedRemoteHost.isEmpty else {
                errorMessage = "Enter a remote host for this tunnel."
                return
            }
            parsedRemotePort = remotePort
            savedRemoteHost = trimmedRemoteHost
        case .dynamic:
            parsedRemotePort = 0
            savedRemoteHost = ""
        }

        if let rule {
            Task { @MainActor in
                let savedRule = await store.updatePortForwardRule(
                    rule,
                    kind: kind,
                    name: name,
                    sshHostID: sshHostID,
                    localHost: localHost,
                    localPort: parsedLocalPort,
                    remoteHost: savedRemoteHost,
                    remotePort: parsedRemotePort
                )
                finishSaving(savedRule)
            }
        } else {
            let savedRule = store.addPortForwardRule(
                kind: kind,
                name: name,
                sshHostID: sshHostID,
                localHost: localHost,
                localPort: parsedLocalPort,
                remoteHost: savedRemoteHost,
                remotePort: parsedRemotePort
            )
            finishSaving(savedRule)
        }
    }

    @MainActor
    private func finishSaving(_ savedRule: PortForwardRule?) {
        if savedRule != nil {
            dismiss()
        } else {
            errorMessage = store.portForwardErrorMessage ?? "Could not save this tunnel."
        }
    }

    private var localHostFieldTitle: String {
        switch kind {
        case .local:
            "Local bind host"
        case .remote:
            "Local target host"
        case .dynamic:
            "SOCKS bind host"
        }
    }

    private var localPortFieldTitle: String {
        switch kind {
        case .local:
            "Local listen port"
        case .remote:
            "Local target port"
        case .dynamic:
            "SOCKS listen port"
        }
    }

    private var remoteHostFieldTitle: String {
        switch kind {
        case .local:
            "Remote target host"
        case .remote:
            "Remote bind host"
        case .dynamic:
            "Remote host"
        }
    }

    private var remotePortFieldTitle: String {
        switch kind {
        case .local:
            "Remote target port"
        case .remote:
            "Remote listen port"
        case .dynamic:
            "Remote port"
        }
    }
}
