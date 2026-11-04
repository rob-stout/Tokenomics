import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Tokens
//
// Source of truth: trytokenomics-site/design-system.md (sections 02–05).
// Mirrors design-system-v3.html. Anti-patterns: see section "Anti-patterns
// (Swift)" in the MD — never reach for `Color.accentColor`, `.body`,
// `Color(.controlBackgroundColor)`, etc. Every value below comes from the MD;
// do not improvise.
//
// Two ways to consume theme-aware colors (pick one per view):
//   1. Tokens.Color.text(scheme)   — explicit ColorScheme arg, type-safe.
//      Requires `@Environment(\.colorScheme) var scheme` in the view.
//   2. Tokens.DynamicColor.text    — auto-flips via dynamic NSColor.
//      Cleaner view code, resolves at draw time, macOS-only.
//
// Raw brand constants (Tokens.Color.brand600, .cream100, .ink800) never flip —
// use them for surfaces tied to a specific WidgetTheme or static brand fills.

enum Tokens {

    // MARK: - Color

    enum Color {
        // ─── Brand ramp (navy → cyan) ───
        static let ink900 = SwiftUI.Color(red:   5/255, green:  25/255, blue:  40/255) // #051928
        static let ink800 = SwiftUI.Color(red:  14/255, green:  51/255, blue:  77/255) // #0E334D
        static let ink700 = SwiftUI.Color(red:  40/255, green:  97/255, blue: 149/255) // #286195

        static let brand600 = SwiftUI.Color(red:  47/255, green: 132/255, blue: 191/255) // #2F84BF
        static let brand500 = SwiftUI.Color(red:  51/255, green: 137/255, blue: 199/255) // #3389C7
        static let brand400 = SwiftUI.Color(red:  75/255, green: 166/255, blue: 210/255) // #4BA6D2
        static let brand300 = SwiftUI.Color(red:  86/255, green: 162/255, blue: 214/255) // #56A2D6
        static let brand200 = SwiftUI.Color(red: 117/255, green: 203/255, blue: 245/255) // #75CBF5

        // ─── Cream ramp (paper) ───
        static let cream50  = SwiftUI.Color(red: 243/255, green: 239/255, blue: 229/255) // #F3EFE5
        static let cream100 = SwiftUI.Color(red: 230/255, green: 224/255, blue: 212/255) // #E6E0D4
        static let cream200 = SwiftUI.Color(red: 217/255, green: 209/255, blue: 192/255) // #D9D1C0

        static let white = SwiftUI.Color.white

        // ─── Semantic ramps ───
        static let successLight = SwiftUI.Color(red:  47/255, green: 143/255, blue:  79/255) // #2F8F4F
        static let warningLight = SwiftUI.Color(red: 194/255, green: 106/255, blue:  31/255) // #C26A1F (burnt amber, not yellow)
        static let dangerLight  = SwiftUI.Color(red: 179/255, green:  58/255, blue:  58/255) // #B33A3A

        static let successDark  = SwiftUI.Color(red: 111/255, green: 209/255, blue: 138/255) // #6FD18A
        static let warningDark  = SwiftUI.Color(red: 226/255, green: 167/255, blue: 101/255) // #E2A765
        static let dangerDark   = SwiftUI.Color(red: 226/255, green: 119/255, blue: 119/255) // #E27777

        // ─── Light-theme raw values (input to the accessors below) ───
        // View code should NOT reference these directly — use the accessors.
        fileprivate static let _textLight         = ink800
        fileprivate static let _textMutedLight    = ink800.opacity(0.64)
        fileprivate static let _textSubtleLight   = ink800.opacity(0.44)
        fileprivate static let _bgLight           = cream50
        fileprivate static let _bg2Light          = cream100
        fileprivate static let _surfaceLight      = SwiftUI.Color.white
        fileprivate static let _surface2Light     = SwiftUI.Color(red: 251/255, green: 248/255, blue: 241/255) // #FBF8F1
        fileprivate static let _borderLight       = ink800.opacity(0.12)
        fileprivate static let _borderStrongLight = ink800.opacity(0.22)
        fileprivate static let _accentLight       = brand600
        fileprivate static let _accentInkLight    = ink800

