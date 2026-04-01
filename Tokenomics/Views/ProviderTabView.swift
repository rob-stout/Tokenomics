import SwiftUI

/// Segmented tab bar for switching between providers.
/// Normal click selects a tab. Cmd+drag reorders tabs (same as macOS menu bar items).
/// At 4+ providers, inactive tabs collapse to icon-only with a native hover tooltip.
struct ProviderTabView: View {
    let providers: [ProviderId]
    @Binding var selection: ProviderId?
    var onMove: ((_ provider: ProviderId, _ toIndex: Int) -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @State private var draggedProvider: ProviderId?
    @State private var dragStartX: CGFloat = 0
    @State private var tabFrames: [ProviderId: CGRect] = [:]

    /// Icon-only mode kicks in at 4+ providers to keep the popover compact.
    private var useIconOnly: Bool { providers.count >= 4 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.3))

            HStack(spacing: 2) {
                ForEach(providers) { provider in
                    tabItem(for: provider)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: providers)
            .animation(.easeInOut(duration: 0.2), value: selection)
            .padding(2)
        }
        .coordinateSpace(name: "tabBar")
        .onPreferenceChange(TabFramePreference.self) { tabFrames = $0 }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    @ViewBuilder
    private func tabItem(for provider: ProviderId) -> some View {
        let isDragging = draggedProvider == provider
        let isSelected = selection == provider
        let showLabel = !useIconOnly || isSelected

        tabContent(provider: provider, showLabel: showLabel, isSelected: isSelected)
            .contentShape(Rectangle())
            .background(isSelected ? Color.white.opacity(0.1) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .foregroundStyle(isSelected ? .primary : .secondary)
            .scaleEffect(isDragging ? 1.08 : 1.0, anchor: .center)
            .shadow(
                color: .black.opacity(isDragging ? 0.25 : 0),
                radius: isDragging ? 6 : 0,
                x: 0, y: isDragging ? 3 : 0
            )
            .zIndex(isDragging ? 1 : 0)
            .animation(.easeInOut(duration: 0.15), value: draggedProvider)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: TabFramePreference.self,
                        value: [provider: geo.frame(in: .named("tabBar"))]
                    )
                }
            )
            .help(useIconOnly && !isSelected ? provider.tabLabel : "")
            .simultaneousGesture(TapGesture().onEnded {
                selection = provider
            })
            .simultaneousGesture(
                DragGesture(minimumDistance: 5, coordinateSpace: .named("tabBar"))
                    .onChanged { value in
                        guard NSEvent.modifierFlags.contains(.command) else { return }

                        if draggedProvider == nil {
                            draggedProvider = provider
                            dragStartX = value.startLocation.x
                        }

                        let currentX = value.location.x

                        let targetIndex = providers.enumerated().first { _, id in
                            guard let frame = tabFrames[id] else { return false }
                            return currentX >= frame.minX && currentX <= frame.maxX
                        }?.offset

                        guard let target = targetIndex,
                              let dragged = draggedProvider,
                              let sourceIndex = providers.firstIndex(of: dragged),
                              target != sourceIndex else { return }

                        onMove?(dragged, target)
                    }
                    .onEnded { _ in
                        draggedProvider = nil
                    }
            )
    }

    @ViewBuilder
    private func tabContent(provider: ProviderId, showLabel: Bool, isSelected: Bool) -> some View {
        let inner = HStack(spacing: showLabel ? 5 : 0) {
            providerTabIcon(for: provider, colorScheme: colorScheme)
                .resizable()
                .scaledToFit()
                .frame(width: 12, height: 12)
                .opacity(isSelected ? 0.9 : 0.5)
            if showLabel {
                Text(provider.tabLabel)
                    .lineLimit(1)
            }
        }
        .font(.caption)
        .fontWeight(.medium)
        .padding(.vertical, 6)
        .padding(.horizontal, showLabel ? 12 : 10)

        if useIconOnly && isSelected {
            inner.frame(width: 160)
        } else {
            inner.frame(maxWidth: .infinity)
        }
    }
}

private func providerTabIcon(for provider: ProviderId, colorScheme: ColorScheme) -> Image {
    let suffix = colorScheme == .dark ? "-white" : "-black"
    let name = "\(provider.iconBaseName)\(suffix)"
    if let nsImage = NSImage(named: name) {
        return Image(nsImage: nsImage)
    }
    return Image(systemName: "questionmark.square")
}

private struct TabFramePreference: PreferenceKey {
    static var defaultValue: [ProviderId: CGRect] = [:]
    static func reduce(value: inout [ProviderId: CGRect], nextValue: () -> [ProviderId: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}
