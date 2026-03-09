import SwiftUI

/// Identity screen — what Tokenomics is, who built it, and legal info.
/// Displayed inline within the popover, replacing the main content.
struct AboutView: View {
    let onDismiss: () -> Void

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: onDismiss) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Text("About")
                    .font(.headline)
                    .fontWeight(.medium)

                Spacer()

                // Invisible balance for centering
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .font(.caption)
                .hidden()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // App identity
                    HStack(spacing: 12) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .frame(width: 48, height: 48)
                            .cornerRadius(10)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tokenomics")
                                .font(.title3)
                                .fontWeight(.semibold)
                            Text("v\(appVersion)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Divider()

                    // What it is
                    Text("A menu bar tool for developers using AI coding assistants. Glance at your rate limits without leaving your editor.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Divider()

                    // Built by
                    Text("Built by Rob Stout")
                        .font(.caption)
                        .fontWeight(.medium)

                    // Links
                    VStack(spacing: 0) {
                        linkRow(
                            icon: "person.circle",
                            label: "Rob Stout \u{2014} Portfolio",
                            url: "https://robrstout.com"
                        )

                        Divider()

                        linkRow(
                            icon: "chevron.left.forwardslash.chevron.right",
                            label: "View Source on GitHub",
                            url: "https://github.com/rob-stout/Tokenomics"
                        )

                        Divider()

                        linkRow(
                            icon: "cup.and.saucer",
                            label: "Buy Me a Coffee",
                            url: "https://buymeacoffee.com/robstout"
                        )
                    }

                    Divider()

                    // Legal
                    sectionHeader("Legal")

                    HStack(spacing: 16) {
                        if let privacyURL = URL(string: "https://github.com/rob-stout/Tokenomics/blob/main/docs/PRIVACY.md") {
                            Link("Privacy Policy", destination: privacyURL)
                                .font(.caption)
                        }
                        if let licenseURL = URL(string: "https://github.com/rob-stout/Tokenomics/blob/main/LICENSE") {
                            Link("License", destination: licenseURL)
                                .font(.caption)
                        }
                    }

                    Text("Tokenomics is not affiliated with, endorsed by, or sponsored by Anthropic PBC, OpenAI Inc., or Google LLC.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
            }
        }
    }

    // MARK: - Components

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline)
            .fontWeight(.semibold)
    }

    private func linkRow(icon: String, label: String, url: String) -> some View {
        Button {
            if let linkURL = URL(string: url) {
                NSWorkspace.shared.open(linkURL)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 16, alignment: .center)

                Text(label)
                    .font(.caption)

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    AboutView(onDismiss: {})
        .frame(width: 320)
}