        // ─── Dark-theme raw values ───
        fileprivate static let _textDark          = SwiftUI.Color(red: 230/255, green: 238/255, blue: 246/255) // #E6EEF6
        fileprivate static let _textMutedDark     = SwiftUI.Color(red: 230/255, green: 238/255, blue: 246/255).opacity(0.68)
        fileprivate static let _textSubtleDark    = SwiftUI.Color(red: 230/255, green: 238/255, blue: 246/255).opacity(0.44)
        fileprivate static let _bgDark            = SwiftUI.Color(red:   7/255, green:  16/255, blue:  26/255) // #07101a
        fileprivate static let _bg2Dark           = SwiftUI.Color(red:  11/255, green:  26/255, blue:  41/255) // #0b1a29
        fileprivate static let _surfaceDark       = ink800
        fileprivate static let _surface2Dark      = SwiftUI.Color(red:  10/255, green:  36/255, blue:  57/255) // #0a2439
        fileprivate static let _borderDark        = SwiftUI.Color.white.opacity(0.10)
        fileprivate static let _borderStrongDark  = SwiftUI.Color.white.opacity(0.22)
        fileprivate static let _accentDark        = brand200
        // accentInk in dark = brand200 (cyan), per the mockup .btn-primary CSS
        // (guided-onboarding-mockup.html line 364:
        //   [data-theme="dark"] .btn-primary { background: var(--brand-200); })
        // The MD drop-in had this wired to _textDark, which contradicted its
        // own doc comment ("Dark mode = brand-200 (cyan on navy)"). Mockup wins.
        fileprivate static let _accentInkDark     = brand200

        // ─────────────────────────────────────────────────────────────────
        // PUBLIC THEME-RESOLVED ACCESSORS
        //   @Environment(\.colorScheme) var scheme
        //   .foregroundStyle(Tokens.Color.text(scheme))
        // ─────────────────────────────────────────────────────────────────

        // Surfaces
        static func bg(_ scheme: ColorScheme)       -> SwiftUI.Color { scheme == .dark ? _bgDark       : _bgLight }
        static func bg2(_ scheme: ColorScheme)      -> SwiftUI.Color { scheme == .dark ? _bg2Dark      : _bg2Light }
        static func surface(_ scheme: ColorScheme)  -> SwiftUI.Color { scheme == .dark ? _surfaceDark  : _surfaceLight }
        /// Hover surface — unified across all hovers (button-secondary, copy, in-field, etc.)
        static func surface2(_ scheme: ColorScheme) -> SwiftUI.Color { scheme == .dark ? _surface2Dark : _surface2Light }

        // Text
        static func text(_ scheme: ColorScheme)        -> SwiftUI.Color { scheme == .dark ? _textDark       : _textLight }
        static func textMuted(_ scheme: ColorScheme)   -> SwiftUI.Color { scheme == .dark ? _textMutedDark  : _textMutedLight }
        static func textSubtle(_ scheme: ColorScheme)  -> SwiftUI.Color { scheme == .dark ? _textSubtleDark : _textSubtleLight }

        // Borders
        static func border(_ scheme: ColorScheme)        -> SwiftUI.Color { scheme == .dark ? _borderDark       : _borderLight }
        static func borderStrong(_ scheme: ColorScheme)  -> SwiftUI.Color { scheme == .dark ? _borderStrongDark : _borderStrongLight }

        // Accents — flips brand-600 (light) ↔ brand-200 (dark)
        static func accent(_ scheme: ColorScheme)    -> SwiftUI.Color { scheme == .dark ? _accentDark    : _accentLight }
        /// Used for the Primary button's *fill*. Light = ink-800 (navy on cream), dark = brand-200 (cyan on navy).
        static func accentInk(_ scheme: ColorScheme) -> SwiftUI.Color { scheme == .dark ? _accentInkDark : _accentInkLight }

        // Semantic
        static func success(_ scheme: ColorScheme) -> SwiftUI.Color { scheme == .dark ? successDark : successLight }
        static func warning(_ scheme: ColorScheme) -> SwiftUI.Color { scheme == .dark ? warningDark : warningLight }
        static func danger(_ scheme: ColorScheme)  -> SwiftUI.Color { scheme == .dark ? dangerDark  : dangerLight }
    }

    // MARK: - DynamicColor (auto-flipping NSColor wrapper)
    //
    // Same tokens, but resolve at draw time. No `colorScheme` plumbing through
    // view bodies. Use these for terse view code; use the `Color.text(scheme)`
    // accessors when you also need scheme for sibling logic in the same view.

