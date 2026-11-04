import SwiftUI

/// One-shot confetti pop for the onboarding "connected" screen. Pieces pop out
/// toward the viewer, arc down under gravity, and pile up along the bottom
/// edge, where they stay. Values live in `Tokens.Motion.Confetti`.
///
/// A port of the HTML motion study's simulation: a reference-type model is
/// stepped once per animation frame and drawn with `Canvas`, so 235 pieces
/// cost one view rather than 235. Callers skip it under Reduce Motion.
struct ConfettiView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var simulation = ConfettiSimulation()
    @State private var isFinished = false

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(paused: isFinished)) { timeline in
                let pieces = simulation.advance(to: timeline.date, in: geometry.size)
                let colors = palette
                Canvas { context, size in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    for piece in pieces where piece.isVisible {
                        draw(piece, colors: colors, center: center, in: &context)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            // Stop the frame clock once everything has landed or left.
            while !simulation.isFinished {
                try? await Task.sleep(for: .milliseconds(250))
            }
            isFinished = true
        }
    }

    /// Brand palette plus success green. On dark, ink 700 would vanish into the
    /// navy background, so cream 50 takes its place.
    private var palette: [Color] {
        scheme == .dark
            ? [Tokens.Color.brand200, Tokens.Color.brand300, Tokens.Color.brand500,
               Tokens.Color.cream50, Tokens.Color.cream200, Tokens.Color.successDark]
            : [Tokens.Color.brand200, Tokens.Color.brand300, Tokens.Color.brand600,
               Tokens.Color.ink700, Tokens.Color.cream200, Tokens.Color.successLight]
    }

    private func draw(_ piece: ConfettiPiece, colors: [Color], center: CGPoint, in context: inout GraphicsContext) {
        // Perspective about the center: nearer pieces sit farther out and draw bigger.
        let zoom = 1 + piece.z
        var ctx = context
        ctx.translateBy(x: center.x + (piece.x - center.x) * zoom,
                        y: center.y + (piece.y - center.y) * zoom)
        ctx.rotate(by: .radians(piece.rotation))
        // Tumbling: the piece's height shrinks as it turns edge-on.
        ctx.scaleBy(x: zoom, y: zoom * (abs(cos(piece.flip)) * 0.8 + 0.2))
        let color = colors[piece.colorIndex % colors.count]
        let s = piece.size
        if piece.isRound {
            let r = s / 2.4
            ctx.fill(Path(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2)), with: .color(color))
        } else {
            ctx.fill(Path(CGRect(x: -s / 2, y: -s / 4, width: s, height: s / 2)), with: .color(color))
        }
    }
}

struct ConfettiPiece {
    var born: Double
    var x: Double, y: Double
    var vx: Double, vy: Double
    var z: Double = 0, vz: Double
    var sway: Double, swayRate: Double
    var rotation: Double, spin: Double
    var flip: Double, flipRate: Double
    var size: Double
    var isRound: Bool
    var colorIndex: Int
    var hasLaunched = false
    var isLanded = false
    var isGone = false

    var isVisible: Bool { hasLaunched && !isGone }
}

/// Owns the pieces and the pile. Not observed: the TimelineView drives redraws.
@MainActor
final class ConfettiSimulation {
    private typealias Spec = Tokens.Motion.Confetti

    private var pieces: [ConfettiPiece] = []
    private var piles: [Double] = []
    private var start: Date?
    private var last: Date?
    private(set) var isFinished = false

    /// Pile height map: one column per 6pt, so later pieces land on earlier ones.
    private let column: Double = 6

    func advance(to now: Date, in size: CGSize) -> [ConfettiPiece] {
        guard size.width > 0, size.height > 0 else { return pieces }
        if start == nil { launch(at: now, in: size) }
        guard let start, let last, !isFinished else { return pieces }

        let dt = min(0.05, now.timeIntervalSince(last))
        let t = now.timeIntervalSince(start)
        self.last = now
        let w = Double(size.width), h = Double(size.height)
        var active = 0

        for index in pieces.indices {
            var p = pieces[index]
            defer { pieces[index] = p }
            if t < p.born { active += 1; continue }
            p.hasLaunched = true
            if p.isGone || p.isLanded { continue }
            active += 1

            // Gravity plus linear air drag; drag caps the fall at gravity / drag.
            let k = exp(-Spec.drag * dt)
            p.vx *= k
            p.vy = p.vy * k + Spec.gravity * dt
            p.sway += p.swayRate * dt
            let flutter = sin(p.sway) * 30 * min(1, max(0, p.vy) / 300)
            p.x += (p.vx + flutter) * dt
            p.y += p.vy * dt
            p.rotation += p.spin * dt
            p.flip += p.flipRate * dt
            // Out toward the viewer, then pulled back to the window so it lands in the pile.
            p.vz = (p.vz - p.z * 7 * dt) * exp(-2.5 * dt)
            p.z = max(0, p.z + p.vz * dt)

            // Pieces that fly past a side edge leave rather than stacking on the wall.
            if p.x < -p.size || p.x > w + p.size { p.isGone = true; continue }

            var i = columnIndex(for: p.x)
            if p.y >= h - piles[i] - p.size * 0.2 {
                // Roll toward a lower neighbor so the pile spreads like sand.
                let step = p.size * 0.3
                for _ in 0..<6 {
                    let left = i > 0 ? piles[i - 1] : .infinity
                    let right = i < piles.count - 1 ? piles[i + 1] : .infinity
                    guard piles[i] - min(left, right) > step else { break }
                    i = left < right ? i - 1 : i + 1
                    p.x = (Double(i) + 0.5) * column
                }
                p.y = h - piles[i] - p.size * 0.2
                piles[i] += step
                p.isLanded = true
                p.z = 0
                p.flip = 0
            }
        }

        if active == 0 || t > 20 { isFinished = true }
        return pieces
    }

    private func columnIndex(for x: Double) -> Int {
        max(0, min(piles.count - 1, Int(x / column)))
    }

    private func launch(at now: Date, in size: CGSize) {
        start = now
        last = now
        let w = Double(size.width), h = Double(size.height)
        piles = Array(repeating: 0, count: Int((w / column).rounded(.up)) + 1)

        let count = Int((Spec.emitDuration * Spec.density).rounded())
        let origin = (x: w * Spec.originX, y: h * Spec.originY - 4)
        let fan = Spec.spreadDegrees * .pi / 180
        pieces = (0..<count).map { n in
            // Aim 0° = straight up; the fan opens around it.
            let angle = (Spec.aimDegrees - 90) * .pi / 180 + (Double.random(in: 0...1) - 0.5) * fan
            // sqrt fills the burst evenly; a minimum speed would leave a hollow ring.
            let speed = Spec.pop * Double.random(in: 0...1).squareRoot()
            return ConfettiPiece(
                born: Double(n) / Double(max(1, count)) * Spec.emitDuration,
                x: origin.x, y: origin.y,
                vx: cos(angle) * speed, vy: sin(angle) * speed,
                vz: Spec.depth * Double.random(in: 2...5),
                sway: Double.random(in: 0...(2 * .pi)), swayRate: Double.random(in: 3...6),
                rotation: Double.random(in: 0...(2 * .pi)), spin: Double.random(in: -6...6),
                flip: Double.random(in: 0...(2 * .pi)), flipRate: Double.random(in: 6...14),
                size: Double.random(in: 5...10),
                isRound: Double.random(in: 0...1) < 0.25,
                colorIndex: Int.random(in: 0..<6)
            )
        }
    }
}

#Preview {
    ConfettiView()
        .frame(width: 680, height: 580)
        .background(Tokens.Color.cream50)
}
