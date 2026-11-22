import Foundation

extension MobileShellStore {
    @MainActor
    func openSFTP(for host: ShellHost, path: String = "/home/deploy") async {
        selectedSection = .sftp
        selectedSFTPHostID = host.id
        await refreshSFTPDirectory(path: path)
    }

    @MainActor
    func refreshSFTPDirectory(path: String? = nil) async {
        let requestedPath = path ?? sftpPath
        guard let selectedSFTPHostID,
              let host = hosts.first(where: { $0.id == selectedSFTPHostID })
        else { return }

        sftpPath = requestedPath
        isSFTPLoading = true
        sftpErrorMessage = nil
        sftpItems = []

        do {
            let request = try SSHConnectionRequestBuilder(
                credentialVault: credentialVault,
                hosts: hosts,
                identities: identities,
                keys: keys,
                certificates: certificates,
                hostGroupProfiles: hostGroupProfiles,
                knownHosts: knownHosts
            ).request(for: host)
            sftpItems = try await sftpClient.listDirectory(at: requestedPath, using: request)
            history.insert("Browsed \(host.name):\(requestedPath)", at: 0)
        } catch {
            if recordHostKeyChallenge(error, action: .sftpDirectory(hostID: host.id, path: requestedPath)) {
                isSFTPLoading = false
                return
            }
            sftpErrorMessage = "SFTP error: \(error.localizedDescription)"
        }

        isSFTPLoading = false
    }

    @MainActor
    func openSFTPItem(_ item: SFTPItem) async {
        guard item.kind == "folder" else { return }
        await refreshSFTPDirectory(path: childSFTPPath(named: item.name))
    }

    @MainActor
    func openParentSFTPDirectory() async {
        let parentPath = parentSFTPPath()
        guard parentPath != sftpPath else { return }
        await refreshSFTPDirectory(path: parentPath)
    }

    @MainActor
    func createSFTPDirectory(named folderName: String) async {
        let normalizedName = normalizedSFTPName(folderName)
        guard !normalizedName.isEmpty else { return }

        let path = childSFTPPath(named: normalizedName)
        await performSFTPOperation(
            historyEntry: "Created directory %@:\(path)"
        ) { request in
            try await sftpClient.createDirectory(at: path, using: request)
        }
    }

    @MainActor
    func renameSFTPItem(_ item: SFTPItem, to newName: String) async {
        let normalizedName = normalizedSFTPName(newName)
        guard !normalizedName.isEmpty else { return }

        let oldPath = path(for: item)
        let newPath = childSFTPPath(named: normalizedName)
        await performSFTPOperation(
            historyEntry: "Renamed %@:\(oldPath) to \(newPath)"
        ) { request in
            try await sftpClient.renameItem(at: oldPath, to: newPath, using: request)
        }
    }

    @MainActor
    func deleteSFTPItem(_ item: SFTPItem) async {
        let path = path(for: item)
        await performSFTPOperation(
            historyEntry: "Deleted %@:\(path)"
        ) { request in
            try await sftpClient.deleteItem(at: path, isDirectory: item.kind == "folder", using: request)
        }
    }

    @MainActor
    func downloadSFTPItem(_ item: SFTPItem) async {
        guard item.kind != "folder",
              let selectedSFTPHostID,
              let host = hosts.first(where: { $0.id == selectedSFTPHostID })
        else { return }

        let remotePath = path(for: item)
        isSFTPLoading = true
        sftpErrorMessage = nil
        downloadedSFTPFile = nil

        do {
            let request = try SSHConnectionRequestBuilder(
                credentialVault: credentialVault,
                hosts: hosts,
                identities: identities,
                keys: keys,
                certificates: certificates,
                hostGroupProfiles: hostGroupProfiles,
                knownHosts: knownHosts
            ).request(for: host)
            let data = try await sftpClient.downloadFile(at: remotePath, using: request)
            downloadedSFTPFile = SFTPDownloadedFile(name: item.name, remotePath: remotePath, data: data)
            history.insert("Downloaded \(host.name):\(remotePath)", at: 0)
        } catch {
            sftpErrorMessage = "SFTP error: \(error.localizedDescription)"
        }

        isSFTPLoading = false
    }

    @MainActor
    func uploadSFTPFile(named fileName: String, data: Data) async {
        let normalizedName = normalizedSFTPName(fileName)
        guard !normalizedName.isEmpty else { return }

        let remotePath = childSFTPPath(named: normalizedName)
        await performSFTPOperation(
            historyEntry: "Uploaded %@:\(remotePath)"
        ) { request in
            try await sftpClient.uploadFile(data, to: remotePath, using: request)
        }
    }

    @MainActor
    private func performSFTPOperation(
        historyEntry: String,
        operation: (SSHConnectionRequest) async throws -> Void
    ) async {
        guard let selectedSFTPHostID,
              let host = hosts.first(where: { $0.id == selectedSFTPHostID })
        else { return }

        let refreshPath = sftpPath
        isSFTPLoading = true
        sftpErrorMessage = nil

        do {
            let request = try SSHConnectionRequestBuilder(
                credentialVault: credentialVault,
                hosts: hosts,
                identities: identities,
                keys: keys,
                certificates: certificates,
                hostGroupProfiles: hostGroupProfiles,
                knownHosts: knownHosts
            ).request(for: host)
            try await operation(request)
            isSFTPLoading = false
            await refreshSFTPDirectory(path: refreshPath)
            history.insert(String(format: historyEntry, host.name), at: 0)
        } catch {
            sftpErrorMessage = "SFTP error: \(error.localizedDescription)"
            isSFTPLoading = false
        }
    }

    private func childSFTPPath(named childName: String) -> String {
        let trimmedPath = sftpPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let normalizedChildName = childName.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        if trimmedPath.isEmpty {
            return "/\(normalizedChildName)"
        }
        return "/\(trimmedPath)/\(normalizedChildName)"
    }

    private func parentSFTPPath() -> String {
        let trimmedPath = sftpPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmedPath.isEmpty else { return "/" }

        var components = trimmedPath.split(separator: "/").map(String.init)
        components.removeLast()

        guard !components.isEmpty else { return "/" }
        return "/" + components.joined(separator: "/")
    }

    private func path(for item: SFTPItem) -> String {
        childSFTPPath(named: item.name)
    }

    private func normalizedSFTPName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
