import SwiftUI

/// Hero double-ring used on the welcome screen.
///
/// Geometry comes directly from `TokenomicsWidgetEntryView.swift:180-256`
/// (the small-widget renderer):
///   • outerDia = size × 0.61   (radius 33.5 at viewBox 110)
///   • innerDia = size × 0.46   (radius 25.3 at viewBox 110)
///   • lineW    = size × 0.07
///   • fontSize = size × 0.125  (centered percentage text)
///
/// Colors match the widget's blue ramp (not the app's accent), so the welcome
/// hero feels like the same product as the menu-bar widget the user will see
/// after onboarding completes.
struct WelcomeRingView: View {
    /// Outer ring fill fraction (0–1). Demo default = 0.7.
    var shortFraction: Double = 0.7
    /// Inner ring fill fraction (0–1). Demo default = 0.45.
    var longFraction: Double = 0.45
    /// Diameter in points. Welcome screen uses 165 (1.5× base 110).
    var size: CGFloat = 165

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let outerDia = size * 0.61
        let innerDia = size * 0.46
        let lineW    = size * 0.07
        let fontSize = size * 0.125

        ZStack {
            // Outer track + fill
            Circle()
                .stroke(trackColor, lineWidth: lineW)
                .frame(width: outerDia, height: outerDia)

            Circle()
                .trim(from: 0, to: clamped(shortFraction))
                .stroke(
                    shortColor,
                    style: StrokeStyle(lineWidth: lineW, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: outerDia, height: outerDia)

            // Inner track + fill
            Circle()
                .stroke(trackColor, lineWidth: lineW)
                .frame(width: innerDia, height: innerDia)

            Circle()
                .trim(from: 0, to: clamped(longFraction))
                .stroke(
                    longColor,
                    style: StrokeStyle(lineWidth: lineW, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: innerDia, height: innerDia)

            // Centered percentage — matches widget's `fontSize = size × 0.125`
            Text("\(Int(shortFraction * 100))%")
                .font(.system(size: fontSize, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(percentColor)
        }
        .frame(width: size, height: size)
    }

    // MARK: - Widget palette

    private var shortColor: Color {
        colorScheme == .dark
            ? Color(red: 117/255, green: 203/255, blue: 245/255)
            : Color(red: 47/255, green: 132/255, blue: 191/255)
    }

    private var longColor: Color {
        colorScheme == .dark
            ? Color(red: 51/255, green: 137/255, blue: 199/255)
            : Color(red: 86/255, green: 162/255, blue: 214/255)
    }

    private var trackColor: Color {
        colorScheme == .dark
            ? Color(red: 75/255, green: 166/255, blue: 210/255).opacity(0.25)
            : Color(red: 40/255, green: 97/255, blue: 149/255).opacity(0.12)
    }

    private var percentColor: Color { shortColor }

    private func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

#if DEBUG
#Preview("Light") {
    WelcomeRingView()
        .padding(40)
        .background(Color(red: 243/255, green: 239/255, blue: 229/255))
}

#Preview("Dark") {
    WelcomeRingView()
        .padding(40)
        .background(Color(red: 14/255, green: 51/255, blue: 77/255))
        .preferredColorScheme(.dark)
}
#endif
