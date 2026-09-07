import SwiftUI

/// One color stop of a sky. The raw hex is kept alongside the location so
/// edit mode can label each stop with its exact value.
struct SkyStop: Hashable, Identifiable, Codable {
    /// Stable identity, so a tag keeps animating as its own view while the
    /// stop is dragged, and the right tag leaves when a stop is removed.
    let id: UUID
    var hex: UInt32
    var location: CGFloat

    init(hex: UInt32, location: CGFloat) {
        self.id = UUID()
        self.hex = hex
        self.location = location
    }

    var color: Color { Color(hex: hex) }
    var label: String { String(format: "#%06X", hex) }

    /// Per-channel sRGB mix — the color the gradient itself shows between
    /// two stops.
    static func mix(_ a: UInt32, _ b: UInt32, _ t: CGFloat) -> UInt32 {
        func channel(_ shift: UInt32) -> UInt32 {
            let x = CGFloat((a >> shift) & 0xFF), y = CGFloat((b >> shift) & 0xFF)
            return UInt32((x + (y - x) * t).rounded()) << shift
        }
        return channel(16) | channel(8) | channel(0)
    }
}

// MARK: - Adding and removing stops (prototyped in prototypes/bottom-bar.html)

extension Array where Element == SkyStop {
    /// Adding a color, the Figma way: a new stop drops into the biggest gap,
    /// at its midpoint, carrying the color the gradient already shows there.
    /// The sky itself doesn't change — a new handle simply appears, ready to
    /// be moved or recolored. Repeated adds keep subdividing evenly. A lone
    /// color gets a partner at the far end of the card, in the same color.
    ///
    /// The new stop is appended, not sorted in, so existing stops keep their
    /// indices (edit mode tracks tags by index).
    func addingStop() -> [SkyStop] {
        let sorted = self.sorted { $0.location < $1.location }
        guard let first = sorted.first else { return self }
        guard sorted.count >= 2 else {
            return self + [SkyStop(hex: first.hex, location: first.location <= 0.5 ? 1 : 0)]
        }
        var widest = (sorted[0], sorted[1])
        for (a, b) in zip(sorted, sorted.dropFirst())
        where b.location - a.location > widest.1.location - widest.0.location {
            widest = (a, b)
        }
        let (a, b) = widest
        return self + [SkyStop(
            hex: SkyStop.mix(a.hex, b.hex, 0.5),
            location: (a.location + b.location) / 2
        )]
    }

    /// The color the gradient would show at `location` if stop `index`
    /// weren't there.
    func colorWithout(_ index: Int, at location: CGFloat) -> UInt32 {
        let rest = enumerated().filter { $0.offset != index }.map(\.element)
            .sorted { $0.location < $1.location }
        guard let first = rest.first, let last = rest.last else { return self[index].hex }
        guard let above = rest.first(where: { $0.location >= location }) else { return last.hex }
        guard let below = rest.last(where: { $0.location <= location }) else { return first.hex }
        let span = above.location - below.location
        guard span > 0 else { return below.hex }
        return SkyStop.mix(below.hex, above.hex, (location - below.location) / span)
    }

    /// A display copy with stop `index` melted `fade` of the way into its
    /// surroundings — what the card shows while that stop is being pulled
    /// off. At 1 the stop is invisible, so removing it changes nothing.
    func fading(_ index: Int?, by fade: CGFloat) -> [SkyStop] {
        guard let index, indices.contains(index), fade > 0 else { return self }
        var copy = self
        copy[index].hex = SkyStop.mix(self[index].hex, colorWithout(index, at: self[index].location), fade)
        return copy
    }
}

/// A saved sky gradient — a vertical run of color stops plus the day it was captured.
struct SkyGradient: Identifiable, Hashable, Codable {
    let id: Int
    let title: String
    let stops: [SkyStop]

