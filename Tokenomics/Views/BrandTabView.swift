import SwiftUI

/// Segmented tab bar for switching between brands (one tab per brand).
///
/// Used by `PopoverView` when `FeatureFlags.brandAggregation` is on.
/// Brand order is not user-reorderable in this phase — it follows
/// `UsageViewModel.enabledBrands` which is stable by first-visible-provider.
/// Icon-only mode matches `ProviderTabView`: kicks in at 4+ brands.
struct BrandTabView: View {
    let brands: [BrandId]
    @Binding var selection: BrandId?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.tokenomicsTextSize) private var textSize

    /// Icon-only mode kicks in at 4+ brands to keep the popover compact.
    private var useIconOnly: Bool { brands.count >= 4 }

    /// Past 6 brands the row can't fit the popover width even icon-collapsed,
    /// so it scrolls horizontally instead of cramming the tabs together. The
    /// rounded container stays full-width (fixed) so window padding is unaffected.
    private var scrolls: Bool { brands.count > 6 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.3))

            tabStrip
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    /// The row of brand tabs. Below the scroll threshold tabs fill the width
    /// evenly (unchanged). Above it, the row scrolls horizontally inside the
    /// fixed container and auto-scrolls to keep the selected tab in view.
    @ViewBuilder
    private var tabStrip: some View {
        let row = HStack(spacing: 2) {
            ForEach(brands) { brand in
                tabItem(for: brand)
                    .id(brand)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: brands.map(\.id))
        .animation(.easeInOut(duration: 0.2), value: selection?.id)
        .padding(2)

        if scrolls {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    row
                }
                .onAppear {
                    if let selection { proxy.scrollTo(selection, anchor: .center) }
                }
                .onChange(of: selection) { _, newValue in
                    guard let newValue else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
        } else {
            row
        }
    }

    @ViewBuilder
    private func tabItem(for brand: BrandId) -> some View {
        let isSelected = selection == brand
        let showLabel = !useIconOnly || isSelected

        tabContent(brand: brand, showLabel: showLabel, isSelected: isSelected)
            .contentShape(Rectangle())
            .background(isSelected ? Color.white.opacity(0.1) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .foregroundStyle(isSelected ? .primary : .secondary)
            .animation(.easeInOut(duration: 0.15), value: selection?.id)
            // Native tooltip when icon-only and not selected
            .help(useIconOnly && !isSelected ? brand.displayName : "")
            .onTapGesture {
                selection = brand
            }
    }

    @ViewBuilder
    private func tabContent(brand: BrandId, showLabel: Bool, isSelected: Bool) -> some View {
        let inner = HStack(spacing: showLabel ? 5 : 0) {
            brandTabIcon(for: brand, colorScheme: colorScheme)
                .resizable()
                .scaledToFit()
                .frame(width: 12 * textSize.iconScale, height: 12 * textSize.iconScale)
                .opacity(isSelected ? 0.9 : 0.5)
            if showLabel {
                Text(brand.displayName)
                    .lineLimit(1)
            }
        }
        .scaledFont(.caption)
        .fontWeight(.medium)
        .padding(.vertical, 6)
        .padding(.horizontal, showLabel ? 12 : 10)

        if scrolls {
            inner
        } else if useIconOnly && isSelected {
            inner.frame(width: 160)
        } else {
            inner.frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Icon Resolution

/// Resolves the tab icon for a brand. Uses the primary pool's icon asset —
/// the most recognizable asset for the brand (e.g. Claude icon for Anthropic,
/// ChatGPT icon for OpenAI). Falls back to a system image when no asset exists.
private func brandTabIcon(for brand: BrandId, colorScheme: ColorScheme) -> Image {
    let suffix = colorScheme == .dark ? "-white" : "-black"
    // Use the brand's primary (first-defined) pool icon as the representative asset.
    // `BrandId.pools` is a Set — convert to a stable order via CaseIterable fallback.
    let primaryProvider = primaryPool(for: brand)
    let name = "\(primaryProvider.iconBaseName)\(suffix)"
    if let nsImage = NSImage(named: name) {
        return Image(nsImage: nsImage)
    }
    return Image(systemName: "questionmark.square")
}

/// Returns the primary ProviderId for a brand's tab icon.
/// Prefers the pool whose `ProviderId.allCases` position is lowest — ensures
/// stable, deterministic icon selection without depending on `Set` ordering.
private func primaryPool(for brand: BrandId) -> ProviderId {
    let pools = brand.pools
    return ProviderId.allCases.first { pools.contains($0) } ?? .claude
}