    enum DynamicColor {
        static let text         = dynamic(light: Color._textLight,         dark: Color._textDark)
        static let textMuted    = dynamic(light: Color._textMutedLight,    dark: Color._textMutedDark)
        static let textSubtle   = dynamic(light: Color._textSubtleLight,   dark: Color._textSubtleDark)
        static let bg           = dynamic(light: Color._bgLight,           dark: Color._bgDark)
        static let bg2          = dynamic(light: Color._bg2Light,          dark: Color._bg2Dark)
        static let surface      = dynamic(light: Color._surfaceLight,      dark: Color._surfaceDark)
        static let surface2     = dynamic(light: Color._surface2Light,     dark: Color._surface2Dark)
        static let border       = dynamic(light: Color._borderLight,       dark: Color._borderDark)
        static let borderStrong = dynamic(light: Color._borderStrongLight, dark: Color._borderStrongDark)
        static let accent       = dynamic(light: Color._accentLight,       dark: Color._accentDark)
        static let accentInk    = dynamic(light: Color._accentInkLight,    dark: Color._accentInkDark)
        static let success      = dynamic(light: Color.successLight,       dark: Color.successDark)
        static let warning      = dynamic(light: Color.warningLight,       dark: Color.warningDark)
        static let danger       = dynamic(light: Color.dangerLight,        dark: Color.dangerDark)

