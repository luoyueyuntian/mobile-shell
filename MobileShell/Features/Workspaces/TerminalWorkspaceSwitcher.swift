import SwiftUI

struct TerminalWorkspaceSwitcher: View {
    @Bindable var store: MobileShellStore
    @State private var isCreatingWorkspace = false
    @State private var workspaceName = ""
    @State private var isSavingTemplate = false
    @State private var templateName = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    workspaceButton(
                        title: "All",
                        count: store.terminalSessions.count,
                        isSelected: store.selectedWorkspaceID == nil
                    ) {
                        store.selectTerminalWorkspace(nil)
                    }

                    ForEach(store.terminalWorkspaces) { workspace in
                        workspaceButton(
                            title: workspace.name,
                            count: store.terminalSessionCount(for: workspace),
                            isSelected: store.selectedWorkspaceID == workspace.id
                        ) {
                            store.selectTerminalWorkspace(workspace.id)
                        }
                    }

                    Button {
                        workspaceName = ""
                        isCreatingWorkspace = true
                    } label: {
                        Label("New", systemImage: "plus")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 10)
                            .frame(height: 32)
                            .background(ShellColor.panel)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(ShellColor.accent)
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)
            }

            if !store.terminalWorkspaceTemplates.isEmpty {
                templateShelf
            }

            if let workspace = store.selectedTerminalWorkspace {
                workspaceActions(for: workspace)
            }
        }
        .background(ShellColor.surface)
        .alert("New Workspace", isPresented: $isCreatingWorkspace) {
            TextField("Workspace name", text: $workspaceName)
                .textInputAutocapitalization(.words)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                _ = store.createTerminalWorkspace(name: workspaceName)
            }
        } message: {
            Text("Group related terminal tabs into a focused workspace.")
        }
        .alert("Save Workspace Template", isPresented: $isSavingTemplate) {
            TextField("Template name", text: $templateName)
                .textInputAutocapitalization(.words)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                _ = store.saveSelectedWorkspaceAsTemplate(name: templateName)
                templateName = ""
            }
            .disabled(templateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Save this workspace host set so you can reopen it later.")
        }
    }

    private var templateShelf: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.terminalWorkspaceTemplates) { template in
                    Button {
                        _ = store.openWorkspaceTemplate(template)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Label(template.name, systemImage: "rectangle.stack")
                                .font(.caption.weight(.bold))
                                .lineLimit(1)

                            Text(templateSubtitle(for: template))
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                                .foregroundStyle(ShellColor.secondaryText)
                        }
                        .foregroundStyle(ShellColor.primaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(ShellColor.deepPanel)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open workspace template \(template.name)")
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        }
    }

    private func workspaceActions(for workspace: TerminalWorkspace) -> some View {
        VStack(spacing: 8) {
            Button {
                store.setBroadcastEnabled(!workspace.isBroadcastEnabled, for: workspace.id)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                    Text(workspace.isBroadcastEnabled ? "Broadcast on" : "Broadcast off")
                    Spacer()
                    Text("\(store.terminalSessionCount(for: workspace)) sessions")
                        .foregroundStyle(ShellColor.secondaryText)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(workspace.isBroadcastEnabled ? ShellColor.accent : ShellColor.primaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(ShellColor.deepPanel)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            Button {
                templateName = "\(workspace.name) Template"
                isSavingTemplate = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "bookmark")
                    Text("Save Template")
                    Spacer()
                    Text("Reopen later")
                        .foregroundStyle(ShellColor.secondaryText)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(ShellColor.primaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(ShellColor.panel)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .opacity(store.terminalSessionCount(for: workspace) == 0 ? 0.45 : 1)
            }
            .buttonStyle(.plain)
            .disabled(store.terminalSessionCount(for: workspace) == 0)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func templateSubtitle(for template: TerminalWorkspaceTemplate) -> String {
        let hostNames = store.templateHostNames(for: template)
        guard !hostNames.isEmpty else { return "\(template.hostIDs.count) saved hosts" }
        guard hostNames.count > 2 else { return hostNames.joined(separator: ", ") }
        return "\(hostNames[0]), \(hostNames[1]) +\(hostNames.count - 2)"
    }

    private func workspaceButton(
        title: String,
        count: Int,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .lineLimit(1)
                Text("\(count)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(isSelected ? .black.opacity(0.65) : ShellColor.secondaryText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isSelected ? .black.opacity(0.12) : ShellColor.surface)
                    .clipShape(Capsule())
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(isSelected ? .black : ShellColor.primaryText)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(isSelected ? ShellColor.accent : ShellColor.deepPanel)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) workspace, \(count) terminal sessions")
    }
}
