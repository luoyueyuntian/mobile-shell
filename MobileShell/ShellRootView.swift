import SwiftUI
import UniformTypeIdentifiers

struct ShellRootView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    var store: MobileShellStore

    var body: some View {
        ZStack {
            ShellColor.background.ignoresSafeArea()

            if horizontalSizeClass == .compact {
                CompactShellLayout(store: store)
            } else {
                RegularShellLayout(store: store)
            }
        }
        .alert(
            "Trust SSH Host?",
            isPresented: Binding(
                get: { store.pendingHostKeyChallenge != nil },
                set: { isPresented in
                    if !isPresented {
                        store.cancelPendingHostKeyChallenge()
                    }
                }
            )
        ) {
            Button("Cancel", role: .cancel) {
                store.cancelPendingHostKeyChallenge()
            }
            Button("Trust & Continue") {
                Task { @MainActor in
                    await store.trustPendingHostKey()
                }
            }
        } message: {
            if let challenge = store.pendingHostKeyChallenge {
                Text("""
                \(challenge.knownHostHost) is not in Known Hosts.

                Key: \(challenge.keyType)
                Fingerprint: \(challenge.fingerprint)
                """)
            }
        }
        .alert(
            "Mosh Session Unavailable",
            isPresented: Binding(
                get: { store.terminalUnavailableMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        store.terminalUnavailableMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                store.terminalUnavailableMessage = nil
            }
        } message: {
            if let message = store.terminalUnavailableMessage {
                Text(message)
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct CompactShellLayout: View {
    var store: MobileShellStore

    var body: some View {
        VStack(spacing: 0) {
            ShellHeader(store: store)
            Divider().overlay(ShellColor.stroke)
            ActiveSectionView(store: store)
            CompactSectionBar(store: store)
        }
    }
}

private struct RegularShellLayout: View {
    var store: MobileShellStore

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(store: store)
                .frame(width: 268)
            Divider().overlay(ShellColor.stroke)
            VStack(spacing: 0) {
                ShellHeader(store: store)
                Divider().overlay(ShellColor.stroke)
                ActiveSectionView(store: store)
            }
        }
    }
}

private struct ShellHeader: View {
    var store: MobileShellStore

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: store.selectedSection.symbolName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(ShellColor.accent)
                .frame(width: 36, height: 36)
                .background(ShellColor.panel)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(store.selectedSection.title)
                    .font(.headline.weight(.semibold))
                Text("Vault: Personal Ops")
                    .font(.caption)
                    .foregroundStyle(ShellColor.secondaryText)
            }

            Spacer()

            Button {
                store.selectedSection = .settings
            } label: {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 24))
            }
            .buttonStyle(.plain)
            .foregroundStyle(ShellColor.primaryText)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(ShellColor.surface)
    }
}

private struct SidebarView: View {
    var store: MobileShellStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(ShellColor.accent)
                    .frame(width: 26, height: 26)
                    .overlay(Image(systemName: "terminal").font(.caption.weight(.bold)).foregroundStyle(.black))
                Text("MobileShell")
                    .font(.title3.weight(.semibold))
            }
            .padding(.horizontal, 18)
            .padding(.top, 20)

            VStack(spacing: 4) {
                ForEach(ShellSection.allCases) { section in
                    SidebarRow(
                        section: section,
                        count: count(for: section),
                        isSelected: store.selectedSection == section
                    ) {
                        store.selectedSection = section
                    }
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                Label("Secure local prototype", systemImage: "lock.shield")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ShellColor.accent)
                Text("Hosts, tabs, snippets and transfers are ready for a real SSH backend.")
                    .font(.caption)
                    .foregroundStyle(ShellColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(ShellColor.panel)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
        .foregroundStyle(ShellColor.primaryText)
        .background(ShellColor.surface)
    }

    private func count(for section: ShellSection) -> Int? {
        switch section {
        case .hosts: store.hosts.count
        case .terminals: store.terminalSessions.count
        case .logs: store.sessionLogs.count
        case .sftp: store.sftpItems.count
        case .portForwarding: store.portForwardRules.count
        case .snippets: store.snippets.count
        case .keychain: store.keys.count
        case .history: store.history.count
        case .knownHosts: store.knownHosts.count
        case .settings: nil
        }
    }
}

