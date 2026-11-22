# Log Bookmarks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add personal Termius-style log bookmarks so a user can mark important lines inside local session logs and return to them later.

**Architecture:** Extend `SessionLog` with nested bookmark data, add focused bookmark mutation APIs on `MobileShellStore`, and keep the UI logic inside `MobileShell/Features/Logs/` by introducing a log detail view plus a lightweight bookmark editor sheet. Persist bookmarks inside existing `sessionLogs` snapshots with backward-compatible decoding so legacy logs still load cleanly.

**Tech Stack:** Swift 6, SwiftUI, Observation, XCTest, existing JSON snapshot persistence.

---

### Task 1: Bookmark Model And Backward-Compatible Decoding

**Files:**
- Create: `MobileShellTests/Features/Logs/SessionLogBookmarkTests.swift`
- Modify: `MobileShell/Features/Logs/SessionLog.swift`
- Modify: `MobileShell.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import MobileShell

final class SessionLogBookmarkTests: XCTestCase {
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
        XCTAssertEqual(store.sessionLogs.first?.bookmarks.map(\\.title), ["Restart API"])
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/SessionLogBookmarkTests`

Expected: FAIL because `SessionLogBookmark`, `bookmarks`, `addSessionLogBookmark`, and `deleteSessionLogBookmark` do not exist yet.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

struct SessionLogBookmark: Identifiable, Equatable, Codable {
    let id: UUID
    var lineIndex: Int
    var title: String
    var linePreview: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        lineIndex: Int,
        title: String,
        linePreview: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.lineIndex = lineIndex
        self.title = title
        self.linePreview = linePreview
        self.createdAt = createdAt
    }
}

struct SessionLog: Identifiable, Equatable, Codable {
    let id: UUID
    var hostID: ShellHost.ID
    var hostName: String
    var startedAt: Date
    var endedAt: Date?
    var lines: [String]
    var bookmarks: [SessionLogBookmark]

    init(
        id: UUID = UUID(),
        hostID: ShellHost.ID,
        hostName: String,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        lines: [String] = [],
        bookmarks: [SessionLogBookmark] = []
    ) {
        self.id = id
        self.hostID = hostID
        self.hostName = hostName
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.lines = lines
        self.bookmarks = bookmarks
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case hostID
        case hostName
        case startedAt
        case endedAt
        case lines
        case bookmarks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        hostID = try container.decode(ShellHost.ID.self, forKey: .hostID)
        hostName = try container.decode(String.self, forKey: .hostName)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
        lines = try container.decodeIfPresent([String].self, forKey: .lines) ?? []
        bookmarks = try container.decodeIfPresent([SessionLogBookmark].self, forKey: .bookmarks) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(hostID, forKey: .hostID)
        try container.encode(hostName, forKey: .hostName)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encodeIfPresent(endedAt, forKey: .endedAt)
        try container.encode(lines, forKey: .lines)
        try container.encode(bookmarks, forKey: .bookmarks)
    }

    var lineCount: Int {
        lines.count
    }

