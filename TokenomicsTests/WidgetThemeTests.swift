import XCTest
import SwiftUI
import WidgetKit
@testable import Tokenomics

// MARK: - Widget Theme Pinning Tests

/// Pins every color token in every WidgetTheme preset so accidental changes
/// to RGB values, opacities, or gradient stop locations fail immediately.
///
/// Color comparison strategy: SwiftUI Color doesn't implement Equatable in a
/// meaningful way for custom colors. We convert each Color to NSColor in the
/// sRGB color space and compare individual RGBA components to 4 decimal places
/// (≈ 0.4% channel tolerance — well under any perceptible change).
final class WidgetThemeTests: XCTestCase {

    // MARK: - Helpers

    /// Resolves a SwiftUI Color to sRGB components.
    /// Returns nil if the color can't be expressed in sRGB (e.g. semantic colors like .secondary).
    private func sRGB(_ color: Color) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)? {
        guard let ns = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        return (ns.redComponent, ns.greenComponent, ns.blueComponent, ns.alphaComponent)
    }

    private func assertChannel(
        _ actual: CGFloat,
        _ expected: CGFloat,
        label: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual, expected, accuracy: 0.0001, "\(label)", file: file, line: line)
    }

    private func assertColor(
        _ color: Color,
        r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat = 1.0,
        label: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard let components = sRGB(color) else {
            XCTFail("Could not resolve \(label) to sRGB — semantic color used where numeric expected", file: file, line: line)
            return
        }
        assertChannel(components.r, r / 255.0, label: "\(label).red", file: file, line: line)
        assertChannel(components.g, g / 255.0, label: "\(label).green", file: file, line: line)
        assertChannel(components.b, b / 255.0, label: "\(label).blue", file: file, line: line)
        assertChannel(components.a, a,          label: "\(label).alpha", file: file, line: line)
    }

    // MARK: - Dark Preset: Color Tokens

    func testDark_labelColor_rgb() {
        // Color(red: 117/255, green: 203/255, blue: 245/255).opacity(0.5)
        assertColor(WidgetTheme.dark.labelColor,
                    r: 117, g: 203, b: 245, a: 0.5,
                    label: "dark.labelColor")
    }

    func testDark_shortColor_rgb() {
        // Color(red: 117/255, green: 203/255, blue: 245/255)
        assertColor(WidgetTheme.dark.shortColor,
                    r: 117, g: 203, b: 245, a: 1.0,
                    label: "dark.shortColor")
    }

    func testDark_longColor_rgb() {
        // Color(red: 51/255, green: 137/255, blue: 199/255)
        assertColor(WidgetTheme.dark.longColor,
                    r: 51, g: 137, b: 199, a: 1.0,
                    label: "dark.longColor")
    }

    func testDark_barTrack_rgb() {
        // Color(red: 75/255, green: 166/255, blue: 210/255).opacity(0.25)
        assertColor(WidgetTheme.dark.barTrack,
                    r: 75, g: 166, b: 210, a: 0.25,
                    label: "dark.barTrack")
    }

    func testDark_barFillOpacity() {
        XCTAssertEqual(WidgetTheme.dark.barFillOpacity, 1.0)
    }

    func testDark_iconSuffix() {
        XCTAssertEqual(WidgetTheme.dark.iconSuffix, "-white")
    }

    func testDark_paceDotColor_isWhite() {
        // .white — semantic, but we can verify it resolves to full-white sRGB
        assertColor(WidgetTheme.dark.paceDotColor,
                    r: 255, g: 255, b: 255, a: 1.0,
                    label: "dark.paceDotColor")
    }

    // MARK: - Dark Preset: Gradient Stops

    func testDark_gradientStops_count() {
        XCTAssertEqual(WidgetTheme.dark.gradientStops.count, 2)
    }

    func testDark_gradientStop0_location() {
        // location: 0.103
        XCTAssertEqual(WidgetTheme.dark.gradientStops[0].location, 0.103, accuracy: 0.0001)
    }

    func testDark_gradientStop0_color() {
        // Color(red: 14/255, green: 51/255, blue: 77/255)
        assertColor(WidgetTheme.dark.gradientStops[0].color,
                    r: 14, g: 51, b: 77, a: 1.0,
                    label: "dark.gradientStops[0].color")
    }

    func testDark_gradientStop1_location() {
        // location: 0.881
        XCTAssertEqual(WidgetTheme.dark.gradientStops[1].location, 0.881, accuracy: 0.0001)
    }

    func testDark_gradientStop1_color() {
        // Color(red: 5/255, green: 25/255, blue: 40/255)
        assertColor(WidgetTheme.dark.gradientStops[1].color,
                    r: 5, g: 25, b: 40, a: 1.0,
                    label: "dark.gradientStops[1].color")
    }

    // MARK: - Light Preset: Color Tokens

    func testLight_labelColor_rgb() {
        // Color(red: 47/255, green: 132/255, blue: 191/255).opacity(0.67)
        assertColor(WidgetTheme.light.labelColor,
                    r: 47, g: 132, b: 191, a: 0.67,
                    label: "light.labelColor")
    }

    func testLight_shortColor_rgb() {
        // Color(red: 47/255, green: 132/255, blue: 191/255)
        assertColor(WidgetTheme.light.shortColor,
                    r: 47, g: 132, b: 191, a: 1.0,
                    label: "light.shortColor")
    }

    func testLight_longColor_rgb() {
        // Color(red: 86/255, green: 162/255, blue: 214/255)
        assertColor(WidgetTheme.light.longColor,
                    r: 86, g: 162, b: 214, a: 1.0,
                    label: "light.longColor")
    }

    func testLight_barTrack_rgb() {
        // Color(red: 40/255, green: 97/255, blue: 149/255).opacity(0.12)
        assertColor(WidgetTheme.light.barTrack,
                    r: 40, g: 97, b: 149, a: 0.12,
                    label: "light.barTrack")
    }

    func testLight_barFillOpacity() {
        XCTAssertEqual(WidgetTheme.light.barFillOpacity, 1.0)
    }

    func testLight_iconSuffix() {
        XCTAssertEqual(WidgetTheme.light.iconSuffix, "-d.blue")
    }

    func testLight_paceDotColor_rgb() {
        // Color(red: 14/255, green: 51/255, blue: 77/255)
        assertColor(WidgetTheme.light.paceDotColor,
                    r: 14, g: 51, b: 77, a: 1.0,
                    label: "light.paceDotColor")
    }

    // MARK: - Light Preset: Gradient Stops

    func testLight_gradientStops_count() {
        XCTAssertEqual(WidgetTheme.light.gradientStops.count, 2)
    }

    func testLight_gradientStop0_location() {
        // location: 0.016
        XCTAssertEqual(WidgetTheme.light.gradientStops[0].location, 0.016, accuracy: 0.0001)
    }

    func testLight_gradientStop0_color() {
        // Color(red: 243/255, green: 239/255, blue: 229/255)
        assertColor(WidgetTheme.light.gradientStops[0].color,
                    r: 243, g: 239, b: 229, a: 1.0,
                    label: "light.gradientStops[0].color")
    }

    func testLight_gradientStop1_location() {
        // location: 0.845
        XCTAssertEqual(WidgetTheme.light.gradientStops[1].location, 0.845, accuracy: 0.0001)
    }

    func testLight_gradientStop1_color() {
        // Color(red: 230/255, green: 224/255, blue: 212/255)
        assertColor(WidgetTheme.light.gradientStops[1].color,
                    r: 230, g: 224, b: 212, a: 1.0,
                    label: "light.gradientStops[1].color")
    }

    // MARK: - Accented Preset: Non-Numeric Tokens

    // Accented uses semantic colors (.secondary, .white) that aren't stable
    // sRGB values — we pin the non-color properties and the structural facts.

    func testAccented_barFillOpacity() {
        XCTAssertEqual(WidgetTheme.accented.barFillOpacity, 0.6)
    }

    func testAccented_iconSuffix() {
        XCTAssertEqual(WidgetTheme.accented.iconSuffix, "-white")
    }

    func testAccented_gradientStops_isEmpty() {
        // Accented has no gradient — widget host provides the background
        XCTAssertTrue(WidgetTheme.accented.gradientStops.isEmpty)
    }

    // MARK: - Resolver Tests

    // WidgetTheme.current(for:renderingMode:) always returns .dark or .light
    // based solely on ColorScheme — renderingMode is intentionally ignored
    // (see comment in source: accented preset was retired).

    func testResolver_darkScheme_fullColor_returnsDark() {
        let theme = WidgetTheme.current(for: .dark, renderingMode: .fullColor)
        // The dark preset's shortColor RGB is 117/203/245 — unique to .dark
        assertColor(theme.shortColor, r: 117, g: 203, b: 245, a: 1.0,
                    label: "resolver(.dark,.fullColor).shortColor")
    }

    func testResolver_darkScheme_accented_returnsDark() {
        let theme = WidgetTheme.current(for: .dark, renderingMode: .accented)
        assertColor(theme.shortColor, r: 117, g: 203, b: 245, a: 1.0,
                    label: "resolver(.dark,.accented).shortColor")
    }

    func testResolver_darkScheme_vibrant_returnsDark() {
        let theme = WidgetTheme.current(for: .dark, renderingMode: .vibrant)
        assertColor(theme.shortColor, r: 117, g: 203, b: 245, a: 1.0,
                    label: "resolver(.dark,.vibrant).shortColor")
    }

    func testResolver_lightScheme_fullColor_returnsLight() {
        let theme = WidgetTheme.current(for: .light, renderingMode: .fullColor)
        // The light preset's shortColor RGB is 47/132/191 — unique to .light
        assertColor(theme.shortColor, r: 47, g: 132, b: 191, a: 1.0,
                    label: "resolver(.light,.fullColor).shortColor")
    }

    func testResolver_lightScheme_accented_returnsLight() {
        let theme = WidgetTheme.current(for: .light, renderingMode: .accented)
        assertColor(theme.shortColor, r: 47, g: 132, b: 191, a: 1.0,
                    label: "resolver(.light,.accented).shortColor")
    }

    func testResolver_lightScheme_vibrant_returnsLight() {
        let theme = WidgetTheme.current(for: .light, renderingMode: .vibrant)
        assertColor(theme.shortColor, r: 47, g: 132, b: 191, a: 1.0,
                    label: "resolver(.light,.vibrant).shortColor")
    }

    // MARK: - Fill Color Boundary Tests (dark preset)

    func testFillColor_zeroUtilization_notLong_returnsShortColor() {
        // fillColor(for:) always returns shortColor or longColor regardless of utilization value
        let fill = WidgetTheme.dark.fillColor(for: 0.0, isLong: false)
        assertColor(fill, r: 117, g: 203, b: 245, a: 1.0,
                    label: "dark.fillColor(0%, isLong:false)")
    }

    func testFillColor_hundredUtilization_notLong_returnsShortColor() {
        let fill = WidgetTheme.dark.fillColor(for: 100.0, isLong: false)
        assertColor(fill, r: 117, g: 203, b: 245, a: 1.0,
                    label: "dark.fillColor(100%, isLong:false)")
    }

    func testFillColor_overHundred_notLong_returnsShortColor() {
        let fill = WidgetTheme.dark.fillColor(for: 150.0, isLong: false)
        assertColor(fill, r: 117, g: 203, b: 245, a: 1.0,
                    label: "dark.fillColor(150%, isLong:false)")
    }

    func testFillColor_zeroUtilization_isLong_returnsLongColor() {
        let fill = WidgetTheme.dark.fillColor(for: 0.0, isLong: true)
        assertColor(fill, r: 51, g: 137, b: 199, a: 1.0,
                    label: "dark.fillColor(0%, isLong:true)")
    }

    func testFillColor_hundredUtilization_isLong_returnsLongColor() {
        let fill = WidgetTheme.dark.fillColor(for: 100.0, isLong: true)
        assertColor(fill, r: 51, g: 137, b: 199, a: 1.0,
                    label: "dark.fillColor(100%, isLong:true)")
    }

    func testFillColor_defaultIsLong_isFalse() {
        // fillColor(for:) default is isLong: false — should return shortColor
        let fillDefault = WidgetTheme.dark.fillColor(for: 50.0)
        let fillExplicit = WidgetTheme.dark.fillColor(for: 50.0, isLong: false)
        // Both resolve to the same sRGB values
        guard let def = sRGB(fillDefault), let exp = sRGB(fillExplicit) else {
            XCTFail("Could not resolve colors")
            return
        }
        assertChannel(def.r, exp.r, label: "fillColor default isLong:false red")
        assertChannel(def.g, exp.g, label: "fillColor default isLong:false green")
        assertChannel(def.b, exp.b, label: "fillColor default isLong:false blue")
    }
}
