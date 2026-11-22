import XCTest
@testable import MobileShell

final class SessionLogBookmarkTests: XCTestCase {
    func testSessionLogLinePresentationReflectsBookmarkState() {
        let bookmark = SessionLogBookmark(
            id: UUID(uuidString: "24242424-2424-2424-2424-242424242424")!,
            lineIndex: 1,
            title: "Restart API",
            linePreview: "sudo systemctl restart api.service"
        )
        let log = SessionLog(
            id: UUID(uuidString: "25252525-2525-2525-2525-252525252525")!,
            hostID: UUID(uuidString: "26262626-2626-2626-2626-262626262626")!,
            hostName: "api-prod",
            lines: ["connected", "sudo systemctl restart api.service"],
            bookmarks: [bookmark]
        )

        let bookmarkedPresentation = SessionLogLinePresentation(
            log: log,
            lineIndex: 1,
            line: "sudo systemctl restart api.service"
        )
        let plainPresentation = SessionLogLinePresentation(
            log: log,
            lineIndex: 0,
            line: "connected"
        )

        XCTAssertTrue(bookmarkedPresentation.isBookmarked)
        XCTAssertEqual(bookmarkedPresentation.bookmarkIconName, "bookmark.fill")
        XCTAssertEqual(bookmarkedPresentation.bookmarkTitle, "Restart API")
        XCTAssertEqual(bookmarkedPresentation.accessibilityLabel, "Remove bookmark from line 2")

        XCTAssertFalse(plainPresentation.isBookmarked)
        XCTAssertEqual(plainPresentation.bookmarkIconName, "bookmark")
        XCTAssertNil(plainPresentation.bookmarkTitle)
        XCTAssertEqual(plainPresentation.accessibilityLabel, "Bookmark line 1")
    }

    func testSessionLogLinePresentationChoosesRemoveActionForBookmarkedLine() {
        let bookmark = SessionLogBookmark(
            id: UUID(uuidString: "34343434-3434-3434-3434-343434343434")!,
            lineIndex: 0,
            title: "Connected",
            linePreview: "connected"
        )
        let log = SessionLog(
            id: UUID(uuidString: "35353535-3535-3535-3535-353535353535")!,
            hostID: UUID(uuidString: "36363636-3636-3636-3636-363636363636")!,
            hostName: "api-prod",
            lines: ["connected"],
            bookmarks: [bookmark]
        )

        let bookmarkedPresentation = SessionLogLinePresentation(
            log: log,
            lineIndex: 0,
            line: "connected"
        )
        let plainPresentation = SessionLogLinePresentation(
            log: SessionLog(
                id: UUID(uuidString: "37373737-3737-3737-3737-373737373737")!,
                hostID: UUID(uuidString: "38383838-3838-3838-3838-383838383838")!,
                hostName: "api-prod",
                lines: ["connected"]
            ),
            lineIndex: 0,
            line: "connected"
        )

        XCTAssertEqual(bookmarkedPresentation.bookmarkAction, .remove)
        XCTAssertEqual(plainPresentation.bookmarkAction, .add)
    }

    func testSessionLogBookmarkLookupMatchesLineIndex() {
        let bookmark = SessionLogBookmark(
            id: UUID(uuidString: "21212121-2121-2121-2121-212121212121")!,
            lineIndex: 2,
            title: "Restart API",
            linePreview: "sudo systemctl restart api.service"
        )
        let log = SessionLog(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            hostID: UUID(uuidString: "23232323-2323-2323-2323-232323232323")!,
            hostName: "api-prod",
            lines: ["connected", "uptime", "sudo systemctl restart api.service"],
            bookmarks: [bookmark]
        )

        XCTAssertTrue(log.isBookmarked(lineIndex: 2))
        XCTAssertEqual(log.bookmark(for: 2), bookmark)
        XCTAssertFalse(log.isBookmarked(lineIndex: 0))
        XCTAssertNil(log.bookmark(for: 0))
    }

    func testSessionLogBookmarkSummaryUsesSingularAndPluralLabels() {
        let firstBookmark = SessionLogBookmark(
            id: UUID(uuidString: "15151515-1515-1515-1515-151515151515")!,
            lineIndex: 1,
            title: "Restart API",
            linePreview: "sudo systemctl restart api.service"
        )
        let secondBookmark = SessionLogBookmark(
            id: UUID(uuidString: "18181818-1818-1818-1818-181818181818")!,
            lineIndex: 0,
            title: "Connected",
            linePreview: "connected"
        )
        let log = SessionLog(
            id: UUID(uuidString: "16161616-1616-1616-1616-161616161616")!,
            hostID: UUID(uuidString: "17171717-1717-1717-1717-171717171717")!,
            hostName: "api-prod",
            lines: ["connected", "sudo systemctl restart api.service"],
            bookmarks: [firstBookmark]
        )

        XCTAssertEqual(log.bookmarkSummary, "1 bookmark")
        XCTAssertEqual(
            SessionLog(
                id: UUID(uuidString: "19191919-1919-1919-1919-191919191919")!,
                hostID: UUID(uuidString: "20202020-2020-2020-2020-202020202020")!,
                hostName: "api-prod",
                lines: ["connected", "sudo systemctl restart api.service"],
                bookmarks: [firstBookmark, secondBookmark]
            ).bookmarkSummary,
            "2 bookmarks"
        )
        XCTAssertEqual(
            SessionLog(
                id: UUID(uuidString: "16161616-1616-1616-1616-161616161616")!,
                hostID: UUID(uuidString: "17171717-1717-1717-1717-171717171717")!,
                hostName: "web-prod",
                lines: ["connected"],
                bookmarks: []
            ).bookmarkSummary,
            "No bookmarks"
        )
    }

