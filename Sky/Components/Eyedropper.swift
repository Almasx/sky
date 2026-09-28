import SwiftUI
import UIKit

// MARK: - Eyedropper (prototyped in prototypes/color-picker.html)

/// One pass of the eyedropper, owned by the overlay that hosts the
/// Choose-color sheet.
///
/// The pipette in the sheet's header drops the sheet and zooms the sky up
/// into the safe area — the hero move, so it rides `heroOpen` / `heroClose`.
/// A glass lens sits mid-sky; touching the sky puts it under the finger at
/// once, and the drag carries it.
/// Lifting after a drag takes the color under it (a tap does nothing); the sky zooms back into the card as the
/// sheet rises with the new color.
struct EyedropperSession {
    /// The stop being picked for; nil when no pass is running.
    var stop: Int?
    /// Zoomed up (true) or sitting exactly on the card (false). Animated.
    var isZoomed = false
    /// The lens is live. Drops the instant a color is taken, before the
    /// zoom back.
    var isPicking = false
    /// The docked tag isn't part of the pick: gone the instant a pass starts,
    /// fading back in step with the zoom home.
    var hidesTag = false
    /// Dropping the sheet to pick mustn't run the sheet-closed slide.
    var swallowsDismiss = false

    /// The pipette button's center: the lens flies out of it and back.
    var origin: CGPoint = .zero

    mutating func begin(stop index: Int, from origin: CGPoint) {
        stop = index
        self.origin = origin
        isPicking = true
        hidesTag = true
        swallowsDismiss = true
    }
}

/// The zoomed sky and the glass lens.
///
/// Layers never trade places: this sits above the card and its chrome and,
/// like the card, below the sheet — the sky grows behind the falling sheet
/// and shrinks back behind the rising one. The card holds still for the whole
/// pass (ride-up kept), so the zoom leaves from and lands on it exactly, and
/// vanishes onto an identical card once it has.
struct SkyEyedropper: View {
    let stops: [SkyStop]
    /// The card's on-screen rect for a full-screen size — the host's own
    /// hero geometry, so the zoom leaves from exactly where the card is.
    let cardFrame: (CGSize) -> CGRect
    let session: EyedropperSession
    /// The header's cancel button (global): touches there cancel, not pick.
    var cancelFrame: CGRect = .zero
    /// The color taken, or nil when the pass was cancelled.
    var onFinish: (UInt32?) -> Void

    private var sky: SkyGradient { SkyGradient(id: -1, title: "", stops: stops) }

    /// The sky's two ends — what runs on past the safe area.
    private var edgeHexes: (top: UInt32, bottom: UInt32) {
        (stops.hex(at: 0), stops.hex(at: 1))
    }

