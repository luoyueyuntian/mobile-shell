import XCTest
@testable import MobileShell

final class SFTPStoreTests: XCTestCase {
    @MainActor
    func testOpeningSFTPUsesVaultRequestAndUpdatesDirectoryListing() async throws {
        let hostID = UUID(uuidString: "ABCDABCD-1111-2222-3333-ABCDABCDABCD")!
        let knownHost = KnownHost(
            host: "[files.example.com]:2202",
            keyType: "ssh-ed25519",
            fingerprint: "SHA256:files"
        )
        let host = ShellHost(
            id: hostID,
            name: "files-prod",
            address: "files.example.com",
            port: 2202,
            username: "deploy",
            group: "Production",
            tags: ["sftp"],
            status: .idle
        )
        let credentialVault = InMemoryCredentialVault()
        try credentialVault.savePassword("file-secret", forHostID: hostID)
        let sftpClient = RecordingSFTPDirectoryListingClient(
            result: .success([
                SFTPItem(
                    id: UUID(uuidString: "01010101-0101-0101-0101-010101010101")!,
                    name: "releases",
                    kind: "folder",
                    size: "--"
                ),
                SFTPItem(
                    id: UUID(uuidString: "02020202-0202-0202-0202-020202020202")!,
                    name: "deploy.log",
                    kind: "text",
                    size: "2 KB"
                )
            ])
        )
        let store = MobileShellStore(
            hosts: [host],
            knownHosts: [knownHost],
            credentialVault: credentialVault,
            sftpClient: sftpClient
        )

        await store.openSFTP(for: host, path: "/home/deploy")

        XCTAssertEqual(store.selectedSection, .sftp)
        XCTAssertEqual(store.selectedSFTPHostID, hostID)
        XCTAssertEqual(store.sftpPath, "/home/deploy")
        XCTAssertFalse(store.isSFTPLoading)
        XCTAssertNil(store.sftpErrorMessage)
        XCTAssertEqual(sftpClient.paths, ["/home/deploy"])
        XCTAssertEqual(sftpClient.requests.first?.hostname, "files.example.com")
        XCTAssertEqual(sftpClient.requests.first?.port, 2202)
        XCTAssertEqual(sftpClient.requests.first?.password, "file-secret")
        XCTAssertEqual(sftpClient.requests.first?.knownHosts, [knownHost])
        XCTAssertEqual(store.sftpItems.map(\.name), ["releases", "deploy.log"])
        XCTAssertEqual(store.history.first, "Browsed files-prod:/home/deploy")
    }

    @MainActor
    func testTrustingSFTPHostKeyChallengeStoresFingerprintAndRetriesDirectoryListing() async throws {
        let hostID = UUID(uuidString: "ABCDABCD-4444-5555-6666-ABCDABCDABCD")!
        let host = ShellHost(
            id: hostID,
            name: "files-new",
            address: "new-files.example.com",
            port: 2202,
            username: "deploy",
            group: "Production",
            tags: ["sftp"],
            status: .idle
        )
        let challenge = HostKeyChallenge(
            id: UUID(uuidString: "BCBCBCBC-1111-2222-3333-BCBCBCBCBCBC")!,
            hostname: "new-files.example.com",
            port: 2202,
            keyType: "ssh-ed25519",
            fingerprint: "SHA256:newfiles"
        )
        let credentialVault = InMemoryCredentialVault()
        try credentialVault.savePassword("file-secret", forHostID: hostID)
        let sftpClient = RecordingSFTPDirectoryListingClient(results: [
            .failure(challenge),
            .success([
                SFTPItem(
                    id: UUID(uuidString: "03030303-0303-0303-0303-030303030303")!,
                    name: "release.tar.gz",
                    kind: "archive",
                    size: "9 MB"
                )
            ])
        ])
        let store = MobileShellStore(
            hosts: [host],
            credentialVault: credentialVault,
            sftpClient: sftpClient
        )

        await store.openSFTP(for: host, path: "/srv")

        XCTAssertEqual(sftpClient.paths, ["/srv"])
        XCTAssertEqual(store.pendingHostKeyChallenge, challenge)
        XCTAssertTrue(store.sftpItems.isEmpty)
        XCTAssertNil(store.sftpErrorMessage)

        await store.trustPendingHostKey()

        XCTAssertNil(store.pendingHostKeyChallenge)
        XCTAssertEqual(sftpClient.paths, ["/srv", "/srv"])
        XCTAssertEqual(sftpClient.requests.last?.knownHosts.first?.host, "[new-files.example.com]:2202")
        XCTAssertEqual(store.knownHosts.first?.knownHostLine, "[new-files.example.com]:2202 ssh-ed25519 SHA256:newfiles")
        XCTAssertEqual(store.sftpItems.map(\.name), ["release.tar.gz"])
    }

