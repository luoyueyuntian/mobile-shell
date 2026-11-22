import SwiftUI

struct HostsView: View {
    @Bindable var store: MobileShellStore
    @State private var showingAddHost = false
    @State private var showingImportConfig = false
    @State private var editingGroupName: String?
    @State private var editingHost: ShellHost?
    @State private var hostPendingDelete: ShellHost?

    var groupedHosts: [(String, [ShellHost])] {
        Dictionary(grouping: store.filteredHosts(), by: \.group)
            .map { ($0.key, $0.value) }
            .sorted { $0.0 < $1.0 }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                HStack {
                    SearchField(text: $store.searchText)
                    Button {
                        showingAddHost = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.headline.weight(.bold))
                            .frame(width: 42, height: 42)
                            .background(ShellColor.accent)
                            .foregroundStyle(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add host")
                }

                QuickImportCard {
                    showingImportConfig = true
                }

                HostTagFilterStrip(
                    tags: store.hostTags(),
                    selectedTag: store.selectedHostTag,
                    selectTag: { store.selectHostTag($0) },
                    clearSelection: { store.clearSelectedHostTag() }
                )

                SectionTitle("Groups")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    ForEach(groupedHosts, id: \.0) { group, hosts in
                        GroupCard(
                            name: group,
                            count: hosts.count,
                            identitySummary: identitySummary(forGroup: group),
                            routeSummary: routeSummary(forGroup: group),
                            startupSnippetSummary: startupSnippetSummary(forGroup: group)
                        ) {
                            editingGroupName = group
                        }
                    }
                }

                SectionTitle("Hosts")
                LazyVStack(spacing: 10) {
                    ForEach(store.filteredHosts()) { host in
                        HostRow(
                            host: host,
                            authenticationSummary: store.authenticationSummary(for: host),
                            routeSummary: store.routeSummary(for: host),
                            startupSnippetTitle: store.startupSnippetTitle(for: host)
                        ) {
                            Task { @MainActor in
                                await store.openInteractiveTerminal(for: host)
                            }
                        } sftpAction: {
                            Task { @MainActor in
                                await store.openSFTP(for: host)
                            }
                        } editAction: {
                            editingHost = host
                        } deleteAction: {
                            hostPendingDelete = host
                        }
                    }
                }
            }
            .padding(18)
        }
        .sheet(isPresented: $showingAddHost) {
            AddHostSheet(store: store)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingImportConfig) {
            ImportOpenSSHConfigSheet(store: store)
                .presentationDetents([.medium, .large])
        }
        .sheet(
            isPresented: Binding(
                get: { editingGroupName != nil },
                set: { isPresented in
                    if !isPresented {
                        editingGroupName = nil
                    }
                }
            )
        ) {
            if let editingGroupName {
                HostGroupEditorSheet(store: store, groupName: editingGroupName)
                    .presentationDetents([.medium])
            }
        }
        .sheet(item: $editingHost) { host in
            EditHostSheet(store: store, host: host)
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog(
            "Delete Host?",
            isPresented: Binding(
                get: { hostPendingDelete != nil },
                set: { isPresented in
                    if !isPresented {
                        hostPendingDelete = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let host = hostPendingDelete {
                Button("Delete \(host.name)", role: .destructive) {
                    Task { @MainActor in
                        await store.deleteHost(host)
                        hostPendingDelete = nil
                    }
                }
            }
        } message: {
            if let host = hostPendingDelete {
                Text("This removes \(host.name), its saved password, open sessions, SFTP state, and linked port forwards.")
            }
        }
    }

    private func identitySummary(forGroup group: String) -> String? {
        guard let identityID = store.hostGroupProfiles.first(where: {
            $0.name.caseInsensitiveCompare(group) == .orderedSame
        })?.identityID else {
            return nil
        }

        guard let identity = store.identities.first(where: { $0.id == identityID }) else {
            return "Missing identity"
        }

        return "Identity: \(identity.name)"
    }

    private func routeSummary(forGroup group: String) -> String? {
        guard let jumpHostID = store.hostGroupProfiles.first(where: {
            $0.name.caseInsensitiveCompare(group) == .orderedSame
        })?.jumpHostID else {
            return nil
        }

        guard let jumpHost = store.hosts.first(where: { $0.id == jumpHostID }) else {
            return "Missing jump host"
        }

        return "Via \(jumpHost.name)"
    }

    private func startupSnippetSummary(forGroup group: String) -> String? {
        guard let startupSnippetID = store.hostGroupProfiles.first(where: {
            $0.name.caseInsensitiveCompare(group) == .orderedSame
        })?.startupSnippetID else {
            return nil
        }

        guard let snippet = store.snippets.first(where: { $0.id == startupSnippetID }) else {
            return "Missing startup snippet"
        }

        return "Startup: \(snippet.title)"
    }
}

private struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(ShellColor.secondaryText)
            TextField("Search hosts, tags, address", text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(ShellColor.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct QuickImportCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "square.and.arrow.down")
                    .font(.headline)
                    .frame(width: 40, height: 40)
                    .background(ShellColor.deepPanel)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Quick Import")
                        .font(.subheadline.weight(.semibold))
                    Text("Paste an OpenSSH config or add a saved host manually.")
                        .font(.caption)
                        .foregroundStyle(ShellColor.secondaryText)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(ShellColor.secondaryText)
            }
            .padding(14)
            .background(ShellColor.panel)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

private struct GroupCard: View {
    let name: String
    let count: Int
    let identitySummary: String?
    let routeSummary: String?
    let startupSnippetSummary: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: identitySummary == nil && routeSummary == nil && startupSnippetSummary == nil ? "server.rack" : "point.3.connected.trianglepath.dotted")
                    .font(.headline)
                    .foregroundStyle(ShellColor.accent)
                    .frame(width: 38, height: 38)
                    .background(ShellColor.deepPanel)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .allowsTightening(true)
                    Text(summaryLine)
                        .font(.caption)
                        .foregroundStyle(ShellColor.secondaryText)
                        .lineLimit(1)
                    if identitySummary != nil || routeSummary != nil || startupSnippetSummary != nil {
                        Text("Hosts: \(count)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(ShellColor.accent)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ShellColor.secondaryText)
            }
            .padding(12)
            .background(ShellColor.panel)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private var summaryLine: String {
        let parts = [identitySummary, routeSummary, startupSnippetSummary].compactMap { $0 }
        return parts.isEmpty ? "Hosts: \(count)" : parts.joined(separator: " · ")
    }
}

private struct HostGroupEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: MobileShellStore
    let groupName: String
    @State private var identityID: SSHIdentity.ID?
    @State private var jumpHostID: ShellHost.ID?
    @State private var startupSnippetID: ShellSnippet.ID?
    @State private var terminalTheme: TerminalTheme?
    @State private var terminalFontSize: TerminalFontSize?
    @State private var environmentVariablesText: String

    init(store: MobileShellStore, groupName: String) {
        self.store = store
        self.groupName = groupName
        let profile = store.hostGroupProfiles.first(where: {
            $0.name.caseInsensitiveCompare(groupName) == .orderedSame
        })
        _identityID = State(initialValue: profile?.identityID)
        _jumpHostID = State(initialValue: profile?.jumpHostID)
        _startupSnippetID = State(initialValue: profile?.startupSnippetID)
        _terminalTheme = State(initialValue: profile?.terminalTheme)
        _terminalFontSize = State(initialValue: profile?.terminalFontSize)
        _environmentVariablesText = State(
            initialValue: ShellEnvironmentVariable.text(from: profile?.environmentVariables ?? [])
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Group") {
                    Text(groupName)
                    Text("Hosts without their own identity can inherit this group's identity.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Identity") {
                    if store.identities.isEmpty {
                        Text("Create an identity in Keychain before assigning group credentials.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Identity", selection: $identityID) {
                            Text("No group identity").tag(SSHIdentity.ID?.none)
                            ForEach(store.identities) { identity in
                                Text("\(identity.name) (\(identity.username))").tag(Optional(identity.id))
                            }
                        }
                    }
                }

                Section("Jump Host") {
                    if store.hosts.isEmpty {
                        Text("Add a host first if this group should route through a bastion.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Jump Host", selection: $jumpHostID) {
                            Text("Direct connection").tag(ShellHost.ID?.none)
                            ForEach(store.hosts) { host in
                                Text(host.name).tag(Optional(host.id))
                            }
                        }
                        Text("Hosts in this group can inherit the selected jump host unless they choose their own.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Automation") {
                    if store.snippets.isEmpty {
                        Text("Add snippets first to define a group startup command.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Startup Snippet", selection: $startupSnippetID) {
                            Text("No group startup").tag(ShellSnippet.ID?.none)
                            ForEach(store.snippets) { snippet in
                                Text(snippet.title).tag(Optional(snippet.id))
                            }
                        }
                        Text("Hosts in this group inherit this startup snippet unless they choose their own.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Environment") {
                    EnvironmentVariablesTextEditor(
                        text: $environmentVariablesText,
                        helperText: "One KEY=value per line. Hosts in this group inherit these variables unless they override the same key."
                    )
                }

                Section("Appearance") {
                    Picker("Terminal Theme", selection: $terminalTheme) {
                        Text("Default").tag(TerminalTheme?.none)
                        ForEach(TerminalTheme.allCases) { theme in
                            Text(theme.displayName).tag(Optional(theme))
                        }
                    }
                    Picker("Font Size", selection: $terminalFontSize) {
                        Text("Default").tag(TerminalFontSize?.none)
                        ForEach(TerminalFontSize.allCases) { fontSize in
                            Text(fontSize.displayName).tag(Optional(fontSize))
                        }
                    }
                    Text("Hosts in this group inherit these terminal appearance settings unless they choose their own.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit Group")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        _ = store.upsertHostGroupProfile(
                            name: groupName,
                            identityID: identityID,
                            jumpHostID: jumpHostID,
                            startupSnippetID: startupSnippetID,
                            terminalTheme: terminalTheme,
                            terminalFontSize: terminalFontSize,
                            environmentVariables: ShellEnvironmentVariable.parseLines(environmentVariablesText)
                        )
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct HostRow: View {
    let host: ShellHost
    let authenticationSummary: HostAuthenticationSummary
    let routeSummary: String?
    let startupSnippetTitle: String?
    let terminalAction: () -> Void
    let sftpAction: () -> Void
    let editAction: () -> Void
    let deleteAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: terminalAction) {
                HStack(spacing: 12) {
                    hostIcon
                    VStack(alignment: .leading, spacing: 4) {
                        Text(host.name)
                            .font(.subheadline.weight(.semibold))
                        Text(host.subtitle)
                            .font(.caption)
                            .foregroundStyle(ShellColor.secondaryText)
                            .lineLimit(1)
                        HStack(spacing: 5) {
                            Image(systemName: authenticationSummary.symbolName)
                                .font(.caption2.weight(.bold))
                            Text(authenticationSummary.text)
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(authenticationSummary.isReady ? ShellColor.accent : ShellColor.pink)
                        if let protocolBadge = HostProtocolBadgePresentation(host: host) {
                            Text(protocolBadge.label)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(ShellColor.orange)
                        }
                        if let routeSummary {
                            HStack(spacing: 5) {
                                Image(systemName: routeSummary == "Missing jump host" ? "exclamationmark.triangle.fill" : "point.3.connected.trianglepath.dotted")
                                    .font(.caption2.weight(.bold))
                                Text(routeSummary)
                                    .font(.caption2.weight(.semibold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(routeSummary == "Missing jump host" ? ShellColor.pink : ShellColor.orange)
                        }
                        if let startupSnippetTitle {
                            HStack(spacing: 5) {
                                Image(systemName: "bolt.fill")
                                    .font(.caption2.weight(.bold))
                                Text("Startup: \(startupSnippetTitle)")
                                    .font(.caption2.weight(.semibold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(ShellColor.accent)
                        }
                    }
                    Spacer()
                    Image(systemName: "play.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(ShellColor.accent)
                }
            }
            .buttonStyle(.plain)

            Button(action: sftpAction) {
                Image(systemName: "folder.fill")
                    .font(.headline)
                    .foregroundStyle(ShellColor.orange)
                    .frame(width: 42, height: 42)
                    .background(ShellColor.deepPanel)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open SFTP for \(host.name)")

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
        .background(ShellColor.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var hostIcon: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: "terminal.fill")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(statusColor)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Circle()
                .fill(statusColor)
                .frame(width: 11, height: 11)
                .overlay(Circle().stroke(ShellColor.panel, lineWidth: 2))
                .offset(x: 2, y: 2)
        }
    }

    private var statusColor: Color {
        switch host.status {
        case .online: ShellColor.accent
        case .idle: ShellColor.orange
        case .locked: ShellColor.pink
        }
    }
}

struct HostProtocolBadgePresentation: Equatable {
    let label: String

    init?(host: ShellHost) {
        guard host.protocol == .mosh else { return nil }
        label = "MOSH"
    }
}

private struct AddHostSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: MobileShellStore
    @State private var name = ""
    @State private var address = ""
    @State private var port = "22"
    @State private var username = ""
    @State private var group = ""
    @State private var tags = ""
    @State private var password = ""
    @State private var accessProtocol: RemoteAccessProtocol = .ssh
    @State private var moshUDPPort = String(MoshHostConfiguration.default.udpPort)
    @State private var moshServerCommand = MoshHostConfiguration.default.serverCommand
    @State private var moshPredictiveEcho = MoshHostConfiguration.default.predictiveEcho
    @State private var moshUseExperimentalConnection = MoshHostConfiguration.default.useExperimentalConnection
    @State private var sshKeyID: SSHKey.ID?
    @State private var identityID: SSHIdentity.ID?
    @State private var jumpHostID: ShellHost.ID?
    @State private var startupSnippetID: ShellSnippet.ID?
    @State private var terminalTheme: TerminalTheme?
    @State private var terminalFontSize: TerminalFontSize?
    @State private var environmentVariablesText = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    TextField("Name", text: $name)
                    TextField("Address", text: $address)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Port", text: $port)
                        .keyboardType(.numberPad)
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Protocol") {
                    Picker("Protocol", selection: $accessProtocol) {
                        Text("SSH").tag(RemoteAccessProtocol.ssh)
                        Text("Mosh").tag(RemoteAccessProtocol.mosh)
                    }
                    if accessProtocol == .mosh {
                        moshConfigurationFields
                    }
                }

                Section("Security") {
                    if !store.identities.isEmpty {
                        Picker("Identity", selection: $identityID) {
                            Text("Host credential").tag(SSHIdentity.ID?.none)
                            ForEach(store.identities) { identity in
                                Text("\(identity.name) (\(identity.username))").tag(Optional(identity.id))
                            }
                        }
                        Text(identityID == nil ? "Use the host-specific password and SSH key below." : "Connections will use the selected identity username, password, and SSH key first.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    SecureField("Password", text: $password)
                    if store.keys.isEmpty {
                        Text("Import an SSH key in Keychain to enable key-based auth for this host.")
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
                    Text("Passwords and private keys are stored separately from host JSON in the iOS Keychain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Organization") {
                    TextField("Group", text: $group)
                    TextField("Tags, comma separated", text: $tags)
                        .textInputAutocapitalization(.never)
                }

                Section("Automation") {
                    if store.snippets.isEmpty {
                        Text("Add snippets first to run a command automatically after connecting.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Startup Snippet", selection: $startupSnippetID) {
                            Text("None").tag(ShellSnippet.ID?.none)
                            ForEach(store.snippets) { snippet in
                                Text(snippet.title).tag(Optional(snippet.id))
                            }
                        }
                        Text("The selected snippet runs once when a new terminal session opens for this host.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Routing") {
                    if store.hosts.isEmpty {
                        Text("Add another host first if this host should connect through a bastion.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Jump Host", selection: $jumpHostID) {
                            Text("Direct connection").tag(ShellHost.ID?.none)
                            ForEach(store.hosts) { host in
                                Text(host.name).tag(Optional(host.id))
                            }
                        }
                        Text("Choose a saved host to use as the first jump in the connection chain.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Environment") {
                    EnvironmentVariablesTextEditor(
                        text: $environmentVariablesText,
                        helperText: "One KEY=value per line. Host variables override group variables with the same key."
                    )
                }

                Section("Appearance") {
                    Picker("Terminal Theme", selection: $terminalTheme) {
                        Text("Group / Default").tag(TerminalTheme?.none)
                        ForEach(TerminalTheme.allCases) { theme in
                            Text(theme.displayName).tag(Optional(theme))
                        }
                    }
                    Picker("Font Size", selection: $terminalFontSize) {
                        Text("Group / Default").tag(TerminalFontSize?.none)
                        ForEach(TerminalFontSize.allCases) { fontSize in
                            Text(fontSize.displayName).tag(Optional(fontSize))
                        }
                    }
                    Text("Leave unset to inherit group appearance or use terminal defaults.")
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
            .navigationTitle("Add Host")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        saveHost()
                    }
                }
            }
        }
    }

    private func saveHost() {
        guard let parsedPort = Int(port), (1...65_535).contains(parsedPort) else {
            errorMessage = "Enter a TCP port between 1 and 65535."
            return
        }

        let moshConfiguration = accessProtocol == .mosh ? validatedMoshConfiguration() : nil
        if accessProtocol == .mosh, moshConfiguration == nil {
            return
        }

        do {
            try store.addHost(
                name: name,
                address: address,
                port: parsedPort,
                username: username,
                group: group,
                tags: tags,
                password: password,
                protocol: accessProtocol,
                moshConfiguration: moshConfiguration,
                sshKeyID: sshKeyID,
                identityID: identityID,
                jumpHostID: jumpHostID,
                startupSnippetID: startupSnippetID,
                terminalTheme: terminalTheme,
                terminalFontSize: terminalFontSize,
                environmentVariables: ShellEnvironmentVariable.parseLines(environmentVariablesText)
            )
            dismiss()
        } catch {
            errorMessage = "Could not save host: \(error.localizedDescription)"
        }
    }

    @ViewBuilder
    private var moshConfigurationFields: some View {
        TextField("UDP Port", text: $moshUDPPort)
            .keyboardType(.numberPad)
        TextField("Server Command", text: $moshServerCommand)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        Toggle("Predictive Echo", isOn: $moshPredictiveEcho)
        Toggle("Use Experimental Connection", isOn: $moshUseExperimentalConnection)
        Text("Mosh requires a UDP port between 1 and 65535 and a non-empty server command.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func validatedMoshConfiguration() -> MoshHostConfiguration? {
        guard accessProtocol == .mosh else { return nil }
        guard let udpPort = Int(moshUDPPort), (1...65_535).contains(udpPort) else {
            errorMessage = "Enter a Mosh UDP port between 1 and 65535."
            return nil
        }

        let serverCommand = moshServerCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !serverCommand.isEmpty else {
            errorMessage = "Enter a Mosh server command."
            return nil
        }

        return MoshHostConfiguration(
            udpPort: udpPort,
            serverCommand: serverCommand,
            predictiveEcho: moshPredictiveEcho,
            useExperimentalConnection: moshUseExperimentalConnection
        )
    }
}

private struct EditHostSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: MobileShellStore
    let host: ShellHost
    @State private var name: String
    @State private var address: String
    @State private var port: String
    @State private var username: String
    @State private var group: String
    @State private var tags: String
    @State private var password = ""
    @State private var accessProtocol: RemoteAccessProtocol = .ssh
    @State private var moshUDPPort = String(MoshHostConfiguration.default.udpPort)
    @State private var moshServerCommand = MoshHostConfiguration.default.serverCommand
    @State private var moshPredictiveEcho = MoshHostConfiguration.default.predictiveEcho
    @State private var moshUseExperimentalConnection = MoshHostConfiguration.default.useExperimentalConnection
    @State private var sshKeyID: SSHKey.ID?
    @State private var identityID: SSHIdentity.ID?
    @State private var jumpHostID: ShellHost.ID?
    @State private var startupSnippetID: ShellSnippet.ID?
    @State private var terminalTheme: TerminalTheme?
    @State private var terminalFontSize: TerminalFontSize?
    @State private var environmentVariablesText: String
    @State private var errorMessage: String?

    init(store: MobileShellStore, host: ShellHost) {
        self.store = store
        self.host = host
        _name = State(initialValue: host.name)
        _address = State(initialValue: host.address)
        _port = State(initialValue: String(host.port))
        _username = State(initialValue: host.username)
        _group = State(initialValue: host.group)
        _tags = State(initialValue: host.tags.joined(separator: ", "))
        _accessProtocol = State(initialValue: host.protocol)
        _moshUDPPort = State(initialValue: String(host.moshConfiguration?.udpPort ?? MoshHostConfiguration.default.udpPort))
        _moshServerCommand = State(initialValue: host.moshConfiguration?.serverCommand ?? MoshHostConfiguration.default.serverCommand)
        _moshPredictiveEcho = State(initialValue: host.moshConfiguration?.predictiveEcho ?? MoshHostConfiguration.default.predictiveEcho)
        _moshUseExperimentalConnection = State(initialValue: host.moshConfiguration?.useExperimentalConnection ?? MoshHostConfiguration.default.useExperimentalConnection)
        _sshKeyID = State(initialValue: host.sshKeyID)
        _identityID = State(initialValue: host.identityID)
        _jumpHostID = State(initialValue: host.jumpHostID)
        _startupSnippetID = State(initialValue: host.startupSnippetID)
        _terminalTheme = State(initialValue: host.terminalTheme)
        _terminalFontSize = State(initialValue: host.terminalFontSize)
        _environmentVariablesText = State(initialValue: ShellEnvironmentVariable.text(from: host.environmentVariables))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    TextField("Name", text: $name)
                    TextField("Address", text: $address)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Port", text: $port)
                        .keyboardType(.numberPad)
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Protocol") {
                    Picker("Protocol", selection: $accessProtocol) {
                        Text("SSH").tag(RemoteAccessProtocol.ssh)
                        Text("Mosh").tag(RemoteAccessProtocol.mosh)
                    }
                    if accessProtocol == .mosh {
                        moshConfigurationFields
                    }
                }

                Section("Security") {
                    if !store.identities.isEmpty {
                        Picker("Identity", selection: $identityID) {
                            Text("Host credential").tag(SSHIdentity.ID?.none)
                            ForEach(store.identities) { identity in
                                Text("\(identity.name) (\(identity.username))").tag(Optional(identity.id))
                            }
                        }
                        Text(identityID == nil ? "Use the host-specific password and SSH key below." : "Connections will use the selected identity username, password, and SSH key first.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    SecureField("New password", text: $password)
                    if store.keys.isEmpty {
                        Text("Import an SSH key in Keychain to enable key-based auth for this host.")
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
                    Text("Leave password blank to keep the current saved credential.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Organization") {
                    TextField("Group", text: $group)
                    TextField("Tags, comma separated", text: $tags)
                        .textInputAutocapitalization(.never)
                }

                Section("Automation") {
                    if store.snippets.isEmpty {
                        Text("Add snippets first to run a command automatically after connecting.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Startup Snippet", selection: $startupSnippetID) {
                            Text("None").tag(ShellSnippet.ID?.none)
                            ForEach(store.snippets) { snippet in
                                Text(snippet.title).tag(Optional(snippet.id))
                            }
                        }
                        Text("The selected snippet runs once when a new terminal session opens for this host.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Routing") {
                    let availableJumpHosts = store.hosts.filter { $0.id != host.id }
                    if availableJumpHosts.isEmpty {
                        Text("Add another host first if this host should connect through a bastion.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Jump Host", selection: $jumpHostID) {
                            Text("Direct connection").tag(ShellHost.ID?.none)
                            ForEach(availableJumpHosts) { host in
                                Text(host.name).tag(Optional(host.id))
                            }
                        }
                        Text("Choose a saved host to use as the first jump in the connection chain.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Environment") {
                    EnvironmentVariablesTextEditor(
                        text: $environmentVariablesText,
                        helperText: "One KEY=value per line. Host variables override group variables with the same key."
                    )
                }

                Section("Appearance") {
                    Picker("Terminal Theme", selection: $terminalTheme) {
                        Text("Group / Default").tag(TerminalTheme?.none)
                        ForEach(TerminalTheme.allCases) { theme in
                            Text(theme.displayName).tag(Optional(theme))
                        }
                    }
                    Picker("Font Size", selection: $terminalFontSize) {
                        Text("Group / Default").tag(TerminalFontSize?.none)
                        ForEach(TerminalFontSize.allCases) { fontSize in
                            Text(fontSize.displayName).tag(Optional(fontSize))
                        }
                    }
                    Text("Leave unset to inherit group appearance or use terminal defaults.")
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
            .navigationTitle("Edit Host")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveHost()
                    }
                }
            }
        }
    }

    private func saveHost() {
        guard let parsedPort = Int(port), (1...65_535).contains(parsedPort) else {
            errorMessage = "Enter a TCP port between 1 and 65535."
            return
        }

        let moshConfiguration = accessProtocol == .mosh ? validatedMoshConfiguration() : nil
        if accessProtocol == .mosh, moshConfiguration == nil {
            return
        }

        do {
            let updated = try store.updateHost(
                host,
                name: name,
                address: address,
                port: parsedPort,
                username: username,
                group: group,
                tags: tags,
                password: password,
                protocol: accessProtocol,
                moshConfiguration: moshConfiguration,
                sshKeyID: sshKeyID,
                identityID: identityID,
                jumpHostID: jumpHostID,
                startupSnippetID: startupSnippetID,
                terminalTheme: terminalTheme,
                terminalFontSize: terminalFontSize,
                environmentVariables: ShellEnvironmentVariable.parseLines(environmentVariablesText)
            )
            if updated != nil {
                dismiss()
            } else {
                errorMessage = "Could not update this host."
            }
        } catch {
            errorMessage = "Could not save host: \(error.localizedDescription)"
        }
    }

    @ViewBuilder
    private var moshConfigurationFields: some View {
        TextField("UDP Port", text: $moshUDPPort)
            .keyboardType(.numberPad)
        TextField("Server Command", text: $moshServerCommand)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        Toggle("Predictive Echo", isOn: $moshPredictiveEcho)
        Toggle("Use Experimental Connection", isOn: $moshUseExperimentalConnection)
        Text("Mosh requires a UDP port between 1 and 65535 and a non-empty server command.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func validatedMoshConfiguration() -> MoshHostConfiguration? {
        guard let udpPort = Int(moshUDPPort), (1...65_535).contains(udpPort) else {
            errorMessage = "Enter a Mosh UDP port between 1 and 65535."
            return nil
        }

        let serverCommand = moshServerCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !serverCommand.isEmpty else {
            errorMessage = "Enter a Mosh server command."
            return nil
        }

        return MoshHostConfiguration(
            udpPort: udpPort,
            serverCommand: serverCommand,
            predictiveEcho: moshPredictiveEcho,
            useExperimentalConnection: moshUseExperimentalConnection
        )
    }
}

private struct ImportOpenSSHConfigSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: MobileShellStore
    @State private var configText = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("OpenSSH Config") {
                    TextEditor(text: $configText)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(minHeight: 220)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("Supported fields: Host, HostName, User, and Port. Wildcard Host blocks are ignored.")
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
            .navigationTitle("Import SSH Config")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        importConfig()
                    }
                    .disabled(configText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func importConfig() {
        let importedHosts = store.importOpenSSHConfig(configText)
        guard !importedHosts.isEmpty else {
            errorMessage = "No new hosts found. Paste non-wildcard Host blocks that are not already saved."
            return
        }

        dismiss()
    }
}

private struct SectionTitle: View {
    private let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.caption.weight(.bold))
            .foregroundStyle(ShellColor.secondaryText)
            .textCase(.uppercase)
    }
}
