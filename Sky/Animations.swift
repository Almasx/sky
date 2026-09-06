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
}
