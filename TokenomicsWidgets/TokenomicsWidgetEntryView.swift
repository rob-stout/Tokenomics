import SwiftUI
import WidgetKit
import Foundation

// MARK: - Widget Theme

/// Branded color palette for widget appearances.
/// `.dark` and `.light` are used in full-color rendering mode.
/// `.accented` provides system semantic colors for accented/vibrant modes.
struct WidgetTheme {
    let labelColor: Color
    let shortColor: Color
    let longColor: Color
    let barTrack: Color
    let barFillOpacity: Double
    let gradientStops: [Gradient.Stop]
    let iconSuffix: String
    let paceDotColor: Color

    var gradient: LinearGradient {
        LinearGradient(
            stops: gradientStops,
            startPoint: UnitPoint(x: 0.35, y: 0),
            endPoint: UnitPoint(x: 0.65, y: 1.0)
        )
    }

    /// Always returns the branded dark/light theme based on color scheme.
    /// The `.accented` preset is intentionally retired — on macOS the widget host
    /// rarely delivers `.fullColor`, so keying on it produced a degraded white/gray
    /// appearance in almost all real-world placements.
    static func current(for scheme: ColorScheme, renderingMode: WidgetRenderingMode) -> WidgetTheme {
        return scheme == .dark ? .dark : .light
    }

    // MARK: Full Color Presets

    static let dark = WidgetTheme(
        labelColor: Color(red: 117/255, green: 203/255, blue: 245/255).opacity(0.5),
        shortColor: Color(red: 117/255, green: 203/255, blue: 245/255),
        longColor: Color(red: 51/255, green: 137/255, blue: 199/255),
        barTrack: Color(red: 75/255, green: 166/255, blue: 210/255).opacity(0.25),
        barFillOpacity: 1.0,
        gradientStops: [
            .init(color: Color(red: 14/255, green: 51/255, blue: 77/255), location: 0.103),
            .init(color: Color(red: 5/255, green: 25/255, blue: 40/255), location: 0.881)
        ],
        iconSuffix: "-white",
        paceDotColor: .white
    )

    static let light = WidgetTheme(
        labelColor: Color(red: 47/255, green: 132/255, blue: 191/255).opacity(0.67),
        shortColor: Color(red: 47/255, green: 132/255, blue: 191/255),
        longColor: Color(red: 86/255, green: 162/255, blue: 214/255),
        barTrack: Color(red: 40/255, green: 97/255, blue: 149/255).opacity(0.12),
        barFillOpacity: 1.0,
        gradientStops: [
            .init(color: Color(red: 243/255, green: 239/255, blue: 229/255), location: 0.016),
            .init(color: Color(red: 230/255, green: 224/255, blue: 212/255), location: 0.845)
        ],
        iconSuffix: "-d.blue",
        paceDotColor: Color(red: 14/255, green: 51/255, blue: 77/255)
    )

    // MARK: Accented / Vibrant Preset (system semantic colors)

    static let accented = WidgetTheme(
        labelColor: .secondary,
        shortColor: .white,
        longColor: .white,
        barTrack: Color.white.opacity(0.1),
        barFillOpacity: 0.6,
        gradientStops: [],
        iconSuffix: "-white",
        paceDotColor: .white
    )

    /// Returns the fill color for a bar. `isLong` selects `longColor` vs `shortColor`.
    func fillColor(for utilization: Double, isLong: Bool = false) -> Color {
        isLong ? longColor : shortColor
    }
}

// MARK: - Theme Environment Key

/// Allows child views to read the resolved theme without each needing widgetRenderingMode.
private struct WidgetThemeKey: EnvironmentKey {
    static let defaultValue = WidgetTheme.accented
}

extension EnvironmentValues {
    var widgetTheme: WidgetTheme {
        get { self[WidgetThemeKey.self] }
        set { self[WidgetThemeKey.self] = newValue }
    }
}

// MARK: - Theme Background

/// Renders the branded gradient background for all rendering modes.
/// Previously used `Rectangle().fill(.fill.tertiary)` for non-fullColor mode,
/// which resolved to black on macOS widget hosts — `.fill` is a foreground style
/// and is not valid as a containerBackground fill. Now always uses the branded
/// gradient keyed on color scheme, which renders correctly in all modes.
struct WidgetThemeBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        WidgetTheme.current(for: colorScheme, renderingMode: .fullColor).gradient
    }
}

