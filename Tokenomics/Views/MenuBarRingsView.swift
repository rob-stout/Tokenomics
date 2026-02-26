import SwiftUI
import AppKit

/// Renders two concentric utilization rings as an NSImage for the MenuBarExtra label.
///
/// Geometry matches the Figma component "usage-animation" (44x44px @2x = 22x22pt).
/// All drawing uses pt coordinates — CoreGraphics scales to @2x pixels automatically.
enum MenuBarRingsRenderer {

    // Extra transparent space on the right so the gap between
    // rings and percentage text survives MenuBarExtra layout compression.
    private static let trailingPadding: CGFloat = 6

    static func image(
        fiveHourFraction: Double,
        sevenDayFraction: Double,
        fiveHourPace: Double,
        sevenDayPace: Double
    ) -> NSImage {
        let ptSize: CGFloat = 22
        let pxSize: CGFloat = 44
        let totalPtWidth = ptSize + trailingPadding
        let totalPxWidth = pxSize + trailingPadding * 2

        let image = NSImage(size: NSSize(width: totalPtWidth, height: ptSize))
        image.addRepresentation(render(
            pxWidth: totalPxWidth, pxHeight: pxSize, ptWidth: totalPtWidth, ptHeight: ptSize,
            fiveHourFraction: fiveHourFraction,
            sevenDayFraction: sevenDayFraction,
            fiveHourPace: fiveHourPace,
            sevenDayPace: sevenDayPace
        ))
        image.isTemplate = true
        return image
    }

    // MARK: - Private

    private static func render(
        pxWidth: CGFloat, pxHeight: CGFloat, ptWidth: CGFloat, ptHeight: CGFloat,
        fiveHourFraction: Double,
        sevenDayFraction: Double,
        fiveHourPace: Double,
        sevenDayPace: Double
    ) -> NSBitmapImageRep {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(pxWidth),
            pixelsHigh: Int(pxHeight),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return NSBitmapImageRep()
        }
        rep.size = NSSize(width: ptWidth, height: ptHeight)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        guard let ctx = NSGraphicsContext.current?.cgContext else {
            NSGraphicsContext.restoreGraphicsState()
            return rep
        }

        // Drawing in pt — CG scales to @2x pixels via the rep's size/pixel ratio.
        // Figma values halved: 44px → 22pt, r=18 → 9, r=11 → 5.5, stroke=6 → 3
        // Rings centered in the left 22pt square; right side is transparent padding.
        let ringSize: CGFloat = 22
        let center = CGPoint(x: ringSize / 2, y: ptHeight / 2)
        let outerRadius: CGFloat = 9       // Figma: 18px
        let innerRadius: CGFloat = 5.5     // Figma: 11px
        let strokeWidth: CGFloat = 3       // Figma: 6px
        let paceDotRadius: CGFloat = 1.375 // Figma: 2.75px

        let trackAlpha: CGFloat = 0.15
        let outerFillAlpha: CGFloat = 0.40
        let innerFillAlpha: CGFloat = 0.50

        // --- Tracks (full circles) ---
        drawArc(in: ctx, center: center, radius: outerRadius,
                fraction: 1.0, strokeWidth: strokeWidth,
                color: CGColor(gray: 1, alpha: trackAlpha), roundCap: false)
        drawArc(in: ctx, center: center, radius: innerRadius,
                fraction: 1.0, strokeWidth: strokeWidth,
                color: CGColor(gray: 1, alpha: trackAlpha), roundCap: false)

        // --- Fill arcs ---
        drawArc(in: ctx, center: center, radius: outerRadius,
                fraction: clamp(sevenDayFraction), strokeWidth: strokeWidth,
                color: CGColor(gray: 1, alpha: outerFillAlpha), roundCap: true)
        drawArc(in: ctx, center: center, radius: innerRadius,
                fraction: clamp(fiveHourFraction), strokeWidth: strokeWidth,
                color: CGColor(gray: 1, alpha: innerFillAlpha), roundCap: true)

        // --- Pace dots ---
        drawPaceDot(in: ctx, center: center, ringRadius: outerRadius,
                    pace: clamp(sevenDayPace), dotRadius: paceDotRadius)
        drawPaceDot(in: ctx, center: center, ringRadius: innerRadius,
                    pace: clamp(fiveHourPace), dotRadius: paceDotRadius)

        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    /// Draws a stroked arc starting at 12 o'clock going clockwise.
    private static func drawArc(
        in ctx: CGContext, center: CGPoint, radius: CGFloat,
        fraction: Double, strokeWidth: CGFloat,
        color: CGColor, roundCap: Bool
    ) {
        guard fraction > 0 else { return }

        // CG y-up coords: π/2 = 12 o'clock, clockwise = true
        let startAngle = CGFloat.pi / 2
        let endAngle = startAngle - CGFloat(fraction) * 2 * .pi

        ctx.setStrokeColor(color)
        ctx.setLineWidth(strokeWidth)
        ctx.setLineCap(roundCap ? .round : .butt)
        ctx.addArc(center: center, radius: radius,
                   startAngle: startAngle, endAngle: endAngle, clockwise: true)
        ctx.strokePath()
    }

    /// Draws a pace dot on the ring centerline at the given fraction around the ring.
    private static func drawPaceDot(
        in ctx: CGContext, center: CGPoint, ringRadius: CGFloat,
        pace: Double, dotRadius: CGFloat
    ) {
        let angle = CGFloat.pi / 2 - CGFloat(pace) * 2 * .pi
        let dotCenter = CGPoint(
            x: center.x + ringRadius * cos(angle),
            y: center.y + ringRadius * sin(angle)
        )

        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.addArc(center: dotCenter, radius: dotRadius,
                   startAngle: 0, endAngle: 2 * .pi, clockwise: false)
        ctx.fillPath()
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