private struct SidebarRow: View {
    let section: ShellSection
    let count: Int?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: section.symbolName)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 24)
                Text(section.title)
                    .font(.subheadline.weight(.medium))
                Spacer()
                if let count {
                    Text("\(count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ShellColor.secondaryText)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isSelected ? ShellColor.panel : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? ShellColor.primaryText : ShellColor.secondaryText)
        .padding(.horizontal, 10)
    }
}

private struct CompactSectionBar: View {
    var store: MobileShellStore

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ShellSection.allCases) { section in
                    Button {
                        store.selectedSection = section
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: section.symbolName)
                                .font(.system(size: 17, weight: .semibold))
                            Text(section.compactTitle)
                                .font(.caption2.weight(.medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(width: 74, height: 52)
                        .foregroundStyle(store.selectedSection == section ? ShellColor.primaryText : ShellColor.secondaryText)
                        .background(store.selectedSection == section ? ShellColor.panel : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(ShellColor.surface)
    }
}

private struct ActiveSectionView: View {
    var store: MobileShellStore

    var body: some View {
        Group {
            switch store.selectedSection {
            case .hosts:
                HostsView(store: store)
            case .terminals:
                TerminalView(store: store)
            case .logs:
                SessionLogsView(store: store)
            case .sftp:
                SFTPView(store: store)
            case .portForwarding:
                PortForwardingView(store: store)
            case .snippets:
                SnippetsView(store: store)
            case .keychain:
                KeychainView(store: store)
            case .history:
                SimpleListView(title: "History", rows: store.history, symbol: "clock")
            case .knownHosts:
                KnownHostsView(store: store)
            case .settings:
                SettingsView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ShellColor.background)
    }
}

private struct SnippetsView: View {
    @Bindable var store: MobileShellStore
    @State private var isShowingSnippetEditor = false
    @State private var editingSnippet: ShellSnippet?
    @State private var snippetPendingDelete: ShellSnippet?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Command Snippets")
                            .font(.headline.weight(.semibold))
                        Text("Save commands you run often and send them to the terminal quickly.")
                            .font(.caption)
                            .foregroundStyle(ShellColor.secondaryText)
                    }

                    Spacer()

                    Button {
                        editingSnippet = nil
                        isShowingSnippetEditor = true
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

                if store.snippets.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "curlybraces")
                            .font(.title2)
                            .foregroundStyle(ShellColor.secondaryText)
                        Text("No snippets yet")
                            .font(.subheadline.weight(.semibold))
                        Text("Add reusable commands for health checks, logs, deploys, and diagnostics.")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(ShellColor.secondaryText)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity)
                    .background(ShellColor.deepPanel)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                ForEach(store.snippetPackages()) { package in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(package.name)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(ShellColor.accent)
                                .textCase(.uppercase)
                            Spacer()
                            Text("\(package.snippets.count) snippet\(package.snippets.count == 1 ? "" : "s")")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(ShellColor.secondaryText)
                        }
                        .padding(.horizontal, 4)

                        ForEach(package.snippets) { snippet in
                            SnippetRow(
                                snippet: snippet,
                                canRunInVisibleTerminals: !store.visibleTerminalSessions().isEmpty,
                                useAction: {
                                    store.useSnippet(snippet)
                                },
                                runInVisibleTerminalsAction: {
                                    Task { @MainActor in
                                        await store.runSnippetInVisibleTerminals(snippet)
                                    }
                                },
                                editAction: {
                                    editingSnippet = snippet
                                    isShowingSnippetEditor = true
                                },
                                deleteAction: {
                                    snippetPendingDelete = snippet
                                }
                            )
                        }
                    }
                }
            }
            .padding(18)
        }
        .sheet(isPresented: $isShowingSnippetEditor) {
            SnippetEditorSheet(store: store, snippet: editingSnippet)
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog(
            "Delete Snippet?",
            isPresented: Binding(
                get: { snippetPendingDelete != nil },
                set: { isPresented in
                    if !isPresented {
                        snippetPendingDelete = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let snippet = snippetPendingDelete {
                Button("Delete \(snippet.title)", role: .destructive) {
                    store.deleteSnippet(snippet)
                    snippetPendingDelete = nil
                }
            }
        } message: {
            if let snippet = snippetPendingDelete {
                Text("This removes \(snippet.title) from your saved commands.")
            }
        }
    }
}

private struct SnippetRow: View {
    let snippet: ShellSnippet
    let canRunInVisibleTerminals: Bool
    let useAction: () -> Void
    let runInVisibleTerminalsAction: () -> Void
    let editAction: () -> Void
    let deleteAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: useAction) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "curlybraces")
                        .font(.title3)
                        .foregroundStyle(ShellColor.accent)
                        .frame(width: 42, height: 42)
                        .background(ShellColor.panel)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(snippet.title)
                            .font(.subheadline.weight(.semibold))
                        Text(snippet.packageName)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(ShellColor.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(ShellColor.accent.opacity(0.14))
                            .clipShape(Capsule())
                        Text(snippet.command)
                            .font(.caption.monospaced())
                            .foregroundStyle(ShellColor.secondaryText)
                            .lineLimit(2)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.forward")
                        .foregroundStyle(ShellColor.secondaryText)
                }
            }
            .buttonStyle(.plain)

            Menu {
                Button {
                    runInVisibleTerminalsAction()
                } label: {
                    Label("Run in Visible Terminals", systemImage: "play.rectangle.on.rectangle")
                }
                .disabled(!canRunInVisibleTerminals)

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
}

