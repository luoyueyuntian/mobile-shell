import SwiftUI

struct SettingsView: View {
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                SettingRow(symbol: "lock.shield", title: "Encrypted Vault", value: "Local preview")
                SettingRow(symbol: "faceid", title: "Biometric Unlock", value: "Enabled")
                SettingRow(symbol: "keyboard", title: "Terminal Keyboard", value: "Extra row")
                SettingRow(symbol: "paintpalette", title: "Theme", value: "Obsidian Neon")
            }
            .padding(18)
        }
    }
}

private struct SettingRow: View {
    let symbol: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(ShellColor.accent)
                .frame(width: 42, height: 42)
                .background(ShellColor.panel)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(value)
                    .font(.caption)
                    .foregroundStyle(ShellColor.secondaryText)
            }
            Spacer()
        }
        .padding(13)
        .background(ShellColor.deepPanel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
