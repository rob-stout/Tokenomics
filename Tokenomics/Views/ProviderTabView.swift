import SwiftUI

/// Segmented tab bar for switching between providers
struct ProviderTabView: View {
    let providers: [ProviderId]
    @Binding var selection: ProviderId?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(providers) { provider in
                let isSelected = selection == provider
                Button(action: { selection = provider }) {
                    Text(provider.tabLabel)
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .background(isSelected ? Color.white.opacity(0.1) : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color(nsColor: .quaternaryLabelColor).opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }
}
