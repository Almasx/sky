import SwiftUI

/// Gallery jiggle mode — the home-screen idiom: hold a tile and the whole
/// grid wobbles, a glass "−" lands on every tile, the "+" becomes a "✓".
/// Tuned live in prototypes/gallery-controls.html.
enum Jiggle {
    /// Hold a tile (or the empty canvas) this long to wake the grid.
    static let holdDuration: TimeInterval = 0.45
    /// The wobble: a small rotation with a hint of drift — restrained, like
    /// widgets on today's home screen, not the old shake.
    static let angle: Double = 1
    static let period: TimeInterval = 0.3
    static let drift: CGFloat = 0.5
    /// The delete badge: a glass disc inside the tile's top-left corner.
    static let badgeSize: CGFloat = 30
    static let badgeInset: CGFloat = 8
    /// A dragged tile lifts to this size.
    static let liftScale: CGFloat = 1.05
    /// Moving this far while the grid is awake picks the tile up.
    static let dragSlop: CGFloat = 6
}

/// The home-screen wobble, driven by a frame clock.
///
/// Not a `repeatForever` animation: SwiftUI blends animations additively and
/// a repeating one never finishes, so its rotation kept leaking onto tiles
/// long after the grid had settled. The clock only ticks while the grid is
/// awake; the only per-frame work is two render-server transforms per tile
/// (keep backdrop effects and blurred shadows off the tiles — those are what
/// make it lag). Each tile starts at a random point in the cycle, so the
/// grid reads as loose rather than marching in step; the wobble ramps in
/// over one period and, on the way out, rides the caller's transaction to
/// rest.
struct Wobble: ViewModifier {
    let isOn: Bool
    @State private var phase = Double.random(in: 0..<(2 * .pi))
    @State private var startedAt = Date.distantPast

    func body(content: Content) -> some View {
        TimelineView(.animation(paused: !isOn)) { context in
            let now = context.date
            let ramp = isOn ? min(1, now.timeIntervalSince(startedAt) / Jiggle.period) : 0
            let u = 2 * .pi * now.timeIntervalSinceReferenceDate / Jiggle.period + phase
            content
                .rotationEffect(.degrees(Jiggle.angle * sin(u) * ramp))
                .offset(x: Jiggle.drift * cos(u) * ramp, y: -Jiggle.drift * sin(u) * ramp)
        }
        .onChange(of: isOn, initial: true) { _, on in
            if on { startedAt = .now }
        }
    }
}

/// The "−" that removes a tile: a small translucent disc, the hit area
/// padded out past it so it's an easy tap on a wobbling card.
///
/// DECIDED: a flat fill, not Liquid Glass. Glass that wobbles visibly
/// breathes in size (tried plain, pinned, and in a `GlassEffectContainer`),
/// and materials sampling the backdrop every frame make the grid lag. The
/// flat disc holds its size and costs nothing; ink and fill are semantic so
/// it follows the rest of the app and dark mode.
struct DeleteBadge: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "minus")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(.tertiary)
                .frame(width: Jiggle.badgeSize, height: Jiggle.badgeSize)
                .background(.background.opacity(0.85), in: .circle)
                .overlay { Circle().strokeBorder(.quaternary, lineWidth: 0.5) }
                .padding(7)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    @Previewable @State var on = true
    VStack(spacing: 40) {
        GradientCard(item: SkyGradient.presets[2])
            .frame(width: 177, height: 234)
            .overlay(alignment: .topLeading) {
                DeleteBadge {}
                    .padding(Jiggle.badgeInset - 7)
            }
            .modifier(Wobble(isOn: on))
        Toggle("Jiggle", isOn: $on).frame(width: 177)
    }
    .padding(60)
    .background(Color.canvas)
}
