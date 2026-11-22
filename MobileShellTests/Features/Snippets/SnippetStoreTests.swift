import XCTest
@testable import MobileShell

final class SnippetStoreTests: XCTestCase {
    func testAddingSnippetTrimsFieldsAndStoresHistory() throws {
        let store = MobileShellStore()

        let snippet = try XCTUnwrap(store.addSnippet(
            title: "  Service Health  ",
            command: "  systemctl status api.service  "
        ))

        XCTAssertEqual(snippet.title, "Service Health")
        XCTAssertEqual(snippet.command, "systemctl status api.service")
        XCTAssertEqual(store.snippets, [snippet])
        XCTAssertEqual(store.history.first, "Added snippet Service Health")
    }

    func testUpdatingSnippetKeepsIDTrimsFieldsAndStoresHistory() throws {
        let snippet = ShellSnippet(
            id: UUID(uuidString: "CECECECE-1111-2222-3333-CECECECECECE")!,
            title: "Old",
            command: "uptime"
        )
        let store = MobileShellStore(snippets: [snippet])

        let updated = try XCTUnwrap(store.updateSnippet(
            snippet,
            title: "  Recent Logs  ",
            command: "  tail -n 100 /var/log/app.log  "
        ))

        XCTAssertEqual(updated.id, snippet.id)
        XCTAssertEqual(updated.title, "Recent Logs")
        XCTAssertEqual(updated.command, "tail -n 100 /var/log/app.log")
        XCTAssertEqual(store.snippets, [updated])
        XCTAssertEqual(store.history.first, "Updated snippet Recent Logs")
    }

    func testDeletingSnippetRemovesItAndStoresHistory() {
        let snippet = ShellSnippet(
            id: UUID(uuidString: "CFCFCFCF-1111-2222-3333-CFCFCFCFCFCF")!,
            title: "Disk Usage",
            command: "df -h"
        )
        let store = MobileShellStore(snippets: [snippet])

        store.deleteSnippet(snippet)

        XCTAssertTrue(store.snippets.isEmpty)
        XCTAssertEqual(store.history.first, "Deleted snippet Disk Usage")
    }
}
