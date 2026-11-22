import XCTest
@testable import MobileShell

final class HostTagNavigationTests: XCTestCase {
    func testHostTagsReturnsUniqueCaseInsensitiveSortedTags() {
        let store = MobileShellStore(hosts: [
            makeHost(name: "api", tags: ["ssh", "Prod", "api"]),
            makeHost(name: "worker", tags: ["SSH", "prod", "worker"]),
            makeHost(name: "empty", tags: ["", "  "])
        ])

        XCTAssertEqual(store.hostTags(), ["api", "Prod", "ssh", "worker"])
    }

    func testSelectingHostTagFiltersHostsByExactTagMembership() {
        let store = MobileShellStore(hosts: [
            makeHost(name: "api", tags: ["ssh", "prod", "api"]),
            makeHost(name: "cache", tags: ["ssh", "dev", "cache"]),
            makeHost(name: "db", tags: ["ssh", "prod", "db"])
        ])

        store.selectHostTag("prod")

        XCTAssertEqual(store.selectedHostTag, "prod")
        XCTAssertEqual(store.filteredHosts().map(\.name), ["api", "db"])
    }

    func testSearchCombinesWithSelectedHostTag() {
        let store = MobileShellStore(hosts: [
            makeHost(name: "api-prod", address: "10.0.0.10", tags: ["ssh", "prod", "api"]),
            makeHost(name: "worker-prod", address: "10.0.0.20", tags: ["ssh", "prod", "worker"]),
            makeHost(name: "api-dev", address: "10.0.0.30", tags: ["ssh", "dev", "api"])
        ])

        store.selectHostTag("prod")
        store.searchText = "api"

        XCTAssertEqual(store.filteredHosts().map(\.name), ["api-prod"])
    }

    func testClearingSelectedHostTagRestoresSearchOnlyFiltering() {
        let store = MobileShellStore(hosts: [
            makeHost(name: "api-prod", tags: ["ssh", "prod", "api"]),
            makeHost(name: "api-dev", tags: ["ssh", "dev", "api"])
        ])

        store.selectHostTag("prod")
        store.searchText = "api"
        XCTAssertEqual(store.filteredHosts().map(\.name), ["api-prod"])

        store.clearSelectedHostTag()

        XCTAssertNil(store.selectedHostTag)
        XCTAssertEqual(store.filteredHosts().map(\.name), ["api-prod", "api-dev"])
    }

    func testFilteredHostsRetainMoshProtocolMetadata() {
        let store = MobileShellStore(hosts: [
            makeHost(name: "ssh-admin", tags: ["ssh", "prod"]),
            ShellHost(
                id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
                name: "lab-mosh",
                address: "lab.example.com",
                username: "ops",
                group: "Lab",
                tags: ["mosh"],
                status: .idle,
                protocol: .mosh,
                moshConfiguration: .default
            ),
            makeHost(name: "db-backup", tags: ["ssh", "backup"])
        ])

        store.selectHostTag("mosh")

        let filteredHosts = store.filteredHosts()
        let host = try? XCTUnwrap(filteredHosts.first)

        XCTAssertEqual(filteredHosts.map(\.name), ["lab-mosh"])
        XCTAssertEqual(host?.protocol, .mosh)
    }

    func testHostProtocolBadgePresentationMatchesProtocol() {
        let moshHost = ShellHost(
            id: UUID(),
            name: "lab-mosh",
            address: "lab.example.com",
            username: "ops",
            group: "Lab",
            tags: ["mosh"],
            status: .idle,
            protocol: .mosh,
            moshConfiguration: .default
        )
        let sshHost = makeHost(name: "ssh-admin", tags: ["ssh", "prod"])

        XCTAssertEqual(HostProtocolBadgePresentation(host: moshHost)?.label, "MOSH")
        XCTAssertNil(HostProtocolBadgePresentation(host: sshHost))
    }

    private func makeHost(
        name: String,
        address: String = "example.com",
        tags: [String]
    ) -> ShellHost {
        ShellHost(
            id: UUID(),
            name: name,
            address: address,
            username: "deploy",
            group: "Production",
            tags: tags,
            status: .idle
        )
    }
}
