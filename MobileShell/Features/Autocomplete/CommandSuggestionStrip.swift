import SwiftUI

struct CommandSuggestionStrip: View {
    let suggestions: [CommandSuggestion]
    let action: (CommandSuggestion) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestions) { suggestion in
                    Button {
                        action(suggestion)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: suggestion.source.symbolName)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(ShellColor.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestion.command)
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .lineLimit(1)
                                Text(suggestion.title)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(ShellColor.secondaryText)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(ShellColor.deepPanel)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(ShellColor.primaryText)
                    .accessibilityLabel("Use command suggestion \(suggestion.command)")
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
        }
    }
}
