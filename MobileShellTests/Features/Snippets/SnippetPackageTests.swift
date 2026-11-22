import XCTest
@testable import MobileShell

final class SnippetPackageTests: XCTestCase {
    func testLegacySnippetDecodesIntoPersonalPackage() throws {
        let legacyJSON = """
        {
          "id" : "A1B2C3D4-1111-2222-3333-A1B2C3D4E5F6",
          "title" : "Disk Usage",
          "command" : "df -h"
        }
        """

        let snippet = try JSONDecoder().decode(ShellSnippet.self, from: Data(legacyJSON.utf8))

        XCTAssertEqual(snippet.packageName, ShellSnippet.defaultPackageName)
    }

    func testAddingSnippetStoresTrimmedPackageNameAndDefaultsBlankPackage() throws {
        let store = MobileShellStore()

        let deploy = try XCTUnwrap(store.addSnippet(
            title: "  Deploy API  ",
            command: "  make deploy-api  ",
            packageName: "  Ops  "
        ))
        let personal = try XCTUnwrap(store.addSnippet(
            title: "  Uptime  ",
            command: "  uptime  ",
            packageName: "   "
        ))

        XCTAssertEqual(deploy.title, "Deploy API")
        XCTAssertEqual(deploy.command, "make deploy-api")
        XCTAssertEqual(deploy.packageName, "Ops")
        XCTAssertEqual(personal.packageName, ShellSnippet.defaultPackageName)
        XCTAssertEqual(store.snippets, [deploy, personal])
    }

    func testUpdatingSnippetKeepsIDAndMovesPackage() throws {
        let snippet = ShellSnippet(
            id: UUID(uuidString: "B1B2C3D4-1111-2222-3333-B1B2C3D4E5F6")!,
            title: "Old",
            command: "uptime",
            packageName: "Ops"
        )
        let store = MobileShellStore(snippets: [snippet])

        let updated = try XCTUnwrap(store.updateSnippet(
            snippet,
            title: "  Tail Logs  ",
            command: "  tail -f /var/log/app.log  ",
            packageName: "  Debug  "
        ))

        XCTAssertEqual(updated.id, snippet.id)
        XCTAssertEqual(updated.title, "Tail Logs")
        XCTAssertEqual(updated.command, "tail -f /var/log/app.log")
        XCTAssertEqual(updated.packageName, "Debug")
        XCTAssertEqual(store.snippets, [updated])
    }

    func testSnippetPackagesGroupAndSortCaseInsensitively() throws {
        let snippets = [
            ShellSnippet(id: UUID(), title: "Restart API", command: "systemctl restart api", packageName: "Ops"),
            ShellSnippet(id: UUID(), title: "Deploy API", command: "make deploy-api", packageName: "ops"),
            ShellSnippet(id: UUID(), title: "Tail Logs", command: "tail -f /var/log/app.log", packageName: "Debug")
        ]
        let store = MobileShellStore(snippets: snippets)

        let packages = store.snippetPackages()

        XCTAssertEqual(packages.map(\.name), ["Debug", "Ops"])
        XCTAssertEqual(packages[0].snippets.map(\.title), ["Tail Logs"])
        XCTAssertEqual(packages[1].snippets.map(\.title), ["Deploy API", "Restart API"])
    }

    func testAutocompleteSnippetDetailIncludesPackageName() throws {
        let store = MobileShellStore(
            snippets: [
                ShellSnippet(id: UUID(), title: "Deploy API", command: "make deploy-api", packageName: "Ops")
            ]
        )

        let suggestion = try XCTUnwrap(store.commandSuggestions(for: "deploy").first)

        XCTAssertEqual(suggestion.source, .snippet)
        XCTAssertEqual(suggestion.detail, "Ops package")
    }
}