    func testLegacySessionLogDecodesWithoutBookmarks() throws {
        let data = Data("""
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "hostID": "22222222-2222-2222-2222-222222222222",
          "hostName": "api-prod",
          "startedAt": 0,
          "endedAt": null,
          "lines": ["connected", "$ uptime"]
        }
        """.utf8)

        let log = try JSONDecoder().decode(SessionLog.self, from: data)

        XCTAssertEqual(log.bookmarks, [])
    }

    func testLegacySessionLogDecodingKeepsNewestBookmarkPerLine() throws {
        let data = Data("""
        {
          "id": "44444444-4444-4444-4444-444444444444",
          "hostID": "55555555-5555-5555-5555-555555555555",
          "hostName": "api-prod",
          "startedAt": 0,
          "endedAt": null,
          "lines": ["connected", "sudo systemctl restart api.service"],
          "bookmarks": [
            {
              "id": "66666666-6666-6666-6666-666666666666",
              "lineIndex": 1,
              "title": "Older restart",
              "linePreview": "sudo systemctl restart api.service",
              "createdAt": 100
            },
            {
              "id": "77777777-7777-7777-7777-777777777777",
              "lineIndex": 1,
              "title": "Newer restart",
              "linePreview": "sudo systemctl restart api.service",
              "createdAt": 200
            },
            {
              "id": "88888888-8888-8888-8888-888888888888",
              "lineIndex": 0,
              "title": "Connected",
              "linePreview": "connected",
              "createdAt": 150
            }
          ]
        }
        """.utf8)

        let log = try JSONDecoder().decode(SessionLog.self, from: data)

        XCTAssertEqual(log.bookmarks.count, 2)
        XCTAssertEqual(log.bookmarks.map(\.lineIndex), [0, 1])
        XCTAssertEqual(log.bookmark(for: 1)?.title, "Newer restart")
        XCTAssertEqual(log.bookmark(for: 1)?.createdAt, Date(timeIntervalSinceReferenceDate: 200))
    }

    func testAddingBookmarkStoresTrimmedTitleLineIndexAndPreview() {
        let log = SessionLog(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            hostID: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            hostName: "api-prod",
            startedAt: Date(timeIntervalSinceReferenceDate: 100),
            lines: ["connected", "sudo systemctl restart api.service"]
        )
        let store = MobileShellStore(sessionLogs: [log])

        let bookmark = store.addSessionLogBookmark(
            to: log.id,
            lineIndex: 1,
            title: "  Restart API  "
        )

        XCTAssertEqual(bookmark?.title, "Restart API")
        XCTAssertEqual(bookmark?.lineIndex, 1)
        XCTAssertEqual(bookmark?.linePreview, "sudo systemctl restart api.service")
        XCTAssertEqual(store.sessionLogs.first?.bookmarks.map(\.title), ["Restart API"])
    }

    func testAddingBookmarkFallsBackToLinePreviewWhenTitleBlank() {
        let log = SessionLog(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            hostID: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
            hostName: "db-prod",
            lines: ["", "tail -n 120 /var/log/nginx/error.log"]
        )
        let store = MobileShellStore(sessionLogs: [log])

        let bookmark = store.addSessionLogBookmark(
            to: log.id,
            lineIndex: 1,
            title: "   "
        )

        XCTAssertEqual(bookmark?.title, "tail -n 120 /var/log/nginx/error.log")
        XCTAssertEqual(store.sessionLogs.first?.bookmarks.first?.title, "tail -n 120 /var/log/nginx/error.log")
    }

    func testBookmarksSortByLineIndexAfterMultipleInserts() {
        let log = SessionLog(
            id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
            hostID: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
            hostName: "ops-prod",
            lines: ["line 0", "line 1", "line 2"]
        )
        let store = MobileShellStore(sessionLogs: [log])

        _ = store.addSessionLogBookmark(to: log.id, lineIndex: 2, title: "Third")
        _ = store.addSessionLogBookmark(to: log.id, lineIndex: 0, title: "First")

        XCTAssertEqual(store.sessionLogs.first?.bookmarks.map(\.lineIndex), [0, 2])
    }