    var body: some View {
        // The outer reader respects the safe area, so it can report the
        // insets; the inner one draws in full-screen coordinates.
        GeometryReader { safe in
            let insets = safe.safeAreaInsets
            ZStack {
                GeometryReader { proxy in
                    let full = CGRect(origin: .zero, size: proxy.size)
                    let zoom = zoomFrame(in: proxy.size, insets: insets)
                    let card = cardFrame(proxy.size)
                    // The layer grows from the card to the WHOLE screen, so
                    // nothing of the scene shows around it (a ridden-up card
                    // peeked out past a safe-area-sized sky). The gradient
                    // itself settles into the safe area; past it, its first and
                    // last colors simply run on to the screen's edges. All one
                    // layout, one spring — frame, gradient and corner can't
                    // drift apart. At full screen the 55pt corner sits inside
                    // the display's own rounding, so it's never seen.
                    let rect = session.isZoomed ? full : card
                    let scope = session.isZoomed ? zoom : card
                    ZStack(alignment: .topLeading) {
                        VStack(spacing: 0) {
                            Color(hex: edgeHexes.top)
                            Color(hex: edgeHexes.bottom)
                        }
                        sky.linearGradient
                            .frame(width: scope.width, height: scope.height)
                            .offset(x: scope.minX - rect.minX, y: scope.minY - rect.minY)
                    }
                    .frame(width: rect.width, height: rect.height)
                    .clipShape(CardShape(cornerRadius: 55))
                    .position(x: rect.midX, y: rect.midY)
                    .opacity(session.stop == nil ? 0 : 1)
                    .allowsHitTesting(false)

                    // On the way home the docked tag rides back ON TOP of the
                    // sky, glued to its trailing edge and fading in with the
                    // zoom — beneath, it popped out when the edge passed it.
                    // Swapped for the real tag as the sky lands.
                    if let index = session.stop, !session.isPicking, stops.indices.contains(index) {
                        let stop = stops[index]
                        // At its stop's height on the gradient; on the layer's edge.
                        let y = min(max(stop.location * scope.height, 20), scope.height - 20)
                        StopTag(color: stop.color)
                            .frame(width: 60, height: 40, alignment: .leading)
                            .position(x: rect.maxX - 22 + 30, y: scope.minY + y)
                            .opacity(session.isZoomed ? 0 : 1)
                            .allowsHitTesting(false)
                    }

                    if session.stop != nil {
                        // Its own view: a drag re-renders the lens and nothing
                        // else. Inserted fresh each pass, so it starts centered.
                        EyedropperLens(
                            stops: stops,
                            gradient: sky.linearGradient,
                            sky: zoom,
                            origin: session.origin,
                            isActive: session.isPicking,
                            cancelFrame: cancelFrame,
                            onFinish: onFinish
                        )
                        .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                }
                .ignoresSafeArea()

            }
        }
    }

    /// Where the zoomed gradient itself lives: the safe area, full width.
    private func zoomFrame(in size: CGSize, insets: EdgeInsets) -> CGRect {
        CGRect(x: 0, y: insets.top, width: size.width, height: size.height - insets.top - insets.bottom)
    }
}

/// The glass lens. Owns the drag, so moving it touches only this view; the
/// magnified sky is a lens-sized strip of the gradient (it only varies
/// vertically), never a full-screen layer scaled and masked.
///
/// It flies out of the pipette button — button-sized, on the zoom's own
/// `heroOpen` — to the middle of the sky, and back into the button on
/// `heroClose` when the pass ends, carrying the color it took.
private struct EyedropperLens: View {
    let stops: [SkyStop]
    /// Built once per pass by the parent, not per drag frame.
    let gradient: LinearGradient
    /// The zoomed sky's rect, full-screen coordinates.
    let sky: CGRect
    /// The pipette button's center.
    let origin: CGPoint
    /// Live (true) or heading home (false).
    let isActive: Bool
    /// Touches starting here belong to the header's ✕.
    let cancelFrame: CGRect
    var onFinish: (UInt32?) -> Void

    /// Tuned in the prototype.
    static let size: CGFloat = 120
    static let magnification: CGFloat = 3
    /// The lens at the button: button-sized.
    static let buttonScale: CGFloat = 44 / 120
    /// Travel below this is a tap: the color right where it landed.
    static let minimumTravel: CGFloat = 4

    /// The lens center — the sampled point. Nil = the middle of the sky.
    @State private var lens: CGPoint?
    /// Where the lens sat when the current touch began, and where the
    /// finger did.
    @State private var dragBase: CGPoint?
    @State private var touchStart: CGPoint = .zero
    /// Out over the sky (true) or tucked into the button (false).
    @State private var isOut = false

