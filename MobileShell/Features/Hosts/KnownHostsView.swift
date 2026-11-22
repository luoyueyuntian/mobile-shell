import SwiftUI

struct KnownHostsView: View {
    @Bindable var store: MobileShellStore
    @State private var knownHostPendingDelete: KnownHost?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Known Hosts")
                        .font(.title3.weight(.bold))
                    Text("Trusted SSH host fingerprints stored in the local vault.")
                        .font(.caption)
                        .foregroundStyle(ShellColor.secondaryText)
                }

                if store.knownHosts.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.shield")
                            .font(.title2)
                            .foregroundStyle(ShellColor.secondaryText)
                        Text("No trusted hosts yet")
                            .font(.subheadline.weight(.semibold))
                        Text("Host fingerprints will appear here as the SSH trust store is populated.")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(ShellColor.secondaryText)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity)
                    .background(ShellColor.deepPanel)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                ForEach(store.knownHosts) { knownHost in
                    KnownHostRow(knownHost: knownHost) {
                        knownHostPendingDelete = knownHost
                    }
                }
            }
            .padding(18)
        }
        .confirmationDialog(
            "Delete Known Host?",
            isPresented: Binding(
                get: { knownHostPendingDelete != nil },
                set: { isPresented in
                    if !isPresented {
                        knownHostPendingDelete = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let knownHost = knownHostPendingDelete {
                Button("Delete \(knownHost.host)", role: .destructive) {
                    store.deleteKnownHost(knownHost)
                    knownHostPendingDelete = nil
                }
            }
        } message: {
            if let knownHost = knownHostPendingDelete {
                Text("This removes the trusted \(knownHost.keyType) fingerprint for \(knownHost.host).")
            }
        }
    }
}

private struct KnownHostRow: View {
    let knownHost: KnownHost
    let deleteAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.shield.fill")
                .font(.title3)
                .foregroundStyle(ShellColor.accent)
                .frame(width: 42, height: 42)
                .background(ShellColor.panel)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(knownHost.title)
                    .font(.subheadline.weight(.semibold))
                Text(knownHost.subtitle)
                    .font(.caption)
                    .foregroundStyle(ShellColor.secondaryText)
                    .lineLimit(2)
            }

            Spacer()

            Menu {
                Button(role: .destructive) {
                    deleteAction()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(ShellColor.secondaryText)
                    .frame(width: 34, height: 42)
            }
            .buttonStyle(.plain)
        }
        .padding(13)
        .background(ShellColor.deepPanel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