    @MainActor
    func testOpeningSFTPFailureStoresErrorAndStopsLoading() async throws {
        let hostID = UUID(uuidString: "BCDEBCDE-1111-2222-3333-BCDEBCDEBCDE")!
        let host = ShellHost(
            id: hostID,
            name: "files-down",
            address: "down.example.com",
            username: "deploy",
            group: "Production",
            tags: ["sftp"],
            status: .idle
        )
        let credentialVault = InMemoryCredentialVault()
        try credentialVault.savePassword("file-secret", forHostID: hostID)
        let store = MobileShellStore(
            hosts: [host],
            credentialVault: credentialVault,
            sftpClient: RecordingSFTPDirectoryListingClient(result: .failure(RecordingSFTPError.unreachable))
        )

        await store.openSFTP(for: host, path: "/var/www")

        XCTAssertEqual(store.selectedSection, .sftp)
        XCTAssertEqual(store.sftpPath, "/var/www")
        XCTAssertFalse(store.isSFTPLoading)
        XCTAssertEqual(store.sftpItems, [])
        XCTAssertEqual(store.sftpErrorMessage, "SFTP error: SFTP fixture unreachable")
    }

    @MainActor
    func testOpeningSFTPFolderItemRefreshesChildDirectory() async throws {
        let hostID = UUID(uuidString: "CDEFCDEF-1111-2222-3333-CDEFCDEFCDEF")!
        let host = ShellHost(
            id: hostID,
            name: "files-prod",
            address: "files.example.com",
            username: "deploy",
            group: "Production",
            tags: ["sftp"],
            status: .idle
        )
        let credentialVault = InMemoryCredentialVault()
        try credentialVault.savePassword("file-secret", forHostID: hostID)
        let sftpClient = RecordingSFTPDirectoryListingClient(
            result: .success([
                SFTPItem(
                    id: UUID(uuidString: "03030303-0303-0303-0303-030303030303")!,
                    name: "releases",
                    kind: "folder",
                    size: "--"
                )
            ])
        )
        let store = MobileShellStore(
            hosts: [host],
            credentialVault: credentialVault,
            sftpClient: sftpClient
        )

        await store.openSFTP(for: host, path: "/home/deploy")
        await store.openSFTPItem(store.sftpItems[0])

        XCTAssertEqual(sftpClient.paths, ["/home/deploy", "/home/deploy/releases"])
        XCTAssertEqual(store.sftpPath, "/home/deploy/releases")
        XCTAssertEqual(store.history.first, "Browsed files-prod:/home/deploy/releases")
    }

    @MainActor
    func testOpeningSFTPParentDirectoryRefreshesParentPath() async throws {
        let hostID = UUID(uuidString: "DEF0DEF0-1111-2222-3333-DEF0DEF0DEF0")!
        let host = ShellHost(
            id: hostID,
            name: "files-prod",
            address: "files.example.com",
            username: "deploy",
            group: "Production",
            tags: ["sftp"],
            status: .idle
        )
        let credentialVault = InMemoryCredentialVault()
        try credentialVault.savePassword("file-secret", forHostID: hostID)
        let sftpClient = RecordingSFTPDirectoryListingClient(result: .success([]))
        let store = MobileShellStore(
            hosts: [host],
            credentialVault: credentialVault,
            sftpClient: sftpClient
        )

        await store.openSFTP(for: host, path: "/var/www/releases")
        await store.openParentSFTPDirectory()

        XCTAssertEqual(sftpClient.paths, ["/var/www/releases", "/var/www"])
        XCTAssertEqual(store.sftpPath, "/var/www")
    }

