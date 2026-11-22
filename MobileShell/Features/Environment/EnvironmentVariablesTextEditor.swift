import SwiftUI

struct EnvironmentVariablesTextEditor: View {
    @Binding var text: String
    var helperText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $text)
                .font(.system(.footnote, design: .monospaced))
                .frame(minHeight: 96)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .scrollContentBackground(.hidden)
                .background(ShellColor.panel)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(helperText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
