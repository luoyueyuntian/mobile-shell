import SwiftUI
import UniformTypeIdentifiers

struct SFTPView: View {
    @Bindable var store: MobileShellStore
    @State private var isCreatingFolder = false
    @State private var isImportingFile = false
    @State private var newFolderName = ""
    @State private var itemPendingRename: SFTPItem?
    @State private var renameName = ""
    @State private var itemPendingDelete: SFTPItem?

    private var selectedHostName: String {
        guard let hostID = store.selectedSFTPHostID,
              let host = store.hosts.first(where: { $0.id == hostID })
        else { return "No host selected" }
        return host.name
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Label(selectedHostName, systemImage: "folder")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button {
                        isImportingFile = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.selectedSFTPHostID == nil || store.isSFTPLoading)

                    Button {
                        newFolderName = ""
                        isCreatingFolder = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.selectedSFTPHostID == nil || store.isSFTPLoading)

                    Button {
                        Task { @MainActor in
                            await store.refreshSFTPDirectory()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.selectedSFTPHostID == nil || store.isSFTPLoading)
                }

                HStack(spacing: 10) {
                    Button {
                        Task { @MainActor in
                            await store.openParentSFTPDirectory()
                        }
                    } label: {
                        Label("Up", systemImage: "arrow.up")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.selectedSFTPHostID == nil || store.sftpPath == "/" || store.isSFTPLoading)

                    Text(store.sftpPath)
                        .font(.caption.monospaced())
                        .foregroundStyle(ShellColor.secondaryText)
                    Spacer()
                }

                if let downloadedFile = store.downloadedSFTPFile {
                    HStack(spacing: 10) {
                        Label(downloadedMessage(for: downloadedFile), systemImage: "arrow.down.doc.fill")
                            .font(.caption)
                            .foregroundStyle(ShellColor.accent)

                        Spacer()

                        ShareLink(
                            item: downloadedFile,
                            preview: SharePreview(
                                downloadedFile.shareExportFileName,
                                icon: Image(systemName: "doc.fill")
                            )
                        ) {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.bordered)
                        .tint(ShellColor.accent)
                    }
                    .padding(12)
                    .background(ShellColor.panel)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                if store.isSFTPLoading {
                    ProgressView("Loading remote files...")
                        .tint(ShellColor.accent)
                }

                if let message = store.sftpErrorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(ShellColor.pink)
                        .padding(12)
                        .background(ShellColor.panel)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                if store.sftpItems.isEmpty && !store.isSFTPLoading {
                    Text(store.selectedSFTPHostID == nil ? "Open SFTP from a host row to browse remote files." : "No files in this directory.")
                        .font(.subheadline)
                        .foregroundStyle(ShellColor.secondaryText)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(ShellColor.deepPanel)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                ForEach(store.sftpItems) { item in
                    SFTPFileRow(
                        item: item,
                        openAction: {
                            Task { @MainActor in
                                await store.openSFTPItem(item)
                            }
                        },
                        renameAction: {
                            renameName = item.name
                            itemPendingRename = item
                        },
                        downloadAction: {
                            Task { @MainActor in
                                await store.downloadSFTPItem(item)
                            }
                        },
                        deleteAction: {
                            itemPendingDelete = item
                        }
                    )
                }
            }
            .padding(18)
        }
        .alert("New Folder", isPresented: $isCreatingFolder) {
            TextField("Folder name", text: $newFolderName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Create") {
                let folderName = newFolderName
                Task { @MainActor in
                    await store.createSFTPDirectory(named: folderName)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Create a directory in \(store.sftpPath).")
        }
        .alert(
            "Rename",
            isPresented: Binding(
                get: { itemPendingRename != nil },
                set: { isPresented in
                    if !isPresented {
                        itemPendingRename = nil
                    }
                }
            )
        ) {
            TextField("New name", text: $renameName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Rename") {
                guard let item = itemPendingRename else { return }
                let newName = renameName
                itemPendingRename = nil
                Task { @MainActor in
                    await store.renameSFTPItem(item, to: newName)
                }
            }
            Button("Cancel", role: .cancel) {
                itemPendingRename = nil
            }
        } message: {
            Text("Rename the selected remote item.")
        }
        .alert(
            "Delete Item?",
            isPresented: Binding(
                get: { itemPendingDelete != nil },
                set: { isPresented in
                    if !isPresented {
                        itemPendingDelete = nil
                    }
                }
            )
        ) {
            Button("Delete", role: .destructive) {
                guard let item = itemPendingDelete else { return }
                itemPendingDelete = nil
                Task { @MainActor in
                    await store.deleteSFTPItem(item)
                }
            }
            Button("Cancel", role: .cancel) {
                itemPendingDelete = nil
            }
        } message: {
            Text("This removes the selected remote item from \(store.sftpPath).")
        }
        .fileImporter(
            isPresented: $isImportingFile,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            handleImportedFile(result)
        }
    }

    private func downloadedMessage(for file: SFTPDownloadedFile) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return "Downloaded \(file.name) · \(formatter.string(fromByteCount: Int64(file.data.count)))"
    }

    private func handleImportedFile(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: url)
            let fileName = url.lastPathComponent
            Task { @MainActor in
                await store.uploadSFTPFile(named: fileName, data: data)
            }
        } catch {
            Task { @MainActor in
                store.sftpErrorMessage = "SFTP error: \(error.localizedDescription)"
            }
        }
    }
}

private struct SFTPFileRow: View {
    let item: SFTPItem
    let openAction: () -> Void
    let renameAction: () -> Void
    let downloadAction: () -> Void
    let deleteAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 42, height: 42)
                .background(ShellColor.panel)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                Text("\(item.kind.uppercased()) · \(item.size)")
                    .font(.caption)
                    .foregroundStyle(ShellColor.secondaryText)
            }
            Spacer()
            if item.kind == "folder" {
                Image(systemName: "chevron.right")
                    .foregroundStyle(ShellColor.secondaryText)
            }
            Menu {
                Button("Rename", systemImage: "pencil", action: renameAction)
                if item.kind != "folder" {
                    Button("Download", systemImage: "square.and.arrow.down", action: downloadAction)
                }
                Button("Delete", systemImage: "trash", role: .destructive, action: deleteAction)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(ShellColor.secondaryText)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
        }
        .padding(13)
        .background(ShellColor.deepPanel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            if item.kind == "folder" {
                openAction()
            }
        }
    }

    private var icon: String {
        switch item.kind {
        case "folder": "folder.fill"
        case "archive": "archivebox.fill"
        case "shell": "terminal.fill"
        default: "doc.text.fill"
        }
    }

    private var iconColor: Color {
        item.kind == "folder" ? ShellColor.accent : ShellColor.orange
    }
}
