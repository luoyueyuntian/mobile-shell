import SwiftUI

struct SessionLogDetailView: View {
    @Bindable var store: MobileShellStore
    let logID: SessionLog.ID

    @State private var bookmarkDraft: SessionLogBookmarkDraft?
    @Environment(\.dismiss) private var dismiss

    private var log: SessionLog? {
        store.sessionLogs.first(where: { $0.id == logID })
    }

    var body: some View {
        Group {
            if let log {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        logMetadataCard(for: log)

                        if !log.bookmarks.isEmpty {
                            bookmarksCard(for: log)
                        }

                        linesCard(for: log)
                    }
                    .padding(18)
                }
            } else {
                ContentUnavailableView(
                    "Session log not found",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("The log may have been removed from the store.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
        }
        .navigationTitle(log?.hostName ?? "Session Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .sheet(item: $bookmarkDraft) { draft in
            BookmarkEditorView(
                title: "Add Bookmark",
                lineIndex: draft.lineIndex,
                linePreview: draft.linePreview
            ) { title in
                _ = store.addSessionLogBookmark(
                    to: logID,
                    lineIndex: draft.lineIndex,
                    title: title
                )
            }
        }
    }

    @ViewBuilder
    private func logMetadataCard(for log: SessionLog) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(log.hostName)
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Label {
                    Text("Started \(log.startedAt.formatted(date: .abbreviated, time: .shortened))")
                } icon: {
                    Image(systemName: "clock")
                }

                if let endedAt = log.endedAt {
                    Label {
                        Text("Ended \(endedAt.formatted(date: .abbreviated, time: .shortened))")
                    } icon: {
                        Image(systemName: "checkmark.circle")
                    }
                } else {
                    Label {
                        Text("Session still open")
                    } icon: {
                        Image(systemName: "record.circle")
                    }
                }

                Label {
                    Text(log.bookmarkSummary)
                } icon: {
                    Image(systemName: "bookmark")
                }
            }
            .font(.caption)
            .foregroundStyle(ShellColor.secondaryText)
        }
        .padding(14)
        .background(ShellColor.deepPanel)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(ShellColor.stroke, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func bookmarksCard(for log: SessionLog) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Bookmarks", systemImage: "bookmark.fill")
                .font(.headline)

            ForEach(log.bookmarks) { bookmark in
                VStack(alignment: .leading, spacing: 4) {
                    Text(bookmark.title)
                        .font(.subheadline.weight(.semibold))
                    Text("Line \(bookmark.lineIndex + 1)")
                        .font(.caption)
                        .foregroundStyle(ShellColor.secondaryText)
                    Text(bookmark.linePreview)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(ShellColor.terminalText)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(ShellColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(14)
        .background(ShellColor.deepPanel)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(ShellColor.stroke, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func linesCard(for log: SessionLog) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Lines", systemImage: "terminal")
                .font(.headline)

            ForEach(Array(log.lines.enumerated()), id: \.offset) { index, line in
                let presentation = SessionLogLinePresentation(
                    log: log,
                    lineIndex: index,
                    line: line
                )

                HStack(alignment: .top, spacing: 12) {
                    Text(presentation.lineNumberText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(presentation.isBookmarked ? ShellColor.accent : ShellColor.secondaryText)
                        .frame(width: 30, alignment: .trailing)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(presentation.lineText)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(ShellColor.terminalText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)

                        if let bookmarkTitle = presentation.bookmarkTitle {
                            Text(bookmarkTitle)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ShellColor.accent)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        switch presentation.bookmarkAction {
                        case .add:
                            bookmarkDraft = SessionLogBookmarkDraft(
                                lineIndex: presentation.lineIndex,
                                linePreview: line
                            )
                        case .remove:
                            if let bookmark = log.bookmark(for: presentation.lineIndex) {
                                store.deleteSessionLogBookmark(bookmark.id, from: logID)
                            }
                        }
                    } label: {
                        Image(systemName: presentation.bookmarkIconName)
                            .font(.caption.weight(.semibold))
                            .frame(width: 28, height: 28)
                            .foregroundStyle(presentation.isBookmarked ? .black : ShellColor.accent)
                            .background(presentation.isBookmarked ? ShellColor.accent : ShellColor.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(presentation.accessibilityLabel)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(presentation.isBookmarked ? ShellColor.panel : ShellColor.terminal)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(presentation.isBookmarked ? ShellColor.accent : Color.clear, lineWidth: 1)
                )
            }
        }
        .padding(14)
        .background(ShellColor.deepPanel)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(ShellColor.stroke, lineWidth: 1)
        )
    }
}

internal struct SessionLogLinePresentation {
    enum BookmarkAction {
        case add
        case remove
    }

    let lineIndex: Int
    let lineNumberText: String
    let lineText: String
    let isBookmarked: Bool
    let bookmarkTitle: String?

    var bookmarkIconName: String {
        isBookmarked ? "bookmark.fill" : "bookmark"
    }

    var bookmarkAction: BookmarkAction {
        isBookmarked ? .remove : .add
    }

    var accessibilityLabel: String {
        isBookmarked ? "Remove bookmark from line \(lineIndex + 1)" : "Bookmark line \(lineIndex + 1)"
    }

    init(log: SessionLog, lineIndex: Int, line: String) {
        self.lineIndex = lineIndex
        self.lineNumberText = "\(lineIndex + 1)"
        self.lineText = line.isEmpty ? " " : line
        self.isBookmarked = log.bookmark(for: lineIndex) != nil
        self.bookmarkTitle = log.bookmark(for: lineIndex)?.title
    }
}

private struct SessionLogBookmarkDraft: Identifiable {
    let id = UUID()
    let lineIndex: Int
    let linePreview: String
}

private struct BookmarkEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let sheetTitle: String
    let lineIndex: Int
    let linePreview: String
    let save: (String) -> Void

    @State private var draftTitle = ""

    init(
        title: String,
        lineIndex: Int,
        linePreview: String,
        save: @escaping (String) -> Void
    ) {
        self.sheetTitle = title
        self.lineIndex = lineIndex
        self.linePreview = linePreview
        self.save = save
        _draftTitle = State(initialValue: linePreview)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Bookmark title") {
                    TextField("Title", text: $draftTitle)
                }

                Section("Selected line") {
                    Text("Line \(lineIndex + 1)")
                    Text(linePreview.isEmpty ? " " : linePreview)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(ShellColor.secondaryText)
                }
            }
            .navigationTitle(sheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save(draftTitle)
                        dismiss()
                    }
                }
            }
        }
    }
}
