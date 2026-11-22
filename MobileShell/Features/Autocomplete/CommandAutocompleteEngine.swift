import Foundation

struct CommandAutocompleteEngine {
    private struct Candidate {
        var suggestion: CommandSuggestion
        var sourceRank: Int
        var matchRank: Int
        var originalIndex: Int
    }

    var builtins: [CommandSuggestion] = [
        CommandSuggestion(title: "Disk usage by folder", command: "du -sh *", source: .builtin),
        CommandSuggestion(title: "List files", command: "ls -la", source: .builtin),
        CommandSuggestion(title: "Change directory", command: "cd", source: .builtin),
        CommandSuggestion(title: "Current directory", command: "pwd", source: .builtin),
        CommandSuggestion(title: "Print file", command: "cat", source: .builtin),
        CommandSuggestion(title: "Follow logs", command: "tail -f", source: .builtin),
        CommandSuggestion(title: "Search recursively", command: "grep -R", source: .builtin),
        CommandSuggestion(title: "System uptime", command: "uptime", source: .builtin),
        CommandSuggestion(title: "Current user", command: "whoami", source: .builtin),
        CommandSuggestion(title: "Service status", command: "systemctl status", source: .builtin),
        CommandSuggestion(title: "Unit logs", command: "journalctl -u", source: .builtin)
    ]

    func suggestions(
        for draft: String,
        snippets: [ShellSnippet],
        history: [String],
        limit: Int = 6
    ) -> [CommandSuggestion] {
        let query = draft.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return [] }

        var candidates: [Candidate] = []
        var sequence = 0

        for snippet in snippets {
            appendCandidate(
                CommandSuggestion(
                    title: snippet.title,
                    command: snippet.command,
                    source: .snippet,
                    detail: "\(snippet.packageName) package"
                ),
                query: query,
                sourceRank: 0,
                originalIndex: &sequence,
                candidates: &candidates
            )
        }

        for command in history {
            let normalizedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedCommand.isEmpty else { continue }
            appendCandidate(
                CommandSuggestion(
                    title: normalizedCommand,
                    command: normalizedCommand,
                    source: .history,
                    detail: "Recent command"
                ),
                query: query,
                sourceRank: 1,
                originalIndex: &sequence,
                candidates: &candidates
            )
        }

        for builtin in builtins {
            appendCandidate(
                builtin,
                query: query,
                sourceRank: 2,
                originalIndex: &sequence,
                candidates: &candidates
            )
        }

        return candidates
            .sorted {
                if $0.sourceRank != $1.sourceRank {
                    return $0.sourceRank < $1.sourceRank
                }
                if $0.matchRank != $1.matchRank {
                    return $0.matchRank < $1.matchRank
                }
                return $0.originalIndex < $1.originalIndex
            }
            .reduce(into: [CommandSuggestion]()) { suggestions, candidate in
                guard suggestions.count < limit,
                      !suggestions.contains(where: {
                          $0.command.caseInsensitiveCompare(candidate.suggestion.command) == .orderedSame
                      })
                else { return }
                suggestions.append(candidate.suggestion)
            }
    }

    private func appendCandidate(
        _ suggestion: CommandSuggestion,
        query: String,
        sourceRank: Int,
        originalIndex: inout Int,
        candidates: inout [Candidate]
    ) {
        guard let matchRank = matchRank(for: suggestion, query: query) else {
            originalIndex += 1
            return
        }

        candidates.append(
            Candidate(
                suggestion: suggestion,
                sourceRank: sourceRank,
                matchRank: matchRank,
                originalIndex: originalIndex
            )
        )
        originalIndex += 1
    }

    private func matchRank(for suggestion: CommandSuggestion, query: String) -> Int? {
        let title = suggestion.title.lowercased()
        let command = suggestion.command.lowercased()
        if title.hasPrefix(query) || command.hasPrefix(query) {
            return 0
        }
        if query.count > 1, title.contains(query) || command.contains(query) {
            return 1
        }
        return nil
    }
}
