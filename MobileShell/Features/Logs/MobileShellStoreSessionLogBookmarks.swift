import Foundation

extension MobileShellStore {
    @discardableResult
    func addSessionLogBookmark(
        to logID: SessionLog.ID,
        lineIndex: Int,
        title: String,
        createdAt: Date = Date()
    ) -> SessionLogBookmark? {
        guard let log = sessionLogs.first(where: { $0.id == logID }),
              log.lines.indices.contains(lineIndex) else {
            return nil
        }

        let linePreview = log.lines[lineIndex]
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let bookmark = SessionLogBookmark(
            lineIndex: lineIndex,
            title: trimmedTitle.isEmpty ? linePreview : trimmedTitle,
            linePreview: linePreview,
            createdAt: createdAt
        )

        let didUpdate = updateSessionLog(withID: logID, historyEntry: "Bookmarked log line on \(log.hostName)") { log in
            log.bookmarks.removeAll { $0.lineIndex == lineIndex }
            log.bookmarks.append(bookmark)
            log.bookmarks.sort {
                if $0.lineIndex != $1.lineIndex {
                    return $0.lineIndex < $1.lineIndex
                }
                return $0.createdAt < $1.createdAt
            }
            return true
        }

        guard didUpdate else { return nil }

        return bookmark
    }

    func deleteSessionLogBookmark(_ bookmarkID: SessionLogBookmark.ID, from logID: SessionLog.ID) {
        guard let log = sessionLogs.first(where: { $0.id == logID }),
              let bookmark = log.bookmarks.first(where: { $0.id == bookmarkID }) else { return }

        _ = updateSessionLog(withID: logID, historyEntry: "Removed log bookmark from \(log.hostName)") { log in
            let countBeforeRemoval = log.bookmarks.count
            log.bookmarks.removeAll { $0.lineIndex == bookmark.lineIndex }
            return log.bookmarks.count != countBeforeRemoval
        }
    }
}
