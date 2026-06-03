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
    /// Cmd+drag reorder callback — `(brand, targetIndex)`. Nil disables reorder.
    var onMove: ((_ brand: BrandId, _ toIndex: Int) -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.tokenomicsTextSize) private var textSize

    @State private var draggedBrand: BrandId?
    @State private var dragStartX: CGFloat = 0
    @State private var tabFrames: [BrandId: CGRect] = [:]

    /// Width of the rounded container (measured) and the row's minimum required
    /// width at the fill layout (measured). The row scrolls only when it can't
    /// fit — a hard count threshold mis-fires for mid counts that actually fit,
    /// leaving dead space at the end of the bar.
    @State private var availableWidth: CGFloat = 0
    @State private var contentWidth: CGFloat = 0

    /// Icon-only mode kicks in at 4+ brands to keep the popover compact.
    private var useIconOnly: Bool { brands.count >= 4 }

    /// Scroll only when the tabs genuinely overflow the bar. Both widths are
    /// measured with matching 2pt insets, so the padding cancels in the compare.
    private var needsScroll: Bool {
        Self.needsScroll(contentWidth: contentWidth, availableWidth: availableWidth)
    }

    /// Pure overflow test (extracted for unit testing): scroll only once the
    /// measured content exceeds the available width. Guards the unmeasured
    /// (zero) state so the initial render is the non-scrolling fill layout.
    static func needsScroll(contentWidth: CGFloat, availableWidth: CGFloat) -> Bool {
        availableWidth > 0 && contentWidth > availableWidth
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.3))

            tabStrip
        }
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: TabBarWidthKey.self, value: geo.size.width)
            }
        )
        .coordinateSpace(name: "brandTabBar")
        .onPreferenceChange(TabBarWidthKey.self) { availableWidth = $0 }
        .onPreferenceChange(BrandTabFramePreference.self) { tabFrames = $0 }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    /// The row of brand tabs. When the tabs fit, they fill the bar evenly
    /// (unchanged). When they overflow, the row scrolls horizontally inside the
    /// fixed container and auto-scrolls to keep the selected tab in view.
    ///
    /// An always-present hidden copy measures the row's natural minimum width so
    /// the fit decision never depends on the layout it drives (no oscillation).
    @ViewBuilder
    private var tabStrip: some View {
        ZStack {
            measuringRow
                .hidden()
                .allowsHitTesting(false)

            if needsScroll {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        tabRow(fill: false)
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
                tabRow(fill: true)
            }
        }
        .onPreferenceChange(TabContentWidthKey.self) { contentWidth = $0 }
    }

    /// Visible row. `fill: true` distributes tabs across the bar; `fill: false`
    /// uses natural widths for horizontal scrolling.
    private func tabRow(fill: Bool) -> some View {
        HStack(spacing: 2) {
            ForEach(brands) { brand in
                sizedTab(for: brand, fill: fill)
                    .id(brand)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: brands.map(\.id))
        .animation(.easeInOut(duration: 0.2), value: selection?.id)
        .padding(2)
    }

    /// Hidden mirror of the fill layout at natural widths — its intrinsic width
    /// is the minimum the bar needs. Reports up via `TabContentWidthKey`.
    private var measuringRow: some View {
        HStack(spacing: 2) {
            ForEach(brands) { brand in
                measuringTab(for: brand)
            }
        }
        .padding(2)
        .fixedSize()
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: TabContentWidthKey.self, value: geo.size.width)
            }
        )
    }

    // MARK: - Tab building

    @ViewBuilder
    private func sizedTab(for brand: BrandId, fill: Bool) -> some View {
        let isSelected = selection == brand
        let isDragging = draggedBrand == brand
        let showLabel = !useIconOnly || isSelected
        let label = tabLabel(brand: brand, showLabel: showLabel, isSelected: isSelected)

        Group {
            if !fill {
                label                              // natural width (scroll)
            } else if useIconOnly && isSelected {
                label.frame(width: 160)            // fill: selected reserves space
            } else {
                label.frame(maxWidth: .infinity)   // fill: others share the rest
            }
        }
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
        .animation(.easeInOut(duration: 0.15), value: selection?.id)
        .animation(.easeInOut(duration: 0.15), value: draggedBrand)
        // Report each tab's frame so the drag can hit-test the target slot.
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: BrandTabFramePreference.self,
                    value: [brand: geo.frame(in: .named("brandTabBar"))]
                )
            }
        )
        // Native tooltip when icon-only and not selected
        .help(useIconOnly && !isSelected ? brand.displayName : "")
        // Tap selects; Cmd+drag reorders — same model as the menu bar items.
        .simultaneousGesture(TapGesture().onEnded {
            selection = brand
        })
        .simultaneousGesture(reorderGesture(for: brand))
    }

    /// Cmd-held horizontal drag that relocates `brand` to the slot under the
    /// cursor. Without the Command modifier it's inert, so normal taps and
    /// (when scrolling) the ScrollView keep working.
    private func reorderGesture(for brand: BrandId) -> some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .named("brandTabBar"))
            .onChanged { value in
                guard onMove != nil,
                      NSEvent.modifierFlags.contains(.command) else { return }

                if draggedBrand == nil {
                    draggedBrand = brand
                    dragStartX = value.startLocation.x
                }

                let currentX = value.location.x
                let targetIndex = brands.enumerated().first { _, id in
                    guard let frame = tabFrames[id] else { return false }
                    return currentX >= frame.minX && currentX <= frame.maxX
                }?.offset

                guard let target = targetIndex,
                      let dragged = draggedBrand,
                      let sourceIndex = brands.firstIndex(of: dragged),
                      target != sourceIndex else { return }

                onMove?(dragged, target)
            }
            .onEnded { _ in
                draggedBrand = nil
            }
    }

    /// Width-contributing version used only for measurement: selected tab takes
    /// its reserved 160 (icon-only), everything else its natural width.
    @ViewBuilder
    private func measuringTab(for brand: BrandId) -> some View {
        let isSelected = selection == brand
        let showLabel = !useIconOnly || isSelected
        let label = tabLabel(brand: brand, showLabel: showLabel, isSelected: isSelected)

        if useIconOnly && isSelected {
            label.frame(width: 160)
        } else {
            label
        }
    }

    /// The styled icon (+ optional label) at natural size, before any width
    /// treatment.
    private func tabLabel(brand: BrandId, showLabel: Bool, isSelected: Bool) -> some View {
        HStack(spacing: showLabel ? 5 : 0) {
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
    }
}

// MARK: - Width measurement

private struct TabBarWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct TabContentWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct BrandTabFramePreference: PreferenceKey {
    static var defaultValue: [BrandId: CGRect] = [:]
    static func reduce(value: inout [BrandId: CGRect], nextValue: () -> [BrandId: CGRect]) {
        value.merge(nextValue()) { _, new in new }
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
