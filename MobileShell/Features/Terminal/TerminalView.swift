import SwiftUI

struct TerminalView: View {
    @Bindable var store: MobileShellStore

    var selectedSession: TerminalSession? {
        store.selectedTerminalSession
    }

    var selectedTheme: TerminalTheme {
        guard
            let selectedSession,
            let host = store.hosts.first(where: { $0.id == selectedSession.hostID })
        else {
            return .obsidianNeon
        }

        return store.terminalTheme(for: host)
    }

    var selectedFontSize: TerminalFontSize {
        guard
            let selectedSession,
            let host = store.hosts.first(where: { $0.id == selectedSession.hostID })
        else {
            return .standard
        }

        return store.terminalFontSize(for: host)
    }

    var body: some View {
        VStack(spacing: 0) {
            TerminalWorkspaceSwitcher(store: store)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(store.visibleTerminalSessions()) { session in
                        TerminalSessionPill(
                            session: session,
                            isSelected: store.selectedSessionID == session.id,
                            selectAction: {
                                store.selectTerminalSession(session.id)
                            },
                            closeAction: {
                                store.closeTerminalSession(session.id)
                            }
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .background(ShellColor.surface)

            if let selectedSession, selectedSession.state != .connected {
                HStack(spacing: 10) {
                    Label(statusText(for: selectedSession.state), systemImage: "bolt.slash")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ShellColor.orange)
                    Spacer()
                    Button {
                        store.reconnectTerminalSession(selectedSession.id)
                    } label: {
                        Label("Reconnect", systemImage: "arrow.clockwise")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(ShellColor.accent)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(ShellColor.deepPanel)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        if let selectedSession {
                            ForEach(Array(selectedSession.lines.enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .font(.system(size: selectedFontSize.pointSize, design: .monospaced))
                                    .foregroundStyle(index == selectedSession.lines.count - 1 ? selectedTheme.promptForeground : selectedTheme.terminalForeground)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(index)
                            }
                        } else {
                            VStack(spacing: 10) {
                                Image(systemName: "terminal")
                                    .font(.title2)
                                    .foregroundStyle(selectedTheme.mutedForeground)
                                Text("Choose a host to open an SSH tab.")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(selectedTheme.mutedForeground)
                            }
                            .frame(maxWidth: .infinity, minHeight: 240)
                        }
                    }
                    .padding(16)
                }
                .background(selectedTheme.terminalBackground)
                .onChange(of: selectedSession?.lines.count) { _, count in
                    guard let count, count > 0 else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(count - 1, anchor: .bottom)
                    }
                }
            }

            ExtraKeyboardRow(store: store)
            CommandBar(store: store)
        }
    }

    private func statusText(for state: TerminalSessionState) -> String {
        switch state {
        case .connected:
            "Connected"
        case .disconnected:
            "Terminal disconnected"
        case .reconnecting:
            "Reconnecting"
        }
    }
}

private struct TerminalSessionPill: View {
    let session: TerminalSession
    let isSelected: Bool
    let selectAction: () -> Void
    let closeAction: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: selectAction) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                    Text(session.hostName)
                        .lineLimit(1)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(ShellColor.primaryText)
            }
            .buttonStyle(.plain)

            Button(action: closeAction) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(ShellColor.secondaryText)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close terminal \(session.hostName)")
        }
        .padding(.leading, 11)
        .padding(.trailing, 7)
        .frame(height: 34)
        .background(isSelected ? ShellColor.panel : ShellColor.deepPanel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var statusColor: Color {
        switch session.state {
        case .connected:
            ShellColor.accent
        case .disconnected:
            ShellColor.pink
        case .reconnecting:
            ShellColor.orange
        }
    }
}

private struct ExtraKeyboardRow: View {
    @Bindable var store: MobileShellStore

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TerminalKeyboardShortcut.allCases) { shortcut in
                    Button {
                        Task { @MainActor in
                            await store.sendTerminalKeyboardShortcut(shortcut)
                        }
                    } label: {
                        Text(shortcut.label)
                            .font(.caption.weight(.semibold))
                            .frame(width: shortcut.label.count > 4 ? 64 : 48, height: 34)
                            .background(ShellColor.panel)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(ShellColor.primaryText)
                    .accessibilityLabel("Send terminal shortcut \(shortcut.label)")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(ShellColor.surface)
    }
}

private struct CommandBar: View {
    @Bindable var store: MobileShellStore

    var body: some View {
        VStack(spacing: 0) {
            if !suggestions.isEmpty {
                CommandSuggestionStrip(suggestions: suggestions) { suggestion in
                    store.applyCommandSuggestion(suggestion)
                }
            }

            HStack(spacing: 10) {
                TextField("Run command", text: commandDraftBinding)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 14, design: .monospaced))
                    .padding(.horizontal, 12)
                    .frame(height: 42)
                    .background(ShellColor.panel)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onSubmit {
                        submitCommand()
                    }

                if isBroadcastEnabled {
                    Button {
                        broadcastCommand()
                    } label: {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.headline.weight(.bold))
                            .frame(width: 42, height: 42)
                            .background(ShellColor.orange)
                            .foregroundStyle(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(store.visibleTerminalSessions().isEmpty)
                    .accessibilityLabel("Broadcast command to workspace")
                }

                Button {
                    submitCommand()
                } label: {
                    Image(systemName: "return")
                        .font(.headline.weight(.bold))
                        .frame(width: 42, height: 42)
                        .background(ShellColor.accent)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(store.selectedTerminalSession == nil)
            }
            .padding(12)
        }
        .background(ShellColor.surface)
    }

    private var suggestions: [CommandSuggestion] {
        store.commandSuggestions(for: currentDraft)
    }

    private var currentDraft: String {
        store.selectedTerminalSession?.commandDraft ?? store.commandInput
    }

    private var isBroadcastEnabled: Bool {
        store.selectedTerminalWorkspace?.isBroadcastEnabled == true
    }

    private var commandDraftBinding: Binding<String> {
        Binding(
            get: {
                store.selectedTerminalSession?.commandDraft ?? store.commandInput
            },
            set: { draft in
                if let sessionID = store.selectedTerminalSession?.id {
                    store.updateCommandDraft(draft, for: sessionID)
                } else {
                    store.commandInput = draft
                }
            }
        )
    }

    @MainActor
    private func submitCommand() {
        let command = store.selectedTerminalSession?.commandDraft ?? store.commandInput
        Task { @MainActor in
            await store.runRemoteCommand(command)
        }
    }

    @MainActor
    private func broadcastCommand() {
        let command = store.selectedTerminalSession?.commandDraft ?? store.commandInput
        Task { @MainActor in
            await store.broadcastCommand(command)
        }
    }
}
