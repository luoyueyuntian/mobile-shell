import SwiftUI

struct SessionLogsView: View {
    @Bindable var store: MobileShellStore
    @State private var selectedLog: SessionLogSelection?

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
                            selectedLog = SessionLogSelection(id: log.id)
                        } label: {
                            SessionLogCard(log: log)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(18)
        }
        .sheet(item: $selectedLog) { selection in
            NavigationStack {
                SessionLogDetailView(store: store, logID: selection.id)
            }
        }
    }
}

private struct SessionLogSelection: Identifiable {
    let id: SessionLog.ID
}

private struct SessionLogsEmptyState: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.title2)
                .foregroundStyle(ShellColor.secondaryText)
            Text("No session logs yet")
                .font(.subheadline.weight(.semibold))
            Text("Connect to a host and MobileShell will keep a local activity record here.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(ShellColor.secondaryText)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(ShellColor.deepPanel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct SessionLogCard: View {
    let log: SessionLog

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: log.endedAt == nil ? "record.circle" : "checkmark.circle")
                    .font(.title3)
                    .foregroundStyle(log.endedAt == nil ? ShellColor.accent : ShellColor.secondaryText)

                VStack(alignment: .leading, spacing: 4) {
                    Text(log.hostName)
                        .font(.headline)
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(ShellColor.secondaryText)
                }

                Spacer()

                Text(log.endedAt == nil ? "Open" : "Saved")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(log.endedAt == nil ? ShellColor.accent : ShellColor.secondaryText)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(ShellColor.surface)
                    .clipShape(Capsule())
            }

            if !log.preview.isEmpty {
                Text(log.preview)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(ShellColor.terminalText)
                    .lineLimit(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(ShellColor.terminal)
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

    private var summary: String {
        "\(log.lineCount) lines, \(log.bookmarkSummary), started \(log.startedAt.formatted(date: .abbreviated, time: .shortened))"
    }
}