    var preview: String {
        lines.suffix(3).joined(separator: "\n")
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/SessionLogBookmarkTests/testLegacySessionLogDecodesWithoutBookmarks`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add MobileShell/Features/Logs/SessionLog.swift MobileShellTests/Features/Logs/SessionLogBookmarkTests.swift MobileShell.xcodeproj/project.pbxproj
git commit -m "feat: add session log bookmark model"
```

### Task 2: Store Bookmark Mutations And Persistence

**Files:**
- Modify: `MobileShell/Models.swift`
- Modify: `MobileShellTests/Features/Logs/SessionLogBookmarkTests.swift`

- [ ] **Step 1: Extend the failing tests for store behavior**

Add these tests to `MobileShellTests/Features/Logs/SessionLogBookmarkTests.swift`:

```swift
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

    XCTAssertEqual(store.sessionLogs.first?.bookmarks.map(\\.lineIndex), [0, 2])
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
```

- [ ] **Step 2: Run the targeted test suite and verify RED**

Run: `xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/SessionLogBookmarkTests`

Expected: FAIL because the store bookmark APIs and history behavior are still missing.

- [ ] **Step 3: Write minimal implementation**

Add these methods to `MobileShellStore` in `MobileShell/Models.swift`:

```swift
func addSessionLogBookmark(
    to logID: SessionLog.ID,
    lineIndex: Int,
    title: String
) -> SessionLogBookmark? {
    guard let logIndex = sessionLogs.firstIndex(where: { $0.id == logID }),
          sessionLogs[logIndex].lines.indices.contains(lineIndex)
    else {
        return nil
    }

    let trimmedLine = sessionLogs[logIndex].lines[lineIndex]
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let resolvedTitle = trimmedTitle.isEmpty
        ? String(trimmedLine.prefix(80))
        : trimmedTitle
    let bookmark = SessionLogBookmark(
        lineIndex: lineIndex,
        title: resolvedTitle,
        linePreview: trimmedLine
    )

    sessionLogs[logIndex].bookmarks.append(bookmark)
    sessionLogs[logIndex].bookmarks.sort { lhs, rhs in
        if lhs.lineIndex == rhs.lineIndex {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.lineIndex < rhs.lineIndex
    }
    history.insert("Bookmarked log line on \(sessionLogs[logIndex].hostName)", at: 0)
    try? persistSnapshot()
    return bookmark
}

func deleteSessionLogBookmark(
    _ bookmarkID: SessionLogBookmark.ID,
    from logID: SessionLog.ID
) {
    guard let logIndex = sessionLogs.firstIndex(where: { $0.id == logID }),
          let bookmarkIndex = sessionLogs[logIndex].bookmarks.firstIndex(where: { $0.id == bookmarkID })
    else {
        return
    }

    let hostName = sessionLogs[logIndex].hostName
    sessionLogs[logIndex].bookmarks.remove(at: bookmarkIndex)
    history.insert("Removed log bookmark from \(hostName)", at: 0)
    try? persistSnapshot()
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/SessionLogBookmarkTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add MobileShell/Models.swift MobileShellTests/Features/Logs/SessionLogBookmarkTests.swift
git commit -m "feat: add session log bookmark store actions"
```

### Task 3: Log Detail View And Bookmark Editor

**Files:**
- Create: `MobileShell/Features/Logs/SessionLogDetailView.swift`
- Modify: `MobileShell/Features/Logs/SessionLog.swift`
- Modify: `MobileShell/Features/Logs/SessionLogsView.swift`
- Modify: `MobileShell.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write the failing UI behavior test**

Add this test to `MobileShellTests/Features/Logs/SessionLogBookmarkTests.swift`:

```swift
func testSessionLogBookmarkSummaryUsesSingularAndPluralLabels() {
    let bookmark = SessionLogBookmark(
        id: UUID(uuidString: "15151515-1515-1515-1515-151515151515")!,
        lineIndex: 1,
        title: "Restart API",
        linePreview: "sudo systemctl restart api.service"
    )
    let log = SessionLog(
        id: UUID(uuidString: "16161616-1616-1616-1616-161616161616")!,
        hostID: UUID(uuidString: "17171717-1717-1717-1717-171717171717")!,
        hostName: "api-prod",
        lines: ["connected", "sudo systemctl restart api.service"],
        bookmarks: [bookmark]
    )

    XCTAssertEqual(log.bookmarkSummary, "1 bookmark")
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
```

- [ ] **Step 2: Run the targeted test and verify RED**

Run: `xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/SessionLogBookmarkTests/testSessionLogBookmarkCountIsShownInLogsListSummary`

Expected: FAIL because the UI summary does not mention bookmarks and no detail view exists yet.

- [ ] **Step 3: Write minimal implementation**

Create `MobileShell/Features/Logs/SessionLogDetailView.swift` with this structure:

```swift
import SwiftUI

struct SessionLogDetailView: View {
    @Bindable var store: MobileShellStore
    let logID: SessionLog.ID

    @Environment(\\.dismiss) private var dismiss
    @State private var pendingBookmarkLineIndex: Int?
    @State private var bookmarkTitle = ""

    private var log: SessionLog? {
        store.sessionLogs.first { $0.id == logID }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let log {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            SessionLogBookmarkSummary(log: log)

                            ForEach(Array(log.lines.enumerated()), id: \\.offset) { index, line in
                                SessionLogLineRow(
                                    lineNumber: index + 1,
                                    line: line,
                                    isBookmarked: log.bookmarks.contains { $0.lineIndex == index },
                                    onBookmark: {
                                        pendingBookmarkLineIndex = index
                                        bookmarkTitle = line.trimmingCharacters(in: .whitespacesAndNewlines)
                                    }
                                )
                            }
                        }
                        .padding(18)
                    }
                } else {
                    ContentUnavailableView("Log Missing", systemImage: "doc.text.magnifyingglass")
                }
            }
            .navigationTitle(log?.hostName ?? "Session Log")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(
                isPresented: Binding(
                    get: { pendingBookmarkLineIndex != nil },
                    set: { isPresented in
                        if !isPresented {
                            pendingBookmarkLineIndex = nil
                            bookmarkTitle = ""
                        }
                    }
                )
            ) {
                NavigationStack {
                    Form {
                        Section("Bookmark") {
                            TextField("Title", text: $bookmarkTitle)
                        }
                    }
                    .navigationTitle("Add Bookmark")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                pendingBookmarkLineIndex = nil
                                bookmarkTitle = ""
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                if let lineIndex = pendingBookmarkLineIndex {
                                    _ = store.addSessionLogBookmark(
                                        to: logID,
                                        lineIndex: lineIndex,
                                        title: bookmarkTitle
                                    )
                                }
                                pendingBookmarkLineIndex = nil
                                bookmarkTitle = ""
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct SessionLogBookmarkSummary: View {
    let log: SessionLog

    var body: some View {
        if log.bookmarks.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Bookmarks")
                    .font(.headline)
                ForEach(log.bookmarks) { bookmark in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "bookmark.fill")
                            .foregroundStyle(ShellColor.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(bookmark.title)
                                .font(.subheadline.weight(.semibold))
                            Text("Line \\(bookmark.lineIndex + 1) · \\(bookmark.linePreview)")
                                .font(.caption)
                                .foregroundStyle(ShellColor.secondaryText)
                        }
                        Spacer()
                    }
                }
            }
            .padding(14)
            .background(ShellColor.deepPanel)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

private struct SessionLogLineRow: View {
    let lineNumber: Int
    let line: String
    let isBookmarked: Bool
    let onBookmark: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\\(lineNumber)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(ShellColor.secondaryText)
                .frame(width: 32, alignment: .trailing)

            Text(line)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(ShellColor.terminalText)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onBookmark) {
                Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                    .foregroundStyle(isBookmarked ? ShellColor.accent : ShellColor.secondaryText)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(ShellColor.terminal)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
```

Add this computed property to `MobileShell/Features/Logs/SessionLog.swift`:

```swift
var bookmarkSummary: String {
    switch bookmarks.count {
    case 0:
        return "No bookmarks"
    case 1:
        return "1 bookmark"
    default:
        return "\(bookmarks.count) bookmarks"
    }
}
```

Then update `SessionLogCard.summary` in `MobileShell/Features/Logs/SessionLogsView.swift`:

```swift
private var summary: String {
    return "\(log.lineCount) lines · \(log.bookmarkSummary) · started \(log.startedAt.formatted(date: .abbreviated, time: .shortened))"
}
```

- [ ] **Step 4: Run the targeted test and verify it passes**

Run: `xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/SessionLogBookmarkTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add MobileShell/Features/Logs/SessionLog.swift MobileShell/Features/Logs/SessionLogDetailView.swift MobileShell/Features/Logs/SessionLogsView.swift MobileShellTests/Features/Logs/SessionLogBookmarkTests.swift MobileShell.xcodeproj/project.pbxproj
git commit -m "feat: add session log bookmark detail view"
```

### Task 4: Logs List Wiring And Full Verification

**Files:**
- Modify: `MobileShell/Features/Logs/SessionLogsView.swift`
- Modify: `docs/product/termius-personal/07-current-state-gap-analysis.md`

- [ ] **Step 1: Finish logs list wiring**

Update `MobileShell/Features/Logs/SessionLogsView.swift` so each card opens the detail screen instead of being static:

```swift
struct SessionLogsView: View {
    @Bindable var store: MobileShellStore
    @State private var selectedLogID: SessionLog.ID?

    private var logs: [SessionLog] {
        store.sessionLogs.sorted { lhs, rhs in
            lhs.startedAt > rhs.startedAt
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Session Logs")
                        .font(.title3.weight(.bold))
                    Text("Local terminal activity captured automatically for each host.")
                        .font(.caption)
                        .foregroundStyle(ShellColor.secondaryText)
                }

                if logs.isEmpty {
                    SessionLogsEmptyState()
                } else {
                    ForEach(logs) { log in
                        Button {
                            selectedLogID = log.id
                        } label: {
                            SessionLogCard(log: log)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(18)
        }
        .sheet(
            isPresented: Binding(
                get: { selectedLogID != nil },
                set: { isPresented in
                    if !isPresented {
                        selectedLogID = nil
                    }
                }
            )
        ) {
            if let selectedLogID {
                SessionLogDetailView(store: store, logID: selectedLogID)
            }
        }
    }
}
```

Then update `docs/product/termius-personal/07-current-state-gap-analysis.md` so `B5: Logs 增强` moves from `部分具备` to `已具备` once implementation is done.

- [ ] **Step 2: Run full verification**

Run: `xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'`

Run: `xcodebuild build -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'`

Expected: both commands PASS.

- [ ] **Step 3: Commit**

```bash
git add MobileShell/Features/Logs/SessionLogsView.swift docs/product/termius-personal/07-current-state-gap-analysis.md
git commit -m "feat: add session log bookmarks"
```