    @MainActor
    func testCreatingSFTPDirectoryRunsRemoteMkdirAndRefreshesCurrentPath() async throws {
        let hostID = UUID(uuidString: "F0F0F0F0-1111-2222-3333-F0F0F0F0F0F0")!
        let host = ShellHost(
            id: hostID,
            name: "files-prod",
            address: "files.example.com",
            port: 2202,
            username: "deploy",
            group: "Production",
            tags: ["sftp"],
            status: .idle
        )
        let credentialVault = InMemoryCredentialVault()
        try credentialVault.savePassword("file-secret", forHostID: hostID)
        let sftpClient = RecordingSFTPDirectoryListingClient(result: .success([]))
        let store = MobileShellStore(
            hosts: [host],
            credentialVault: credentialVault,
            sftpClient: sftpClient
        )

        await store.openSFTP(for: host, path: "/home/deploy")
        await store.createSFTPDirectory(named: " releases ")

        XCTAssertEqual(sftpClient.operations, [.createDirectory(path: "/home/deploy/releases")])
        XCTAssertEqual(sftpClient.paths, ["/home/deploy", "/home/deploy"])
        XCTAssertEqual(sftpClient.operationRequests.first?.port, 2202)
        XCTAssertEqual(sftpClient.operationRequests.first?.password, "file-secret")
        XCTAssertNil(store.sftpErrorMessage)
        XCTAssertFalse(store.isSFTPLoading)
        XCTAssertEqual(store.history.first, "Created directory files-prod:/home/deploy/releases")
    }

    @MainActor
    func testRenamingSFTPItemRunsRemoteRenameAndRefreshesCurrentPath() async throws {
        let hostID = UUID(uuidString: "A0A0A0A0-1111-2222-3333-A0A0A0A0A0A0")!
        let host = ShellHost(
            id: hostID,
            name: "files-prod",
            address: "files.example.com",
            username: "deploy",
            group: "Production",
            tags: ["sftp"],
            status: .idle
        )
        let credentialVault = InMemoryCredentialVault()
        try credentialVault.savePassword("file-secret", forHostID: hostID)
        let item = SFTPItem(
            id: UUID(uuidString: "04040404-0404-0404-0404-040404040404")!,
            name: "deploy.log",
            kind: "text",
            size: "2 KB"
        )
        let sftpClient = RecordingSFTPDirectoryListingClient(result: .success([item]))
        let store = MobileShellStore(
            hosts: [host],
            credentialVault: credentialVault,
            sftpClient: sftpClient
        )

        await store.openSFTP(for: host, path: "/var/log")
        await store.renameSFTPItem(item, to: "server.log")

        XCTAssertEqual(sftpClient.operations, [.rename(oldPath: "/var/log/deploy.log", newPath: "/var/log/server.log")])
        XCTAssertEqual(sftpClient.paths, ["/var/log", "/var/log"])
        XCTAssertEqual(store.history.first, "Renamed files-prod:/var/log/deploy.log to /var/log/server.log")
    }

    @MainActor
    func testDeletingSFTPFileRunsRemoteRemoveAndRefreshesCurrentPath() async throws {
        let hostID = UUID(uuidString: "B0B0B0B0-1111-2222-3333-B0B0B0B0B0B0")!
        let host = ShellHost(
            id: hostID,
            name: "files-prod",
            address: "files.example.com",
            username: "deploy",
            group: "Production",
            tags: ["sftp"],
            status: .idle
        )
        let credentialVault = InMemoryCredentialVault()
        try credentialVault.savePassword("file-secret", forHostID: hostID)
        let item = SFTPItem(
            id: UUID(uuidString: "05050505-0505-0505-0505-050505050505")!,
            name: "old.log",
            kind: "text",
            size: "1 KB"
        )
        let sftpClient = RecordingSFTPDirectoryListingClient(result: .success([item]))
        let store = MobileShellStore(
            hosts: [host],
            credentialVault: credentialVault,
            sftpClient: sftpClient
        )

        await store.openSFTP(for: host, path: "/var/log")
        await store.deleteSFTPItem(item)

        XCTAssertEqual(sftpClient.operations, [.deleteFile(path: "/var/log/old.log")])
        XCTAssertEqual(sftpClient.paths, ["/var/log", "/var/log"])
        XCTAssertEqual(store.history.first, "Deleted files-prod:/var/log/old.log")
    }

    @MainActor
    func testDeletingSFTPFolderRunsRemoteRmdirAndRefreshesCurrentPath() async throws {
        let hostID = UUID(uuidString: "C0C0C0C0-1111-2222-3333-C0C0C0C0C0C0")!
        let host = ShellHost(
            id: hostID,
            name: "files-prod",
            address: "files.example.com",
            username: "deploy",
            group: "Production",
            tags: ["sftp"],
            status: .idle
        )
        let credentialVault = InMemoryCredentialVault()
        try credentialVault.savePassword("file-secret", forHostID: hostID)
        let item = SFTPItem(
            id: UUID(uuidString: "06060606-0606-0606-0606-060606060606")!,
            name: "old-release",
            kind: "folder",
            size: "--"
        )
        let sftpClient = RecordingSFTPDirectoryListingClient(result: .success([item]))
        let store = MobileShellStore(
            hosts: [host],
            credentialVault: credentialVault,
            sftpClient: sftpClient
        )

        await store.openSFTP(for: host, path: "/home/deploy")
        await store.deleteSFTPItem(item)

        XCTAssertEqual(sftpClient.operations, [.deleteDirectory(path: "/home/deploy/old-release")])
        XCTAssertEqual(sftpClient.paths, ["/home/deploy", "/home/deploy"])
    }