        private static func dynamic(light: SwiftUI.Color, dark: SwiftUI.Color) -> SwiftUI.Color {
            #if canImport(AppKit)
            return SwiftUI.Color(nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
                return NSColor(isDark ? dark : light)
            })
            #else
            return light
            #endif
        }
    }

    // MARK: - Spacing (8pt grid)

    enum Spacing {
        static let s1: CGFloat = 4
        static let s2: CGFloat = 8
        static let s3: CGFloat = 12
        static let s4: CGFloat = 16
        static let s5: CGFloat = 24
        static let s6: CGFloat = 32
        static let s7: CGFloat = 48
        static let s8: CGFloat = 64
        static let s9: CGFloat = 96
    }

    // MARK: - Radius

    enum Radius {
        static let xs: CGFloat   = 6   // buttons-in-field
        static let sm: CGFloat   = 10  // small chips, inputs
        static let md: CGFloat   = 14  // cards, install-block, FAQ items
        static let lg: CGFloat   = 20  // section cards, principle blocks
        static let xl: CGFloat   = 28  // hero / featured surfaces
        static let pill: CGFloat = 999 // pills, capsule progress bars, primary buttons
    }

    // MARK: - Typography
    //
    // Three type systems, by surface (MD section 03):
    //   Onboarding wizard → Hedvig + DM Sans (bundled)
    //   Popover / Settings → SF Pro via .system(...)
    //   Widget → SF Pro via WidgetKit caption styles
    //
    // Quick decision rule (MD line 531): if the user is in the guided onboarding
    // flow (window with stepper), use `Onboarding.*`. Otherwise `App.*` /
    // `Widget.*`.

    enum Typography {

        // Onboarding wizard — Hedvig (H1) + DM Sans (UI/body).
        // Both fonts are bundled at Resources/Fonts/ and auto-registered via
        // ATSApplicationFontsPath in Info.plist. PostScript family names
        // verified from the binaries: "Hedvig Letters Serif" and "DM Sans".
        // Variable fonts — apply weight via `.weight(...)` rather than
        // per-instance PostScript names.
        enum Onboarding {
            /// "OpenAI is connected." — Welcome + Done celebration.
            static let h1 = SwiftUI.Font.custom("Hedvig Letters Serif", size: 30)

            /// "Couldn't install the Codex CLI" — every flow-screen headline.
            static let h2 = SwiftUI.Font.custom("DM Sans", size: 22).weight(.semibold)

            /// Inline section heads.
            static let h3 = SwiftUI.Font.custom("DM Sans", size: 17).weight(.semibold)

            /// Subheadline body under a headline (`.lede`).
            static let lede = SwiftUI.Font.custom("DM Sans", size: 15)

            /// Default body.
            static let body = SwiftUI.Font.custom("DM Sans", size: 14)

            /// Captions, helpers.
            static let small = SwiftUI.Font.custom("DM Sans", size: 13)

            /// Step labels, badges, group labels.
            static let micro = SwiftUI.Font.custom("DM Sans", size: 11).weight(.medium)

            /// Number inside the .step-mark circle.
            static let stepperNumber = SwiftUI.Font.custom("DM Sans", size: 11).weight(.semibold)

            /// Centered titlebar text.
            static let windowTitle = SwiftUI.Font.custom("DM Sans", size: 13).weight(.medium)
        }

        // Popover / Settings — SF Pro (system). Never `.body`/`.title`/etc.
        // (those pull dynamic type and break design intent).
        enum App {
            /// Popover section headers.
            static let sectionTitle = SwiftUI.Font.system(size: 14, weight: .semibold)

            /// Most popover/settings text.
            static let body = SwiftUI.Font.system(size: 13, weight: .regular)

            /// Status text, labels.
            static let caption = SwiftUI.Font.system(size: 12, weight: .medium)

            /// Provider scopes, "Updated just now".
            static let tiny = SwiftUI.Font.system(size: 11, weight: .regular)

            /// UPPERCASE section labels (popover).
            static let micro = SwiftUI.Font.system(size: 10.5, weight: .semibold)
        }

        // Widget — pulled from TokenomicsWidgetEntryView.swift.
        enum Widget {
            /// "Tokenomics" header (12pt semibold).
            static let caption = SwiftUI.Font.caption.weight(.semibold)

            /// Relative time, plan label (11pt regular).
            static let caption2 = SwiftUI.Font.caption2

            /// Bar-row labels, ShareCTA arrow (9pt).
            static let tiny = SwiftUI.Font.system(size: 9)
        }
    }

    // MARK: - Motion

    enum Motion {
        static let fast: Double     = 0.12 // hover states
        static let standard: Double = 0.22 // default
        static let slow: Double     = 0.42 // scroll-enter, card reveals

        /// Default easing — matches CSS cubic-bezier(.2,.7,.2,1).
        static let ease = Animation.timingCurve(0.2, 0.7, 0.2, 1, duration: standard)

        // Per-behavior curves — docs/brand/tokenomics-brand-guidelines.html,
        // "Motion rules" table. All custom motion is skipped under Reduce Motion.

        /// Bars: width 0→final, 500ms, cubic-bezier(.25,.46,.45,.94).
        static let barFill = Animation.timingCurve(0.25, 0.46, 0.45, 0.94, duration: 0.5)
        /// Pace dot rides in with the fill on the same curve but slower, so it
        /// trails the fill and lands last — that last beat draws the eye to it.
        static let paceSlide = Animation.timingCurve(0.25, 0.46, 0.45, 0.94, duration: 0.8)
        /// Refresh button: one full turn per refresh. Fetches are near-instant,
        /// so a single turn reads as "done" rather than an open-ended spinner.
        static let refreshSpin = Animation.easeOut(duration: 0.6)

        /// Success pop (onboarding "connected"): scale 0.6 → 1.15 → 0.95 → 1.
        /// Not in the brand table — app-only value, added with this motion pass.
        static let successPopScales: [(scale: CGFloat, duration: Double)] = [
            (1.15, 0.18), (0.95, 0.12), (1.0, 0.12)
        ]
        static let successPopStart: CGFloat = 0.6

        /// Confetti on the onboarding "connected" screen. Tuned by Rob in the
        /// HTML motion study (2026-10-29); units are points and seconds in the
        /// 680pt-wide onboarding window.
        enum Confetti {
            static let originX: CGFloat = 0.5    // fraction of width
            static let originY: CGFloat = 0      // fraction of height (top edge)
            static let depth: Double = 0.2       // how far pieces pop toward the viewer
            static let aimDegrees: Double = 0    // 0° = up
            static let spreadDegrees: Double = 360
            static let pop: Double = 800         // max launch speed, pt/s
            static let gravity: Double = 1100    // pt/s²
            static let drag: Double = 0.4        // linear air drag, 1/s
            static let emitDuration: Double = 0.14
            static let density: Double = 1680    // pieces per second (235 total)
        }
    }
}

// MARK: - Previews

private struct BrandSwatch: Identifiable {
    let id: String
    let color: SwiftUI.Color
}