    func testAddingBookmarkToSameLineReplacesExistingBookmark() {
        let log = SessionLog(
            id: UUID(uuidString: "15151515-1515-1515-1515-151515151515")!,
            hostID: UUID(uuidString: "16161616-1616-1616-1616-161616161616")!,
            hostName: "ops-prod",
            lines: ["line 0", "line 1"]
        )
        let store = MobileShellStore(sessionLogs: [log])

        _ = store.addSessionLogBookmark(
            to: log.id,
            lineIndex: 1,
            title: "Later",
            createdAt: Date(timeIntervalSinceReferenceDate: 200)
        )
        let secondBookmark = store.addSessionLogBookmark(
            to: log.id,
            lineIndex: 1,
            title: "Earlier",
            createdAt: Date(timeIntervalSinceReferenceDate: 100)
        )

        XCTAssertEqual(store.sessionLogs.first?.bookmarks.count, 1)
        XCTAssertEqual(store.sessionLogs.first?.bookmarks.first?.title, "Earlier")
        XCTAssertEqual(store.sessionLogs.first?.bookmarks.first?.createdAt, Date(timeIntervalSinceReferenceDate: 100))
        XCTAssertEqual(secondBookmark, store.sessionLogs.first?.bookmarks.first)
    }

    func testAddingBookmarkRecordsHistoryEntry() {
        let log = SessionLog(
            id: UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!,
            hostID: UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!,
            hostName: "api-prod",
            lines: ["connected", "deploy finished"]
        )
        let store = MobileShellStore(sessionLogs: [log])

        _ = store.addSessionLogBookmark(to: log.id, lineIndex: 1, title: "Deploy finished")

        XCTAssertEqual(store.history.first, "Bookmarked log line on api-prod")
    }

    func testDeletingBookmarkRecordsHistoryEntry() {
        let bookmark = SessionLogBookmark(
            id: UUID(uuidString: "12121212-1212-1212-1212-121212121212")!,
            lineIndex: 0,
            title: "Connected",
            linePreview: "connected"
        )
        let log = SessionLog(
            id: UUID(uuidString: "13131313-1313-1313-1313-131313131313")!,
            hostID: UUID(uuidString: "14141414-1414-1414-1414-141414141414")!,
            hostName: "edge-prod",
            lines: ["connected"],
            bookmarks: [bookmark]
        )
        let store = MobileShellStore(sessionLogs: [log])

        store.deleteSessionLogBookmark(bookmark.id, from: log.id)

        XCTAssertEqual(store.history.first, "Removed log bookmark from edge-prod")
    }

    func testAddingBookmarkPersistsAndReloadsFromRepository() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = JSONHostRepository(fileURL: directory.appendingPathComponent("vault.json"))
        let log = SessionLog(
            id: UUID(uuidString: "ABABABAB-ABAB-ABAB-ABAB-ABABABABABAB")!,
            hostID: UUID(uuidString: "CDCDCDCD-CDCD-CDCD-CDCD-CDCDCDCDCDCD")!,
            hostName: "api-prod",
            lines: ["connected", "sudo systemctl restart api.service"]
        )
        try repository.save(HostPersistenceSnapshot(sessionLogs: [log]))

        let store = try MobileShellStore(
            repository: repository,
            credentialVault: InMemoryCredentialVault()
        )

        let bookmark = try XCTUnwrap(store.addSessionLogBookmark(
            to: log.id,
            lineIndex: 1,
            title: "Restart API"
        ))

        let reloaded = try repository.load()
        XCTAssertEqual(reloaded.sessionLogs.first?.bookmarks, [bookmark])
    }

    func testAddingBookmarkRejectsOutOfBoundsLineIndex() {
        let log = SessionLog(
            id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
            hostID: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!,
            hostName: "web-prod",
            lines: ["one line"]
        )
        let store = MobileShellStore(sessionLogs: [log])

        let bookmark = store.addSessionLogBookmark(
            to: log.id,
            lineIndex: 4,
            title: "Impossible"
        )

        XCTAssertNil(bookmark)
        XCTAssertTrue(store.sessionLogs.first?.bookmarks.isEmpty == true)
    }

    func testDeletingBookmarkRemovesItAndPersistsCleanup() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = JSONHostRepository(fileURL: directory.appendingPathComponent("vault.json"))
        let bookmark = SessionLogBookmark(
            id: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!,
            lineIndex: 1,
            title: "Restart API",
            linePreview: "sudo systemctl restart api.service",
            createdAt: Date(timeIntervalSinceReferenceDate: 200)
        )
        let log = SessionLog(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            hostID: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            hostName: "api-prod",
            startedAt: Date(timeIntervalSinceReferenceDate: 100),
            lines: ["connected", "sudo systemctl restart api.service"],
            bookmarks: [bookmark]
        )
        try repository.save(HostPersistenceSnapshot(sessionLogs: [log]))

        let store = try MobileShellStore(
            repository: repository,
            credentialVault: InMemoryCredentialVault()
        )

        store.deleteSessionLogBookmark(bookmark.id, from: log.id)

        XCTAssertTrue(store.sessionLogs.first?.bookmarks.isEmpty == true)
        XCTAssertTrue(try repository.load().sessionLogs.first?.bookmarks.isEmpty == true)
    }
}