// MARK: - Entry View Router

/// Routes to the correct widget view and injects the resolved theme into the environment.
struct TokenomicsWidgetEntryView: View {
    let entry: UsageEntry

    @Environment(\.widgetFamily) var family
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        content
            .environment(\.widgetTheme, WidgetTheme.current(for: colorScheme, renderingMode: renderingMode))
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        case .systemLarge:
            LargeWidgetView(entry: entry)
        default:
            MediumWidgetView(entry: entry)
        }
    }
}

// MARK: - Small Widget

/// Dual-ring design: outer ring for short window, inner ring for long window.
/// Provider icon in corner identifies the source. In Smart mode, picks highest utilization.
struct SmallWidgetView: View {
    let entry: UsageEntry

    @Environment(\.widgetTheme) private var theme

    private var displayProvider: WidgetDataStore.WidgetSnapshot.ProviderEntry? {
        guard let providers = entry.snapshot?.providers, !providers.isEmpty else { return nil }

        switch entry.selectedProvider {
        case .smart:
            return providers.max(by: { $0.shortWindow.utilization < $1.shortWindow.utilization })
        case .claude:
            return providers.first(where: { $0.id == "claude" })
        case .copilot:
            return providers.first(where: { $0.id == "copilot" })
        case .cursor:
            return providers.first(where: { $0.id == "cursor" })
        case .codex:
            return providers.first(where: { $0.id == "codex" })
        case .gemini:
            return providers.first(where: { $0.id == "gemini" })
        case .elevenlabs:
            return providers.first(where: { $0.id == "elevenlabs" })
        case .runway:
            return providers.first(where: { $0.id == "runway" })
        case .stableDiffusion:
            return providers.first(where: { $0.id == "stableDiffusion" })
        }
    }