    var body: some View {
        let center = lens ?? CGPoint(x: sky.midX, y: sky.midY)
        let t = min(max((center.y - sky.minY) / max(sky.height, 1), 0), 1)
        let tall = sky.height * Self.magnification
        ZStack(alignment: .topLeading) {
            // Takes every touch: drag from anywhere.
            Color.clear.contentShape(Rectangle())

            ZStack {
                // The sky magnified around the sampled point.
                gradient
                    .frame(width: Self.size, height: tall)
                    .offset(y: tall / 2 - t * tall)
                    .frame(width: Self.size, height: Self.size)
                    .clipShape(Circle())
                // Liquid Glass over it: the rim light and edge refraction.
                Circle()
                    .fill(.clear)
                    .glassEffect(.clear, in: .circle)
                // The sheet's own slider thumb, filled with the color you'll get.
                ColorThumb(color: Color(hex: stops.hex(at: t)))
            }
            .frame(width: Self.size, height: Self.size)
            .shadow(color: .black.opacity(0.28), radius: 17, y: 14)
            .scaleEffect(isOut ? 1 : Self.buttonScale)
            .opacity(isOut ? 1 : 0)
            // Two offsets, never one: the flight from/to the button springs,
            // the finger's position never does. Sharing one offset, the
            // flight's spring smoothed the drag and the lens trailed the
            // finger for its first moments. Out, the flight offset is zero
            // whatever the lens does, so dragging mid-flight is still 1:1.
            .offset(isOut ? .zero : CGSize(width: origin.x - center.x, height: origin.y - center.y))
            .offset(x: center.x - Self.size / 2, y: center.y - Self.size / 2)
            .transaction(value: lens) { $0.animation = nil }
        }
        .allowsHitTesting(isActive)
        .onAppear {
            withAnimation(.heroOpen) { isOut = true }
        }
        .onChange(of: isActive) { _, active in
            if active {
                // Picked again before the last pass got home: the view never
                // left, so onAppear won't fire — fly out from here, centered.
                lens = nil
                dragBase = nil
                withAnimation(.heroOpen) { isOut = true }
            } else {
                withAnimation(.heroClose) { isOut = false }
            }
        }
        // Touches come from the WINDOW, not a SwiftUI gesture: after the
        // sheet drops, whatever it leaves behind eats the next touch, and the
        // lens missed the first drag every time. A recognizer on the window
        // sits above all of that and runs alongside everything.
        .background(
            WindowTouches(isEnabled: isActive, excluding: cancelFrame) { phase, point in
                switch phase {
                case .began:
                    // Touch-down puts the lens under the finger at once.
                    let base = moved(point, by: .zero)
                    dragBase = base
                    touchStart = point
                    lens = base
                case .moved:
                    let base = dragBase ?? center
                    lens = moved(base, by: CGSize(width: point.x - touchStart.x, height: point.y - touchStart.y))
                case .ended:
                    let base = dragBase ?? center
                    dragBase = nil
                    let travel = CGSize(width: point.x - touchStart.x, height: point.y - touchStart.y)
                    // A quick tap takes the color right where it landed; a
                    // drag takes it where the lens ended up. Either goes back.
                    let isTap = hypot(travel.width, travel.height) < Self.minimumTravel
                    let end = isTap ? base : moved(base, by: travel)
                    lens = end
                    let at = min(max((end.y - sky.minY) / max(sky.height, 1), 0), 1)
                    onFinish(stops.hex(at: at))
                case .cancelled:
                    dragBase = nil
                }
            }
        )
    }

    /// The lens moved by a drag's travel, kept on the sky.
    private func moved(_ base: CGPoint, by t: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(base.x + t.width, sky.minX), sky.maxX),
            y: min(max(base.y + t.height, sky.minY), sky.maxY)
        )
    }
}

// MARK: - Window touches

/// Follows touches with a recognizer on the hosting WINDOW while enabled —
/// immediately on touch-down, alongside every other gesture, never
/// cancelling them. Points are in window (= full-screen) coordinates.
private struct WindowTouches: UIViewRepresentable {
    enum Phase { case began, moved, ended, cancelled }

    var isEnabled: Bool
    /// Touches beginning here are left alone (a button's frame, global).
    var excluding: CGRect
    var onTouch: (Phase, CGPoint) -> Void

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: WindowTouches
        let recognizer: UILongPressGestureRecognizer
        weak var window: UIWindow?

        init(_ parent: WindowTouches) {
            self.parent = parent
            recognizer = UILongPressGestureRecognizer()
            super.init()
            recognizer.minimumPressDuration = 0
            recognizer.allowableMovement = .greatestFiniteMagnitude
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            recognizer.delegate = self
            recognizer.addTarget(self, action: #selector(handle))
        }

        func attach(to window: UIWindow?) {
            guard window !== self.window else { return }
            self.window?.removeGestureRecognizer(recognizer)
            self.window = window
            window?.addGestureRecognizer(recognizer)
        }

        @objc func handle(_ r: UILongPressGestureRecognizer) {
            guard parent.isEnabled else { return }
            let point = r.location(in: r.view)
            switch r.state {
            case .began: parent.onTouch(.began, point)
            case .changed: parent.onTouch(.moved, point)
            case .ended: parent.onTouch(.ended, point)
            case .cancelled, .failed: parent.onTouch(.cancelled, point)
            default: break
            }
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard parent.isEnabled else { return false }
            return !parent.excluding.contains(touch.location(in: g.view))
        }

        func gestureRecognizer(
            _ g: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }
    }

    /// Reports its window as soon as it joins one.
    final class Probe: UIView {
        var onWindow: ((UIWindow?) -> Void)?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            onWindow?(window)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> Probe {
        let probe = Probe()
        probe.isUserInteractionEnabled = false
        let coordinator = context.coordinator
        probe.onWindow = { coordinator.attach(to: $0) }
        return probe
    }

    func updateUIView(_ probe: Probe, context: Context) {
        context.coordinator.parent = self
        context.coordinator.attach(to: probe.window)
    }

    static func dismantleUIView(_ probe: Probe, coordinator: Coordinator) {
        coordinator.attach(to: nil)
    }
}
