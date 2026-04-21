import SwiftUI

/// Settings sub-screen for popover text size.
/// Tapping a row commits immediately; the popover rescales live behind the view.
struct TextSizeView: View {
    let onDismiss: () -> Void

    @AppStorage("textSize") private var textSizeRaw: String = TextSize.compact.rawValue
    private var selected: TextSize { TextSize(rawValue: textSizeRaw) ?? .compact }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(TextSize.allCases.enumerated()), id: \.element) { index, size in
                    optionRow(size)
                    if index < TextSize.allCases.count - 1 {
                        Divider().padding(.horizontal, 16)
                    }
                }

                Text("The popover resizes to fit.")
                    .scaledFont(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button(action: onDismiss) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .scaledFont(.caption)
                .padding(.vertical, 4)
                .padding(.trailing, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            Text("Text Size")
                .scaledFont(.headline)
                .fontWeight(.medium)

            Spacer()

            // Invisible balance for centering
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                Text("Back")
            }
            .scaledFont(.caption)
            .hidden()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Option Row

    private func optionRow(_ size: TextSize) -> some View {
        let isSelected = selected == size
        return Button {
            textSizeRaw = size.rawValue
        } label: {
            HStack(spacing: 8) {
                Text(size.displayName)
                    .scaledFont(.caption)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .scaledFont(.caption)
                        .foregroundStyle(.blue)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}

#Preview {
    TextSizeView(onDismiss: {})
        .frame(width: 360)
}
