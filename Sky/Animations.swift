import SwiftUI

extension Animation {
    /// Card → detail.
    static let heroOpen: Animation = .spring(duration: 0.31, bounce: 0.19)

    /// Detail → card.
    static let heroClose: Animation = .spring(duration: 0.26, bounce: 0)

    /// Detail ↔ edit slide.
    static let editSlide: Animation = .spring(duration: 0.22, bounce: 0)

    /// Grabbing a stop tag: the scene zooms in and springs back.
    /// Tuned live in prototypes/stop-picker.html.
    static let stopGrab: Animation = .spring(duration: 0.2, bounce: 0.15)

    // Adding and removing stops. Tuned live in prototypes/bottom-bar.html.
    /// A new stop's tag sliding in from the right.
    static let stopEnter: Animation = .spring(duration: 0.2, bounce: 0.15)
    /// A pulled-off tag flying out past the right edge.
    static let stopLeave: Animation = .spring(duration: 0.26, bounce: 0)
    /// A tag let go before the let-go point, snapping back onto the card.
    static let stopSnapBack: Animation = .spring(duration: 0.32, bounce: 0.2)

    // Gallery jiggle mode. Tuned live in prototypes/gallery-controls.html.
    /// A delete badge popping onto a tile as the grid wakes.
    static let badgePop: Animation = .spring(duration: 0.32, bounce: 0.35)
    /// The "+" becoming a "✓" and back; the revert button's entrance.
    static let glyphMorph: Animation = .spring(duration: 0.3, bounce: 0.2)
    /// Tiles making room while one is dragged, closing up after a delete,
    /// and a dropped tile settling into its slot.
    static let gridReflow: Animation = .spring(duration: 0.32, bounce: 0.1)
    /// A dragged tile lifting under the finger.
    static let tileLift: Animation = .spring(duration: 0.2, bounce: 0.2)
    /// A deleted tile shrinking away.
    static let tileVanish: Animation = .spring(duration: 0.26, bounce: 0)
    /// A reverted tile growing back into its slot.
    static let tileReturn: Animation = .spring(duration: 0.36, bounce: 0.2)
}
