import SwiftUI

struct HostTagFilterStrip: View {
    let tags: [String]
    let selectedTag: String?
    let selectTag: (String) -> Void
    let clearSelection: () -> Void

    var body: some View {
        if !tags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    HostTagFilterChip(title: "All", isSelected: selectedTag == nil) {
                        clearSelection()
                    }

                    ForEach(tags, id: \.self) { tag in
                        HostTagFilterChip(title: "#\(tag)", isSelected: isSelected(tag)) {
                            selectTag(tag)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Host tag filters")
        }
    }

    private func isSelected(_ tag: String) -> Bool {
        selectedTag?.caseInsensitiveCompare(tag) == .orderedSame
    }
}

private struct HostTagFilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? .black : ShellColor.secondaryText)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(isSelected ? ShellColor.accent : ShellColor.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isSelected ? ShellColor.accent.opacity(0.85) : ShellColor.stroke, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