    @MainActor
    func testFailedSFTPOperationStoresErrorAndDoesNotRefresh() async throws {
        let hostID = UUID(uuidString: "D0D0D0D0-1111-2222-3333-D0D0D0D0D0D0")!
        let host = ShellHost(
            id: hostID,
            name: "files-prod",
            address: "files.example.com",
            username: "deploy",
            group: "Production",
            tags: ["sftp"],
            status: .idle
        )
        let credentialVault = InMemoryCredentialVault()
        try credentialVault.savePassword("file-secret", forHostID: hostID)
        let item = SFTPItem(
            id: UUID(uuidString: "07070707-0707-0707-0707-070707070707")!,
            name: "locked.log",
            kind: "text",
            size: "1 KB"
        )
        let sftpClient = RecordingSFTPDirectoryListingClient(
            result: .success([item]),
            operationResult: .failure(RecordingSFTPError.unreachable)
        )
        let store = MobileShellStore(
            hosts: [host],
            credentialVault: credentialVault,
            sftpClient: sftpClient
        )

        await store.openSFTP(for: host, path: "/var/log")
        await store.deleteSFTPItem(item)

        XCTAssertEqual(sftpClient.operations, [.deleteFile(path: "/var/log/locked.log")])
        XCTAssertEqual(sftpClient.paths, ["/var/log"])
        XCTAssertFalse(store.isSFTPLoading)
        XCTAssertEqual(store.sftpErrorMessage, "SFTP error: SFTP fixture unreachable")
    }

    @MainActor
    func testDownloadingSFTPFileStoresDownloadedFileAndHistory() async throws {
        let hostID = UUID(uuidString: "E0E0E0E0-1111-2222-3333-E0E0E0E0E0E0")!
        let host = ShellHost(
            id: hostID,
            name: "files-prod",
            address: "files.example.com",
            port: 2202,
            username: "deploy",
            group: "Production",
            tags: ["sftp"],
            status: .idle
        )
        let credentialVault = InMemoryCredentialVault()
        try credentialVault.savePassword("file-secret", forHostID: hostID)
        let item = SFTPItem(
            id: UUID(uuidString: "08080808-0808-0808-0808-080808080808")!,
            name: "app.log",
            kind: "text",
            size: "5 B"
        )
        let sftpClient = RecordingSFTPDirectoryListingClient(
            result: .success([item]),
            downloadResult: .success(Data("hello".utf8))
        )
        let store = MobileShellStore(
            hosts: [host],
            credentialVault: credentialVault,
            sftpClient: sftpClient
        )

        await store.openSFTP(for: host, path: "/var/log")
        await store.downloadSFTPItem(item)

        let downloadedFile = try XCTUnwrap(store.downloadedSFTPFile)
        XCTAssertEqual(downloadedFile.name, "app.log")
        XCTAssertEqual(downloadedFile.remotePath, "/var/log/app.log")
        XCTAssertEqual(downloadedFile.data, Data("hello".utf8))
        XCTAssertEqual(sftpClient.operations, [.download(path: "/var/log/app.log")])
        XCTAssertEqual(sftpClient.operationRequests.first?.port, 2202)
        XCTAssertEqual(sftpClient.operationRequests.first?.password, "file-secret")
        XCTAssertEqual(sftpClient.paths, ["/var/log"])
        XCTAssertNil(store.sftpErrorMessage)
        XCTAssertFalse(store.isSFTPLoading)
        XCTAssertEqual(store.history.first, "Downloaded files-prod:/var/log/app.log")
    }

