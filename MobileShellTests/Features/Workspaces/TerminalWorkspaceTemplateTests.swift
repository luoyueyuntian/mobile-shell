import XCTest
@testable import MobileShell

final class TerminalWorkspaceTemplateTests: XCTestCase {
    func testSavingSelectedWorkspaceAsTemplateStoresVisibleHostsAndBroadcastMode() throws {
        let firstHost = makeHost(name: "api", address: "api.example.com")
        let secondHost = makeHost(name: "db", address: "db.example.com")
        let outsideHost = makeHost(name: "cache", address: "cache.example.com")
        let store = MobileShellStore(hosts: [firstHost, secondHost, outsideHost])
        let workspace = try XCTUnwrap(store.createTerminalWorkspace(name: "Production"))

        store.connect(to: firstHost)
        store.connect(to: secondHost)
        store.setBroadcastEnabled(true, for: workspace.id)
        store.selectTerminalWorkspace(nil)
        store.connect(to: outsideHost)
        store.selectTerminalWorkspace(workspace.id)

        let template = try XCTUnwrap(store.saveSelectedWorkspaceAsTemplate(name: "  Production Daily  "))

        XCTAssertEqual(template.name, "Production Daily")
        XCTAssertEqual(template.hostIDs, [firstHost.id, secondHost.id])
        XCTAssertTrue(template.isBroadcastEnabled)
        XCTAssertEqual(store.terminalWorkspaceTemplates, [template])
        XCTAssertEqual(store.history.first, "Saved workspace template Production Daily")
    }

    func testSavingTemplateWithoutSelectedWorkspaceReturnsNil() {
        let host = makeHost(name: "api", address: "api.example.com")
        let store = MobileShellStore(hosts: [host])

        store.connect(to: host)

        XCTAssertNil(store.saveSelectedWorkspaceAsTemplate(name: "All Terminals"))
        XCTAssertTrue(store.terminalWorkspaceTemplates.isEmpty)
    }

    func testSavingEmptySelectedWorkspaceReturnsNil() throws {
        let store = MobileShellStore()

        _ = try XCTUnwrap(store.createTerminalWorkspace(name: "Incident"))

        XCTAssertNil(store.saveSelectedWorkspaceAsTemplate(name: "Empty Incident"))
        XCTAssertTrue(store.terminalWorkspaceTemplates.isEmpty)
    }

    func testOpeningTemplateCreatesWorkspaceAndConnectsTemplateHosts() throws {
        let firstHost = makeHost(name: "api", address: "api.example.com")
        let secondHost = makeHost(name: "db", address: "db.example.com")
        let missingHostID = UUID(uuidString: "99999999-1111-2222-3333-999999999999")!
        let template = TerminalWorkspaceTemplate(
            id: UUID(uuidString: "91919191-1111-2222-3333-919191919191")!,
            name: "Production",
            hostIDs: [firstHost.id, missingHostID, secondHost.id],
            isBroadcastEnabled: true
        )
        let store = MobileShellStore(
            hosts: [firstHost, secondHost],
            terminalWorkspaceTemplates: [template]
        )

        let workspace = try XCTUnwrap(store.openWorkspaceTemplate(template))

        XCTAssertEqual(store.selectedWorkspaceID, workspace.id)
        XCTAssertEqual(store.selectedTerminalWorkspace?.name, "Production")
        XCTAssertEqual(store.selectedTerminalWorkspace?.isBroadcastEnabled, true)
        XCTAssertEqual(store.visibleTerminalSessions().map(\.hostName), ["api", "db"])
        XCTAssertEqual(store.history.first, "Opened workspace template Production")
    }

    func testDeletingWorkspaceTemplateRemovesAndPersistsIt() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repository = JSONHostRepository(fileURL: tempDirectory.appendingPathComponent("hosts.json"))
        let template = TerminalWorkspaceTemplate(
            id: UUID(uuidString: "92929292-1111-2222-3333-929292929292")!,
            name: "Production",
            hostIDs: [],
            isBroadcastEnabled: false
        )
        try repository.save(HostPersistenceSnapshot(terminalWorkspaceTemplates: [template]))
        let store = try MobileShellStore(repository: repository, credentialVault: InMemoryCredentialVault())

        store.deleteWorkspaceTemplate(template)

        XCTAssertTrue(store.terminalWorkspaceTemplates.isEmpty)
        XCTAssertTrue(try repository.load().terminalWorkspaceTemplates.isEmpty)
    }

    func testWorkspaceTemplatePersistenceRoundTrips() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repository = JSONHostRepository(fileURL: tempDirectory.appendingPathComponent("hosts.json"))
        let template = TerminalWorkspaceTemplate(
            id: UUID(uuidString: "93939393-1111-2222-3333-939393939393")!,
            name: "Production",
            hostIDs: [UUID(uuidString: "94949494-1111-2222-3333-949494949494")!],
            isBroadcastEnabled: true
        )

        try repository.save(HostPersistenceSnapshot(terminalWorkspaceTemplates: [template]))
        let reloaded = try repository.load()
        let store = try MobileShellStore(repository: repository, credentialVault: InMemoryCredentialVault())

        XCTAssertEqual(reloaded.terminalWorkspaceTemplates, [template])
        XCTAssertEqual(store.terminalWorkspaceTemplates, [template])
    }

    private func makeHost(name: String, address: String) -> ShellHost {
        ShellHost(
            id: UUID(),
            name: name,
            address: address,
            username: "deploy",
            group: "Production",
            tags: ["ssh"],
            status: .idle
        )
    }
}
