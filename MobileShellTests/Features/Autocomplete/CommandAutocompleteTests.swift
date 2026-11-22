import XCTest
@testable import MobileShell

final class CommandAutocompleteTests: XCTestCase {
    func testSuggestionsPreferSnippetsThenHistoryThenBuiltins() {
        let store = MobileShellStore(
            snippets: [
                ShellSnippet(id: UUID(), title: "Disk Usage", command: "df -h"),
                ShellSnippet(id: UUID(), title: "Docker Logs", command: "docker logs api")
            ],
            history: ["df -h", "docker ps"]
        )

        let suggestions = store.commandSuggestions(for: "d")

        XCTAssertEqual(suggestions.map(\.command), ["df -h", "docker logs api", "docker ps", "du -sh *"])
        XCTAssertEqual(suggestions.first?.source, .snippet)
    }

    func testSuggestionsDeduplicateCommandsAndIgnoreBlankInput() {
        let store = MobileShellStore(
            snippets: [ShellSnippet(id: UUID(), title: "Disk Usage", command: "df -h")],
            history: ["df -h", " uptime "]
        )

        XCTAssertTrue(store.commandSuggestions(for: "   ").isEmpty)
        XCTAssertEqual(store.commandSuggestions(for: "df").map(\.command), ["df -h"])
    }

    func testApplyingSuggestionUpdatesSelectedTerminalDraft() throws {
        let host = ShellHost(
            id: UUID(),
            name: "api",
            address: "api.example.com",
            username: "deploy",
            group: "Production",
            tags: ["ssh"],
            status: .idle
        )
        let store = MobileShellStore(hosts: [host])
        store.connect(to: host)

        store.applyCommandSuggestion(CommandSuggestion(title: "Disk Usage", command: "df -h", source: .snippet))

        XCTAssertEqual(store.selectedTerminalSession?.commandDraft, "df -h")
        XCTAssertEqual(store.commandInput, "df -h")
    }

    func testUsingSnippetUpdatesActiveTerminalDraft() throws {
        let host = ShellHost(
            id: UUID(),
            name: "api",
            address: "api.example.com",
            username: "deploy",
            group: "Production",
            tags: ["ssh"],
            status: .idle
        )
        let snippet = ShellSnippet(id: UUID(), title: "Health", command: "systemctl status api")
        let store = MobileShellStore(hosts: [host], snippets: [snippet])
        store.connect(to: host)

        store.useSnippet(snippet)

        XCTAssertEqual(store.selectedTerminalSession?.commandDraft, "systemctl status api")
        XCTAssertEqual(store.selectedSection, .terminals)
    }
}