private let brandConstants: [BrandSwatch] = [
    .init(id: "ink900",   color: Tokens.Color.ink900),
    .init(id: "ink800",   color: Tokens.Color.ink800),
    .init(id: "ink700",   color: Tokens.Color.ink700),
    .init(id: "brand600", color: Tokens.Color.brand600),
    .init(id: "brand500", color: Tokens.Color.brand500),
    .init(id: "brand400", color: Tokens.Color.brand400),
    .init(id: "brand300", color: Tokens.Color.brand300),
    .init(id: "brand200", color: Tokens.Color.brand200),
    .init(id: "cream50",  color: Tokens.Color.cream50),
    .init(id: "cream100", color: Tokens.Color.cream100),
    .init(id: "cream200", color: Tokens.Color.cream200),
]

#Preview("Brand constants") {
    ScrollView {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s2) {
            ForEach(brandConstants) { swatch in
                HStack(spacing: Tokens.Spacing.s3) {
                    RoundedRectangle(cornerRadius: Tokens.Radius.xs)
                        .fill(swatch.color)
                        .frame(width: 60, height: 32)
                        .overlay(
                            RoundedRectangle(cornerRadius: Tokens.Radius.xs)
                                .stroke(Tokens.DynamicColor.border, lineWidth: 1)
                        )
                    Text(swatch.id).font(Tokens.Typography.Onboarding.small)
                }
            }
        }
        .padding(Tokens.Spacing.s5)
    }
    .frame(width: 320, height: 480)
    .background(Tokens.DynamicColor.bg)
}

#Preview("Theme tokens — light") {
    themeTokenGrid(scheme: .light)
        .frame(width: 360, height: 520)
        .preferredColorScheme(.light)
}

#Preview("Theme tokens — dark") {
    themeTokenGrid(scheme: .dark)
        .preferredColorScheme(.dark)
        .frame(width: 360, height: 520)
}

@ViewBuilder
private func themeTokenGrid(scheme: ColorScheme) -> some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.s3) {
        Group {
            themeRow("bg",            color: Tokens.Color.bg(scheme))
            themeRow("bg2",           color: Tokens.Color.bg2(scheme))
            themeRow("surface",       color: Tokens.Color.surface(scheme))
            themeRow("surface2",      color: Tokens.Color.surface2(scheme))
            themeRow("border",        color: Tokens.Color.border(scheme))
            themeRow("borderStrong",  color: Tokens.Color.borderStrong(scheme))
            themeRow("text",          color: Tokens.Color.text(scheme))
            themeRow("textMuted",     color: Tokens.Color.textMuted(scheme))
            themeRow("textSubtle",    color: Tokens.Color.textSubtle(scheme))
        }
        Group {
            themeRow("accent",        color: Tokens.Color.accent(scheme))
            themeRow("accentInk",     color: Tokens.Color.accentInk(scheme))
            themeRow("success",       color: Tokens.Color.success(scheme))
            themeRow("warning",       color: Tokens.Color.warning(scheme))
            themeRow("danger",        color: Tokens.Color.danger(scheme))
        }
    }
    .padding(Tokens.Spacing.s5)
    .background(Tokens.Color.bg(scheme))
}

@ViewBuilder
private func themeRow(_ name: String, color: SwiftUI.Color) -> some View {
    HStack(spacing: Tokens.Spacing.s3) {
        RoundedRectangle(cornerRadius: Tokens.Radius.xs)
            .fill(color)
            .frame(width: 60, height: 28)
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Radius.xs)
                    .stroke(Tokens.DynamicColor.border, lineWidth: 1)
            )
        Text(name).font(Tokens.Typography.Onboarding.small)
    }
}

#Preview("Onboarding typography") {
    VStack(alignment: .leading, spacing: Tokens.Spacing.s4) {
        Text("OpenAI is connected.").font(Tokens.Typography.Onboarding.h1)
        Text("Install Homebrew").font(Tokens.Typography.Onboarding.h2)
        Text("Tokenomics will run:").font(Tokens.Typography.Onboarding.h3)
        Text("Tokenomics needs Homebrew to install Node.js.")
            .font(Tokens.Typography.Onboarding.lede)
        Text("Body copy default size.").font(Tokens.Typography.Onboarding.body)
        Text("Helper / sublabel text.").font(Tokens.Typography.Onboarding.small)
        Text("MICRO LABEL").font(Tokens.Typography.Onboarding.micro).tracking(1.5)
    }
    .foregroundStyle(Tokens.DynamicColor.text)
    .padding(Tokens.Spacing.s5)
    .background(Tokens.DynamicColor.bg)
    .frame(width: 360, height: 360)
}