    var body: some View {
        if let provider = displayProvider {
            GeometryReader { geo in
                let size = min(geo.size.width, geo.size.height)
                let outerDia = size * 0.61
                let innerDia = size * 0.46
                let lineW = size * 0.07
                let dotSize = lineW
                let fontSize = size * 0.125

                // Ring pushed slightly below center (top:bottom ≈ 3:2)
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    ZStack {
                        // Outer ring track (short window)
                        Circle()
                            .stroke(theme.barTrack, lineWidth: lineW)
                            .frame(width: outerDia, height: outerDia)

                        // Outer ring fill (short window)
                        Circle()
                            .trim(from: 0, to: min(provider.shortWindow.utilization / 100.0, 1.0))
                            .stroke(
                                theme.fillColor(for: provider.shortWindow.utilization),
                                style: StrokeStyle(lineWidth: lineW, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .frame(width: outerDia, height: outerDia)

                        // Outer ring tracker dot (short window pace)
                        if provider.shortWindow.pace > 0.02 {
                            Circle()
                                .fill(theme.paceDotColor)
                                .frame(width: dotSize, height: dotSize)
                                .offset(trackerDotOffset(progress: provider.shortWindow.pace, radius: outerDia / 2))
                        }

                        // Inner ring track (long window — only when available)
                        if let longWindow = provider.longWindow {
                            Circle()
                                .stroke(theme.barTrack, lineWidth: lineW)
                                .frame(width: innerDia, height: innerDia)

                            // Inner ring fill (long window)
                            Circle()
                                .trim(from: 0, to: min(longWindow.utilization / 100.0, 1.0))
                                .stroke(
                                    theme.fillColor(for: longWindow.utilization, isLong: true),
                                    style: StrokeStyle(lineWidth: lineW, lineCap: .round)
                                )
                                .rotationEffect(.degrees(-90))
                                .frame(width: innerDia, height: innerDia)

                            // Inner ring tracker dot (long window pace)
                            if longWindow.pace > 0.02 {
                                Circle()
                                    .fill(theme.paceDotColor)
                                    .frame(width: dotSize, height: dotSize)
                                    .offset(trackerDotOffset(progress: longWindow.pace, radius: innerDia / 2))
                            }
                        }

                        // Percentage — centered in rings
                        Text("\(Int(provider.shortWindow.utilization))%")
                            .font(.system(size: fontSize, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(theme.shortColor)
                    }
                    .offset(y: size * 0.024)

                    Spacer(minLength: 0)
                    // Reset countdown — pinned to bottom
                    Text("Resets in \(provider.shortWindow.shortTimeUntilReset)")
                        .font(.system(size: size * 0.052))
                        .foregroundStyle(theme.labelColor)
                        .padding(.bottom, size * 0.06)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .overlay(alignment: .topLeading) {
                GeometryReader { geo in
                    let s = min(geo.size.width, geo.size.height)
                    providerIcon(provider.id, theme: theme)
                        .resizable()
                        .scaledToFit()
                        .frame(width: s * 0.112, height: s * 0.112)
                        .padding(.top, s * 0.082)
                        .padding(.leading, s * 0.082)
                }
            }
        } else {
            NoDataView()
        }
    }

    /// Computes the offset for a tracker dot at `progress` (0–1) around a ring of `radius`.
    private func trackerDotOffset(progress: Double, radius: CGFloat) -> CGSize {
        let angle: Double = progress * 2 * Double.pi - Double.pi / 2
        let dx: Double = cos(angle)
        let dy: Double = sin(angle)
        return CGSize(width: CGFloat(dx) * radius, height: CGFloat(dy) * radius)
    }
}

// MARK: - Medium Widget

/// Shows all connected providers with both usage windows.
/// Uses compact rows for 2–3 providers, spacious single-column for 1.
struct MediumWidgetView: View {
    let entry: UsageEntry

    @Environment(\.widgetTheme) private var theme

    var body: some View {
        if let snapshot = entry.snapshot, !snapshot.providers.isEmpty {
            let useCompact = snapshot.providers.count >= 2
            let maxVisible = 3
            let visibleProviders = Array(snapshot.providers.prefix(maxVisible))
            let overflowCount = snapshot.providers.count - maxVisible

            VStack(alignment: .leading, spacing: 0) {
                // Header — timer always top-right
                HStack {
                    Text("Tokenomics")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(theme.labelColor)
                    Spacer()
                    if let updatedAt = entry.snapshot?.updatedAt {
                        Text(updatedAt, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(theme.labelColor)
                    }
                }
                .padding(.bottom, useCompact ? 8 : 20)

                // Provider rows
                if useCompact {
                    // 2+ providers: compact rows with clamped spacing
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(visibleProviders.enumerated()), id: \.element.id) { index, provider in
                            if index > 0 {
                                Spacer(minLength: 8).frame(maxHeight: 24)
                            }
                            CompactProviderRow(provider: provider)
                        }
                    }
                } else {
                    // 1 provider: spacious single-column, centered between header and footer
                    Spacer(minLength: 0)
                    ForEach(visibleProviders, id: \.id) { provider in
                        LargeProviderRow(provider: provider)
                    }
                }

                Spacer(minLength: 0)

                // Footer — overflow indicator or share CTA
                if overflowCount > 0 {
                    Text("+\(overflowCount) in app")
                        .font(.caption2)
                        .foregroundStyle(theme.labelColor)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 10)
                } else if visibleProviders.count <= 2 {
                    ShareCTA()
                        .padding(.top, 10)
                }
            }
            .widgetURL(URL(string: "tokenomics://open"))
            .padding(.top, 14)
            .padding(.bottom, 16)
            .padding(.horizontal, 16)
        } else {
            NoDataView()
        }
    }
}

// MARK: - Large Widget

/// Full-height widget. 1–3 providers: spacious single-column.
/// 4–7: compact rows with fixed 24pt gap.
/// 8+: compact 2-column, space-between + overflow footer.
struct LargeWidgetView: View {
    let entry: UsageEntry

    @Environment(\.widgetTheme) private var theme

    var body: some View {
        if let snapshot = entry.snapshot, !snapshot.providers.isEmpty {
            let useCompact = snapshot.providers.count >= 4
            let maxVisible = 7
            let visibleProviders = Array(snapshot.providers.prefix(maxVisible))
            let overflowCount = snapshot.providers.count - maxVisible
            let hasOverflow = overflowCount > 0

            VStack(alignment: .leading, spacing: 0) {
                // Header — timer top-right
                HStack {
                    Text("Tokenomics")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(theme.labelColor)
                    Spacer()
                    if let updatedAt = entry.snapshot?.updatedAt {
                        Text(updatedAt, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(theme.labelColor)
                    }
                }
                .padding(.bottom, hasOverflow ? 14 : 20)

                // Provider rows
                if useCompact {
                    // 4+ providers: compact rows with clamped spacing
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(visibleProviders.enumerated()), id: \.element.id) { index, provider in
                            if index > 0 {
                                Spacer(minLength: 12).frame(maxHeight: 28)
                            }
                            CompactProviderRow(provider: provider)
                        }
                    }
                } else {
                    // 1–3 providers: spacious single-column with clamped spacing
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(visibleProviders.enumerated()), id: \.element.id) { index, provider in
                            if index > 0 {
                                Spacer(minLength: 16).frame(maxHeight: 24)
                            }
                            LargeProviderRow(provider: provider)
                        }
                    }
                }

                Spacer(minLength: 0)

                // Footer — overflow indicator or share CTA
                if hasOverflow {
                    Text("+\(overflowCount) in app")
                        .font(.caption2)
                        .foregroundStyle(theme.labelColor)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 12)
                } else if visibleProviders.count <= 7 {
                    ShareCTA()
                        .padding(.top, 12)
                }
            }
            .widgetURL(URL(string: "tokenomics://open"))
            .padding(.top, 14)
            .padding(.bottom, 14)
            .padding(.horizontal, 16)
        } else {
            NoDataView()
        }
    }
}

