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
        self.bookmarks = Self.normalizedBookmarks(bookmarks)
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
        bookmarks = Self.normalizedBookmarks(
            try container.decodeIfPresent([SessionLogBookmark].self, forKey: .bookmarks) ?? []
        )
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

    func bookmark(for lineIndex: Int) -> SessionLogBookmark? {
        bookmarks.first(where: { $0.lineIndex == lineIndex })
    }

    func isBookmarked(lineIndex: Int) -> Bool {
        bookmark(for: lineIndex) != nil
    }

    private static func normalizedBookmarks(_ bookmarks: [SessionLogBookmark]) -> [SessionLogBookmark] {
        var newestBookmarkByLineIndex: [Int: SessionLogBookmark] = [:]

        for bookmark in bookmarks {
            if let current = newestBookmarkByLineIndex[bookmark.lineIndex] {
                if bookmark.createdAt >= current.createdAt {
                    newestBookmarkByLineIndex[bookmark.lineIndex] = bookmark
                }
            } else {
                newestBookmarkByLineIndex[bookmark.lineIndex] = bookmark
            }
        }

        return newestBookmarkByLineIndex.values.sorted {
            if $0.lineIndex != $1.lineIndex {
                return $0.lineIndex < $1.lineIndex
            }
            return $0.createdAt < $1.createdAt
        }
    }
}