    func testDownloadedSFTPFileCreatesShareableExportFile() throws {
        let download = SFTPDownloadedFile(
            id: UUID(uuidString: "90909090-9090-9090-9090-909090909090")!,
            name: " app.log ",
            remotePath: "/var/log/app.log",
            data: Data("hello".utf8)
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let exportURL = try download.makeShareExportFile(in: directory)

        XCTAssertEqual(download.shareExportFileName, "app.log")
        XCTAssertEqual(exportURL.lastPathComponent, "app.log")
        XCTAssertEqual(try Data(contentsOf: exportURL), Data("hello".utf8))
    }

    @MainActor
    func testUploadingSFTPFileWritesRemoteFileAndRefreshesCurrentPath() async throws {
        let hostID = UUID(uuidString: "F1F1F1F1-1111-2222-3333-F1F1F1F1F1F1")!
        let host = ShellHost(
            id: hostID,
            name: "files-prod",
            address: "files.example.com",
            username: "deploy",
            group: "Production",
            tags: ["sftp"],
            status: .idle
        )
        let credentialVault = InMemoryCredentialVault()
        try credentialVault.savePassword("file-secret", forHostID: hostID)
        let sftpClient = RecordingSFTPDirectoryListingClient(result: .success([]))
        let store = MobileShellStore(
            hosts: [host],
            credentialVault: credentialVault,
            sftpClient: sftpClient
        )
        let uploadData = Data([0x01, 0x02, 0x03])

        await store.openSFTP(for: host, path: "/tmp")
        await store.uploadSFTPFile(named: " build.tar ", data: uploadData)

        XCTAssertEqual(sftpClient.operations, [.upload(path: "/tmp/build.tar", data: uploadData)])
        XCTAssertEqual(sftpClient.paths, ["/tmp", "/tmp"])
        XCTAssertNil(store.sftpErrorMessage)
        XCTAssertFalse(store.isSFTPLoading)
        XCTAssertEqual(store.history.first, "Uploaded files-prod:/tmp/build.tar")
    }

    @MainActor
    func testFailedSFTPDownloadStoresErrorAndDoesNotRefresh() async throws {
        let hostID = UUID(uuidString: "A1A1A1A1-1111-2222-3333-A1A1A1A1A1A1")!
        let host = ShellHost(
            id: hostID,
            name: "files-prod",
            address: "files.example.com",
            username: "deploy",
            group: "Production",
            tags: ["sftp"],
            status: .idle
        )
        let credentialVault = InMemoryCredentialVault()
        try credentialVault.savePassword("file-secret", forHostID: hostID)
        let item = SFTPItem(
            id: UUID(uuidString: "09090909-0909-0909-0909-090909090909")!,
            name: "locked.log",
            kind: "text",
            size: "1 KB"
        )
        let sftpClient = RecordingSFTPDirectoryListingClient(
            result: .success([item]),
            downloadResult: .failure(RecordingSFTPError.unreachable)
        )
        let store = MobileShellStore(
            hosts: [host],
            credentialVault: credentialVault,
            sftpClient: sftpClient
        )

        await store.openSFTP(for: host, path: "/var/log")
        await store.downloadSFTPItem(item)

        XCTAssertNil(store.downloadedSFTPFile)
        XCTAssertEqual(sftpClient.operations, [.download(path: "/var/log/locked.log")])
        XCTAssertEqual(sftpClient.paths, ["/var/log"])
        XCTAssertFalse(store.isSFTPLoading)
        XCTAssertEqual(store.sftpErrorMessage, "SFTP error: SFTP fixture unreachable")
    }

    @MainActor
    func testFailedSFTPUploadStoresErrorAndDoesNotRefresh() async throws {
        let hostID = UUID(uuidString: "B1B1B1B1-1111-2222-3333-B1B1B1B1B1B1")!
        let host = ShellHost(
            id: hostID,
            name: "files-prod",
            address: "files.example.com",
            username: "deploy",
            group: "Production",
            tags: ["sftp"],
            status: .idle
        )
        let credentialVault = InMemoryCredentialVault()
        try credentialVault.savePassword("file-secret", forHostID: hostID)
        let sftpClient = RecordingSFTPDirectoryListingClient(
            result: .success([]),
            operationResult: .failure(RecordingSFTPError.unreachable)
        )
        let store = MobileShellStore(
            hosts: [host],
            credentialVault: credentialVault,
            sftpClient: sftpClient
        )

        await store.openSFTP(for: host, path: "/tmp")
        await store.uploadSFTPFile(named: "payload.bin", data: Data([0x01]))

        XCTAssertEqual(sftpClient.operations, [.upload(path: "/tmp/payload.bin", data: Data([0x01]))])
        XCTAssertEqual(sftpClient.paths, ["/tmp"])
        XCTAssertFalse(store.isSFTPLoading)
        XCTAssertEqual(store.sftpErrorMessage, "SFTP error: SFTP fixture unreachable")
    }
}