// MARK: - Provider Row Views

/// Compact single-line row: badge | short window bar | long window bar.
/// Used by MediumWidgetView and LargeWidgetView at higher provider counts.
private struct CompactProviderRow: View {
    let provider: WidgetDataStore.WidgetSnapshot.ProviderEntry

    @Environment(\.widgetTheme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            // Provider icon
            providerIcon(provider.id, theme: theme)
                .resizable()
                .scaledToFit()
                .frame(width: 17, height: 17)

            // Short window bar
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(provider.shortWindow.label)
                        .font(.system(size: 9))
                        .foregroundStyle(theme.labelColor)
                    Spacer()
                    Text("\(Int(provider.shortWindow.utilization))%")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .monospacedDigit()
                        .foregroundStyle(theme.fillColor(for: provider.shortWindow.utilization))
                }

                WidgetProgressBar(
                    utilization: provider.shortWindow.utilization,
                    pace: provider.shortWindow.pace,
                    isLong: false
                )
            }

            // Long window bar — only when the provider exposes two usage windows
            if let longWindow = provider.longWindow {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(longWindow.label)
                            .font(.system(size: 9))
                            .foregroundStyle(theme.labelColor)
                        Spacer()
                        Text("\(Int(longWindow.utilization))%")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .monospacedDigit()
                            .foregroundStyle(theme.fillColor(for: longWindow.utilization, isLong: true))
                    }

                    WidgetProgressBar(
                        utilization: longWindow.utilization,
                        pace: longWindow.pace,
                        isLong: true
                    )
                }
            }
        }
    }
}

/// Spacious row with header line (name + plan) plus separate bar rows per window.
/// Used by MediumWidgetView (1 provider) and LargeWidgetView (1–4 providers).
private struct LargeProviderRow: View {
    let provider: WidgetDataStore.WidgetSnapshot.ProviderEntry

    @Environment(\.widgetTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: icon + name + plan
            HStack(spacing: 10) {
                providerIcon(provider.id, theme: theme)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 17, height: 17)

                Text(provider.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(theme.shortColor.opacity(0.85))

                Spacer()

                Text(provider.planLabel)
                    .font(.caption2)
                    .foregroundStyle(theme.labelColor)
            }

            // Metrics
            VStack(alignment: .leading, spacing: 8) {
                // Short window bar row
                HStack(spacing: 8) {
                    Text(provider.shortWindow.label)
                        .font(.system(size: 9))
                        .foregroundStyle(theme.labelColor)
                        .frame(width: 48, alignment: .leading)

                    WidgetProgressBar(
                        utilization: provider.shortWindow.utilization,
                        pace: provider.shortWindow.pace,
                        isLong: false
                    )

                    Text("\(Int(provider.shortWindow.utilization))%")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .monospacedDigit()
                        .foregroundStyle(theme.fillColor(for: provider.shortWindow.utilization))
                        .frame(width: 30, alignment: .trailing)
                }

                // Long window bar row
                if let longWindow = provider.longWindow {
                    HStack(spacing: 8) {
                        Text(longWindow.label)
                            .font(.system(size: 9))
                            .foregroundStyle(theme.labelColor)
                            .frame(width: 48, alignment: .leading)

                        WidgetProgressBar(
                            utilization: longWindow.utilization,
                            pace: longWindow.pace,
                            isLong: true
                        )

                        Text("\(Int(longWindow.utilization))%")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .monospacedDigit()
                            .foregroundStyle(theme.fillColor(for: longWindow.utilization, isLong: true))
                            .frame(width: 30, alignment: .trailing)
                    }
                }
            }
        }
    }
}