private struct SnippetEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    var store: MobileShellStore
    let snippet: ShellSnippet?
    @State private var title: String
    @State private var packageName: String
    @State private var command: String
    @State private var errorMessage: String?

    init(store: MobileShellStore, snippet: ShellSnippet?) {
        self.store = store
        self.snippet = snippet
        _title = State(initialValue: snippet?.title ?? "")
        _packageName = State(initialValue: snippet?.packageName ?? ShellSnippet.defaultPackageName)
        _command = State(initialValue: snippet?.command ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Snippet") {
                    TextField("Title", text: $title)
                    TextField("Package", text: $packageName)
                    TextEditor(text: $command)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(minHeight: 150)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    Text("Saving a snippet does not run it. Tap a snippet to place its command into the terminal input.")
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
            .navigationTitle(snippet == nil ? "Add Snippet" : "Edit Snippet")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(snippet == nil ? "Add" : "Save") {
                        saveSnippet()
                    }
                }
            }
        }
    }

    private func saveSnippet() {
        let savedSnippet: ShellSnippet?
        if let snippet {
            savedSnippet = store.updateSnippet(snippet, title: title, command: command, packageName: packageName)
        } else {
            savedSnippet = store.addSnippet(title: title, command: command, packageName: packageName)
        }

        if savedSnippet != nil {
            dismiss()
        } else {
            errorMessage = "Enter a title and command before saving."
        }
    }
}

private struct SimpleListView: View {
    let title: String
    let rows: [String]
    let symbol: String

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.title3.weight(.bold))
                ForEach(rows, id: \.self) { row in
                    Label(row, systemImage: symbol)
                        .font(.subheadline)
                        .foregroundStyle(ShellColor.primaryText)
                        .padding(13)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(ShellColor.deepPanel)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(18)
        }
    }
}

enum ShellColor {
    static let background = Color(red: 0.04, green: 0.05, blue: 0.10)
    static let surface = Color(red: 0.08, green: 0.09, blue: 0.16)
    static let panel = Color(red: 0.13, green: 0.14, blue: 0.23)
    static let deepPanel = Color(red: 0.10, green: 0.11, blue: 0.18)
    static let terminal = Color(red: 0.02, green: 0.03, blue: 0.07)
    static let stroke = Color.white.opacity(0.08)
    static let primaryText = Color(red: 0.93, green: 0.95, blue: 0.98)
    static let secondaryText = Color(red: 0.56, green: 0.59, blue: 0.70)
    static let terminalText = Color(red: 0.64, green: 0.88, blue: 0.74)
    static let accent = Color(red: 0.24, green: 0.93, blue: 0.64)
    static let orange = Color(red: 1.00, green: 0.38, blue: 0.18)
    static let pink = Color(red: 0.91, green: 0.12, blue: 0.45)
}