    var linearGradient: LinearGradient {
        // Stops can leapfrog each other while being dragged in edit mode;
        // Gradient wants them ascending.
        LinearGradient(
            gradient: Gradient(stops: stops
                .sorted { $0.location < $1.location }
                .map { .init(color: $0.color, location: $0.location) }),
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Palettes (stops taken verbatim from the Figma fills)

extension Array where Element == SkyStop {
    /// Gray-blue into warm sand. "July 5" / "June 5" card.
    static var dusk: [SkyStop] {
        [
            SkyStop(hex: 0x8D909E, location: 0),
            SkyStop(hex: 0xB69F99, location: 0.485),
            SkyStop(hex: 0xC8A68F, location: 0.680),
            SkyStop(hex: 0xD4AC77, location: 0.838),
            SkyStop(hex: 0xDE956A, location: 1),
        ]
    }

    /// Slate into burning orange. "July 3" / "July 18" card.
    static var ember: [SkyStop] {
        [
            SkyStop(hex: 0x888FA6, location: 0),
            SkyStop(hex: 0x9A7A90, location: 0.28),
            SkyStop(hex: 0xC05744, location: 0.52),
            SkyStop(hex: 0xD63C1F, location: 0.72),
            SkyStop(hex: 0xF27615, location: 1),
        ]
    }

    /// Powder blue into rose. "Jun 15" card.
    static var dawn: [SkyStop] {
        [
            SkyStop(hex: 0xA6CADF, location: 0.065),
            SkyStop(hex: 0xA7CDE0, location: 0.200),
            SkyStop(hex: 0xBEB7B1, location: 0.537),
            SkyStop(hex: 0xDA9096, location: 0.761),
            SkyStop(hex: 0xFF9881, location: 0.891),
            SkyStop(hex: 0xEFB291, location: 0.999),
        ]
    }

    /// Deep night blue into violet. "May 12" card.
    static var night: [SkyStop] {
        [
            SkyStop(hex: 0x03113A, location: 0),
            SkyStop(hex: 0x293EA5, location: 0.389),
            SkyStop(hex: 0x5457E1, location: 0.659),
            SkyStop(hex: 0x9380F9, location: 0.861),
            SkyStop(hex: 0xDE8DED, location: 0.963),
        ]
    }

    /// The untouched starting point for a brand-new gradient: white into gray.
    static var blank: [SkyStop] {
        [
            SkyStop(hex: 0xFFFFFF, location: 0),
            SkyStop(hex: 0x999999, location: 1),
        ]
    }

    /// Powder blue straight into coral. "July 20" card.
    static var sunset: [SkyStop] {
        [
            SkyStop(hex: 0xA6CADF, location: 0.065),
            SkyStop(hex: 0xA7CDE0, location: 0.204),
            SkyStop(hex: 0xDA9096, location: 0.748),
            SkyStop(hex: 0xFF9881, location: 0.891),
            SkyStop(hex: 0xEFB291, location: 0.999),
        ]
    }
}

// MARK: - Presets and drafts

extension SkyGradient {
    /// A fresh, unedited gradient for create mode, titled with today's date.
    static func draft() -> SkyGradient {
        SkyGradient(
            id: -1,
            // Short month first ("Sep 9"), like the presets, whatever the locale.
            title: Date.now.formatted(
                Date.FormatStyle(locale: Locale(identifier: "en_US")).month(.abbreviated).day()
            ),
            stops: .blank
        )
    }

    /// What a fresh install starts with: each Figma palette once.
    static let presets: [SkyGradient] = [
        SkyGradient(id: 0, title: "July 5", stops: .dusk),
        SkyGradient(id: 1, title: "July 3", stops: .ember),
        SkyGradient(id: 2, title: "Jun 15", stops: .dawn),
        SkyGradient(id: 3, title: "May 12", stops: .night),
        SkyGradient(id: 4, title: "July 20", stops: .sunset),
    ]
}

// MARK: - Color helpers

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// The app's `#EEEEEE` canvas color.
    static let canvas = Color(hex: 0xEEEEEE)

    /// The muted gray used for dates and glyphs (`#B4B4B4`).
    static let inkMuted = Color(hex: 0xB4B4B4)

    /// The slightly darker gray of the stop hex labels (`#A2A0A0`).
    static let inkLabel = Color(hex: 0xA2A0A0)
}