// MARK: - Share CTA

/// Subtle "Share Tokenomics" link shown when there's spare vertical space.
private struct ShareCTA: View {
    @Environment(\.widgetTheme) private var theme

    var body: some View {
        Link(destination: URL(string: "tokenomics://share")!) {
            HStack(spacing: 4) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 9))
                Text("Tokenomics")
                    .font(.caption2)
            }
            .foregroundStyle(theme.labelColor)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

// MARK: - No Data View

/// Shown when no provider data is available yet.
struct NoDataView: View {
    @Environment(\.widgetTheme) private var theme

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.title2)
                .foregroundStyle(theme.labelColor)
            Text("Open Tokenomics to sync")
                .font(.caption2)
                .foregroundStyle(theme.labelColor)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Shared Components

/// Themed horizontal progress bar with a pace tracker dot.
struct WidgetProgressBar: View {
    let utilization: Double
    let pace: Double
    var isLong: Bool = false

    @Environment(\.widgetTheme) private var theme

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Track
                Capsule()
                    .fill(theme.barTrack)
                    .frame(height: 4)

                // Fill
                Capsule()
                    .fill(theme.fillColor(for: utilization, isLong: isLong).opacity(theme.barFillOpacity))
                    .frame(
                        width: geometry.size.width * min(max(utilization / 100.0, 0), 1),
                        height: 4
                    )

                // Pace tracker dot — shows time elapsed through the window
                if pace > 0.02 {
                    let paceX = geometry.size.width * min(max(pace, 0), 1)
                    Circle()
                        .fill(theme.paceDotColor)
                        .frame(width: 4, height: 4)
                        .offset(x: paceX - 2)
                }
            }
        }
        .frame(height: 4)
    }
}

// MARK: - Shared Functions

/// Maps provider IDs to their icon asset base names.
private let iconBaseNames: [String: String] = [
    "claude": "Claude",
    "codex": "Codex",
    "copilot": "Copilot",
    "cursor": "Cursor",
    "gemini": "Gemini",
    "stableDiffusion": "stability",
    "midjourney": "midjourney",
    "runway": "runway",
    "elevenlabs": "elevenlabs",
    "suno": "suno",
    "udio": "udio"
]

/// Loads a provider icon PNG from the widget extension bundle.
/// Selects the correct variant via the theme's iconSuffix.
func providerIcon(_ id: String, theme: WidgetTheme) -> Image {
    let baseName = iconBaseNames[id] ?? id
    let name = "\(baseName)\(theme.iconSuffix)"
    if let nsImage = Bundle.main.image(forResource: name) {
        return Image(nsImage: nsImage)
    }
    return Image(systemName: "questionmark.square")
}

// MARK: - Previews (widget target only — use WidgetPreview.swift for main app canvas previews)

#if WIDGET_EXTENSION
#Preview("Small — Smart", as: .systemSmall) {
    TokenomicsWidget()
} timeline: {
    UsageEntry(date: .now, snapshot: .placeholder, selectedProvider: .smart)
}

#Preview("Small — Claude", as: .systemSmall) {
    TokenomicsWidget()
} timeline: {
    UsageEntry(date: .now, snapshot: .placeholder, selectedProvider: .claude)
}

#Preview("Medium", as: .systemMedium) {
    TokenomicsWidget()
} timeline: {
    UsageEntry(date: .now, snapshot: .placeholder, selectedProvider: .smart)
}

#Preview("Large", as: .systemLarge) {
    TokenomicsWidget()
} timeline: {
    UsageEntry(date: .now, snapshot: .placeholder, selectedProvider: .smart)
}

#Preview("No Data", as: .systemSmall) {
    TokenomicsWidget()
} timeline: {
    UsageEntry(date: .now, snapshot: nil, selectedProvider: .smart)
}
#endif
