import SwiftUI

/// Renders a provider's vector icon at a given size with the standard 6pt-radius
/// separator-bordered tile treatment used throughout the app.
///
/// Asset lookup matches `AIConnectionsView`'s legacy `providerIcon(for:)`:
/// `<iconBaseName>-black.svg` in light mode, `<iconBaseName>-white.svg` in dark.
/// The base name comes from `ProviderId.iconBaseName`.
///
/// Usage:
/// ```swift
/// ProviderIcon(provider: .cursor)            // 26pt tile, 16pt icon
/// ProviderIcon(provider: .claude, size: .lg) // 44pt tile, 26pt icon
/// ```
struct ProviderIcon: View {
    let provider: ProviderId
    var size: Size = .standard
    var isConnected: Bool = false
    var isDimmed: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.tokenomicsTextSize) private var textSize

    enum Size {
        /// 26pt tile, 16pt icon — the row-row default used in AIConnectionsView/OnboardingView.
        case standard
        /// 44pt tile, 26pt icon — used in connector hero rows.
        case lg

        var tilePoints: CGFloat {
            switch self {
            case .standard: return 26
            case .lg: return 44
            }
        }
        var iconPoints: CGFloat {
            switch self {
            case .standard: return 16
            case .lg: return 26
            }
        }
        var cornerRadius: CGFloat {
            switch self {
            case .standard: return 6
            case .lg: return 9
            }
        }
    }

    var body: some View {
        let scale = textSize.iconScale
        let tile = size.tilePoints * scale
        let icon = size.iconPoints * scale
        let radius = size.cornerRadius

        ZStack {
            image
                .resizable()
                .scaledToFit()
                .frame(width: icon, height: icon)
        }
        .frame(width: tile, height: tile)
        .background(isConnected ? Color(nsColor: .quaternaryLabelColor) : .clear)
        .overlay(
            RoundedRectangle(cornerRadius: radius)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: radius))
        .opacity(isDimmed ? 0.3 : 1.0)
    }

    private var image: Image {
        let suffix = colorScheme == .dark ? "-white" : "-black"
        let name = "\(provider.iconBaseName)\(suffix)"
        if let nsImage = NSImage(named: name) {
            return Image(nsImage: nsImage)
        }
        return Image(systemName: "sparkles")
    }
}
