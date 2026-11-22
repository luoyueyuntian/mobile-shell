import Foundation

enum CommandSuggestionSource: String, Equatable, Codable {
    case snippet
    case history
    case builtin

    var title: String {
        switch self {
        case .snippet:
            "Snippet"
        case .history:
            "History"
        case .builtin:
            "Built-in"
        }
    }

    var symbolName: String {
        switch self {
        case .snippet:
            "curlybraces"
        case .history:
            "clock.arrow.circlepath"
        case .builtin:
            "terminal"
        }
    }
}

struct CommandSuggestion: Identifiable, Equatable, Codable {
    var id: String {
        "\(source.rawValue):\(command)"
    }

    var title: String
    var command: String
    var source: CommandSuggestionSource
    var detail: String?

    init(
        title: String,
        command: String,
        source: CommandSuggestionSource,
        detail: String? = nil
    ) {
        self.title = title
        self.command = command
        self.source = source
        self.detail = detail
    }
}
