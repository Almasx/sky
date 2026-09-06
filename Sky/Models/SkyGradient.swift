import SwiftUI

/// One color stop of a sky. The raw hex is kept alongside the location so
/// edit mode can label each stop with its exact value.
struct SkyStop: Hashable {
    let hex: UInt32
    let location: CGFloat

    var color: Color { Color(hex: hex) }
    var label: String { String(format: "#%06X", hex) }
}

/// A saved sky gradient — a vertical run of color stops plus the day it was captured.
struct SkyGradient: Identifiable, Hashable {
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

// MARK: - Sample data (matches the Figma gallery order)

extension SkyGradient {
    /// A fresh, unedited gradient for create mode, titled with today's date.
    static func draft() -> SkyGradient {
        SkyGradient(
            id: -1,
            title: Date.now.formatted(.dateTime.month(.wide).day()),
            stops: .blank
        )
    }

    static let samples: [SkyGradient] = [
        SkyGradient(id: 0, title: "July 5", stops: .dusk),
        SkyGradient(id: 1, title: "July 3", stops: .ember),
        SkyGradient(id: 2, title: "Jun 15", stops: .dawn),
        SkyGradient(id: 3, title: "May 12", stops: .night),
        SkyGradient(id: 4, title: "July 18", stops: .ember),
        SkyGradient(id: 5, title: "June 5", stops: .dusk),
        SkyGradient(id: 6, title: "July 19", stops: .night),
        SkyGradient(id: 7, title: "July 20", stops: .sunset),
        SkyGradient(id: 8, title: "July 18", stops: .ember),
        SkyGradient(id: 9, title: "June 5", stops: .dusk),
        SkyGradient(id: 10, title: "July 3", stops: .ember),
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
