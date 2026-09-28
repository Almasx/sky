import SwiftUI
import UIKit

/// Shared tuning for edit mode — the card slide and the tag bloom.
enum EditMode {
    /// How much of the screen the card vacates when pinned left.
    /// From the Figma frame: the card slides 16 → −188 on a 402pt screen.
    static let hiddenFraction: CGFloat = 204.0 / 402.0
    /// Tags materialize over the last stretch of the slide…
    static let tagsAppearAt: CGFloat = 0.6
    static let tagsAppearWindow: CGFloat = 0.4
    /// …each blooming out of its own tail tip from this scale.
    static let tagStartScale: CGFloat = 0.2

    // Grab-a-stop interaction, tuned live in prototypes/stop-picker.html.
    /// Holding a tag this long commits the grab…
    static let grabHoldDelay: Duration = .milliseconds(150)
    /// …or moving this far commits it immediately.
    static let grabSlop: CGFloat = 8
    /// The whole scene — card and tags together — zooms in around the stop.
    /// The tag, its swatch, and its label all ride this one transform as a
    /// single rigid group; nothing scales independently.
    static let grabZoom: CGFloat = 1.25

    // Adding and removing stops, tuned live in prototypes/bottom-bar.html.
    /// A new tag slides in from this far to the right…
    static let tagEnterDistance: CGFloat = 80
    /// …and a removed one flies out this far, past the screen edge.
    static let tagLeaveDistance: CGFloat = 480
    /// Pull a tag this far off the card and it lets go.
    static let removePullDistance: CGFloat = 60
    /// Magnet feel while attached: how far the tag lags behind the finger.
    static let removeResistance: CGFloat = 0.4

    // Birth-a-color: touch the empty space beside the card and a new tag
    // docks onto the edge at that height. Tuned in prototypes/bottom-bar.html.
    /// Existing tags own this much of the empty space around their row —
    /// touches there stay quiet rather than birthing a tag on top of one.
    static let birthKeepClear: CGFloat = 30
    /// How far right of the card the zone listens.
    static let birthZoneWidth: CGFloat = 400
    /// A newborn holds on harder than an established tag: dismissing it
    /// mid-birth takes a longer pull than removing an existing stop.
    static let birthLetGo: CGFloat = 60
}

/// Shared, pre-warmed feedback generators. Creating one per tick causes
/// visible frame hitches mid-drag; these live for the app's lifetime and get
/// `prepare()`d when a grab starts so every tick lands with no latency.
@MainActor
private enum Haptics {
    static let grab = UIImpactFeedbackGenerator(style: .medium)
    static let tick = UISelectionFeedbackGenerator()
    static let knock = UIImpactFeedbackGenerator(style: .rigid)
    static let thud = UIImpactFeedbackGenerator(style: .heavy)
    static let release = UIImpactFeedbackGenerator(style: .light)

    static func warmUp() {
        tick.prepare()
        knock.prepare()
        thud.prepare()
        release.prepare()
    }
}

/// Scene-zoom state while a stop tag is grabbed. Owned by the overlay (which
/// scales the whole card + tag layer and fades its chrome), written by
/// `StopTagColumn` (which runs the gesture).
struct StopGrab: Equatable {
    var isZoomed = false
    /// Sticky: keeps its last value through the release so the zoom-out
    /// doesn't re-anchor mid-flight.
    var anchor: UnitPoint = .center
    /// While a tag is being pulled off, its color melts out of the card in
    /// step with the finger: 0 = fully there, 1 = gone.
    var fadingIndex: Int?
    var fade: CGFloat = 0
}

/// Pull-to-remove state, keyed by stop id so it outlives the stop's removal
/// (the leaving tag keeps its offset while it flies off).
struct TagPull: Equatable {
    var id: SkyStop.ID?
    /// Where the tag sits relative to its slot.
    var offset: CGFloat = 0
    /// How far along toward the let-go point the finger is, 0…1.
    var progress: CGFloat = 0
    var detached = false
}

/// The edit-mode picker column: one tag per gradient stop, hanging off the
/// card's trailing edge at the stop's location. All tags pop on the same
/// beat, each scaling out of its own tail tip.
///
/// In edit mode each tag is grabbable: hold it (or just start dragging) and
/// the whole scene zooms in around the stop, the hex morphs into the stop's
/// % position, everything else fades, and dragging moves the stop through
/// the gradient — free to leapfrog its neighbors. Release to spring back,
/// keeping the value.
///
/// Pull a tag sideways, away from the card, to remove its stop. It resists
/// like a magnet while it dims and its color melts out of the sky; at the
/// let-go point it comes free, and releasing it there sends it off the
/// edge. Let go early and it snaps back, color and all. The last color only
/// resists.
///
/// Touch the empty space beside the card and a new tag is born: it docks
/// onto the edge at that height, previewing the color already there — the
/// sky doesn't change, a handle appears. Slide to place it; release to keep
/// it. From birth it obeys removal physics, so dismissing is literally the
/// delete gesture: pull it away and let go. Near an existing tag the space
/// stays quiet — that neighborhood belongs to the tag.
struct StopTagColumn: View {
    @Binding var stops: [SkyStop]
    let cardSize: CGSize
    /// The edit slide progress: 0 = view mode, 1 = edit mode.
    var progress: CGFloat
    /// The scene zoom, applied by the owning overlay.
    @Binding var grab: StopGrab
    /// The stop being color-edited, if any: its tag stays docked at the card
    /// edge (indicator only — not grabbable) while the others bloom away.
    var colorEditIndex: Int? = nil
    /// Hides the docked tag while a twin of it is drawn elsewhere (the
    /// eyedropper's, riding the zoomed sky).
    var hidesDocked = false
    /// A tap — as opposed to a grab — on a tag. Opens the color editor.
    var onTap: ((Int) -> Void)? = nil

    /// The stop under a finger right now — held, not necessarily zoomed yet.
    @State private var grabbedIndex: Int?
    @State private var grabStartLocation: CGFloat = 0
    /// Fires the grab if the hold outlasts `grabHoldDelay` without movement.
    @State private var holdTask: Task<Void, Never>?
    /// Pressing a tag lifts it above overlapping neighbors, lastingly.
    @State private var tagZ: [Int: Double] = [:]
    @State private var nextZ: Double = 1
    /// Haptic bookkeeping: last whole percent ticked, and whether the stop
    /// is already pressed against the card's end.
    @State private var lastTickPercent = 0
    @State private var atEdge = false
    @State private var pull = TagPull()
    /// The stop being born from the empty space, while the finger is down.
    @State private var birthId: SkyStop.ID?

    var body: some View {
        ZStack(alignment: .topLeading) {
            birthZone
            tagRows
        }
        // The zone is wider than the card; without a pinned frame the ZStack
        // would size to it and the overlay's centering would shift every tag
        // off its stop.
        .frame(width: cardSize.width, height: cardSize.height, alignment: .topLeading)
    }

    private var tagRows: some View {
        ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
            let isGrabbed = grabbedIndex == index && grab.isZoomed
            let isPulled = pull.id == stop.id
            let isDocked = colorEditIndex == index
            // Keep tags clear of the card's rounded corners.
            let y = min(max(stop.location * cardSize.height, 20), cardSize.height - 20)
            HStack(spacing: 24) {
                // The tag sits leading in its 60pt slot (Figma layout).
                StopTag(color: stop.color)
                    .frame(width: 60, height: 40, alignment: .leading)
                label(for: stop, showsPercent: isGrabbed)
                    // Docked at the card edge the label would hang off-screen,
                    // so it rides the slide: gone at full width, back in step
                    // with everyone else on the way home.
                    .opacity(isDocked ? min(1, max(0, progress)) : 1)
            }
            .contentShape(Rectangle())
            .gesture(grabGesture(for: index))
            // A gentle press-down while the hold is still deciding.
            .scaleEffect(grabbedIndex == index && !grab.isZoomed && !isPulled && !isDocked
                         ? 0.96 : 1,
                         anchor: UnitPoint(x: 0, y: 0.5))
            // The docked tag rides the card home at full bloom while the
            // others follow the slide back down to nothing.
            .modifier(TagBloom(progress: isDocked ? 1 : progress))
            // Pull-to-remove rides on top: the drag offset, and a dimming
            // that deepens with the pull. A tag still being born is a touch
            // translucent — a preview until the finger lifts.
            .offset(x: isPulled ? pull.offset : 0)
            .opacity(birthId == stop.id ? 0.7 : 1)
            .opacity(isPulled ? 1 - 0.45 * pull.progress : 1)
            // A new tag slides in from the right and fades in; a removed one
            // flies off past the right edge.
            .transition(.asymmetric(
                insertion: .offset(x: EditMode.tagEnterDistance).combined(with: .opacity),
                removal: .offset(x: EditMode.tagLeaveDistance).combined(with: .opacity)
            ))
            // Pin each row in a card-sized box so its x never depends on the
            // row's own width, then push it to the stop's spot: the tail tip
            // sits 22pt inside the card edge (Figma).
            .frame(width: cardSize.width, height: cardSize.height, alignment: .topLeading)
            .offset(x: cardSize.width - 22, y: y - 20)
            // The other tags fade away while a stop is grabbed.
            .opacity(grab.isZoomed && grabbedIndex != index ? 0 : 1)
            .opacity(hidesDocked && isDocked ? 0 : 1)
            .zIndex(tagZ[index] ?? 0)
            // While the color sheet is up only the docked tail is live — a
            // silent handle: drag it to move the stop, nothing else.
            .allowsHitTesting(isDocked || (progress > 0.95 && colorEditIndex == nil))
        }
    }

    // MARK: - Birth-a-color

    /// The empty space beside the card. Sits beneath the tag rows, so
    /// existing tags always win the touch.
    private var birthZone: some View {
        Color.clear
            .frame(width: EditMode.birthZoneWidth, height: cardSize.height)
            .contentShape(Rectangle())
            .offset(x: cardSize.width)
            .gesture(birthGesture)
            .allowsHitTesting(progress > 0.95 && colorEditIndex == nil && !grab.isZoomed)
    }

    /// Zone-local space: x = 0 at the card's trailing edge.
    private var birthGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if birthId == nil {
                    beginBirth(at: value.startLocation)
                }
                guard let id = birthId,
                      let index = stops.firstIndex(where: { $0.id == id }) else { return }
                // Vertical places it; the swatch previews the color there.
                let loc = min(max(value.location.y / cardSize.height, 0), 1)
                stops[index].location = loc
                stops[index].hex = stops.colorWithout(index, at: loc)
                // Horizontal is the delete pull, relative to the dock —
                // with the newborn's longer leash.
                if abs(value.translation.width) > 4 {
                    updatePull(index, dx: value.translation.width, letGo: EditMode.birthLetGo)
                }
            }
            .onEnded { _ in
                guard let id = birthId else { return }
                // The preview solidifies as the finger lifts.
                withAnimation(.easeOut(duration: 0.2)) {
                    birthId = nil
                }
                guard let index = stops.firstIndex(where: { $0.id == id }) else { return }
                if !pull.detached {
                    Haptics.thud.impactOccurred()
                }
                endPull(index)
            }
    }

    private func beginBirth(at point: CGPoint) {
        let loc = min(max(point.y / cardSize.height, 0), 1)
        // Existing tags own their neighborhood: a newcomer materializing on
        // top of one reads as a glitch, and its row must stay reachable.
        let clampedY = { (l: CGFloat) in min(max(l * cardSize.height, 20), cardSize.height - 20) }
        let y = clampedY(loc)
        guard !stops.contains(where: { abs(clampedY($0.location) - y) < EditMode.birthKeepClear + 20 })
        else { return }

        // Born with the color the gradient already shows there, so the sky
        // doesn't change — a new handle simply appears.
        let future = stops + [SkyStop(hex: 0, location: loc)]
        let stop = SkyStop(hex: future.colorWithout(future.count - 1, at: loc), location: loc)
        stops.append(stop)
        birthId = stop.id
        // Docks itself: darts from under the finger onto the card edge.
        // (Tail tip sits 22pt left of the zone origin; the finger holds the
        // swatch, ~30pt into the row.)
        pull = TagPull(id: stop.id, offset: max(0, point.x + 22 - 30))
        Haptics.thud.impactOccurred()
        Haptics.warmUp()
        // Same spring as the "+" entrance — one voice for arriving tags.
        Task { @MainActor in
            withAnimation(.stopEnter) {
                if birthId == stop.id { pull.offset = 0 }
            }
        }
    }

    /// The tag's text: its hex at rest, morphing into the stop's % position
    /// while grabbed — the value takes focus, so it reads darker.
    private func label(for stop: SkyStop, showsPercent: Bool) -> some View {
        ZStack(alignment: .leading) {
            Text(stop.label)
                .foregroundStyle(Color.inkLabel)
                .opacity(showsPercent ? 0 : 1)
                .blur(radius: showsPercent ? 3 : 0)
                .offset(y: showsPercent ? -6 : 0)
            Text("\(Int((stop.location * 100).rounded()))%")
                .monospacedDigit()
                .foregroundStyle(Color(hex: 0x4A4A4A))
                .opacity(showsPercent ? 1 : 0)
                .blur(radius: showsPercent ? 0 : 3)
                .offset(y: showsPercent ? 0 : 6)
        }
        .font(.system(size: 24, weight: .bold, design: .rounded))
    }

    // MARK: - The grab

    /// Global space: the tag itself scales with the scene mid-grab, so its
    /// local space warps under the finger.
    private func grabGesture(for index: Int) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                // The docked tail (color sheet up) is a bare handle: vertical
                // drag moves the stop — no zoom, no hold, no label, no pull.
                if colorEditIndex == index {
                    if grabbedIndex == nil {
                        grabbedIndex = index
                        grabStartLocation = stops[index].location
                        lastTickPercent = Int((stops[index].location * 100).rounded())
                        atEdge = false
                        Haptics.warmUp()
                    }
                    move(index, to: grabStartLocation + value.translation.height / cardSize.height)
                    return
                }
                if grabbedIndex == nil {
                    withAnimation(.spring(duration: 0.15, bounce: 0)) {
                        grabbedIndex = index
                    }
                    grabStartLocation = stops[index].location
                    nextZ += 1
                    tagZ[index] = nextZ
                    Haptics.grab.prepare()
                    holdTask = Task {
                        try? await Task.sleep(for: EditMode.grabHoldDelay)
                        guard !Task.isCancelled else { return }
                        activate(index)
                    }
                }
                guard grabbedIndex == index else { return }
                let dx = value.translation.width, dy = value.translation.height
                if pull.id == stops[index].id {
                    updatePull(index, dx: dx)
                    return
                }
                if !grab.isZoomed {
                    // The first decisive movement picks the job: sideways
                    // pulls the tag off the card, up/down moves the stop.
                    if abs(dx) > EditMode.grabSlop && abs(dx) > abs(dy) {
                        holdTask?.cancel()
                        holdTask = nil
                        pull = TagPull(id: stops[index].id)
                        updatePull(index, dx: dx)
                        return
                    }
                    // A decisive drag doesn't wait for the hold.
                    guard abs(dy) > EditMode.grabSlop else { return }
                    activate(index)
                }
                // Screen points → stop location, through the scene zoom: the
                // finger stays glued to the magnified stop, which naturally
                // makes the adjustment finer.
                move(index, to: grabStartLocation + dy / (cardSize.height * EditMode.grabZoom))
            }
            .onEnded { _ in release() }
    }

    private func activate(_ index: Int) {
        holdTask?.cancel()
        holdTask = nil
        guard grabbedIndex == index, !grab.isZoomed else { return }
        // Anchor the scene zoom at the stop's tail tip, so that point holds
        // still while everything grows around it.
        let y = min(max(stops[index].location * cardSize.height, 20), cardSize.height - 20)
        grab.anchor = UnitPoint(x: (cardSize.width - 22) / cardSize.width,
                                y: y / cardSize.height)
        lastTickPercent = Int((stops[index].location * 100).rounded())
        atEdge = false
        Haptics.grab.impactOccurred()
        Haptics.warmUp()
        withAnimation(.stopGrab) {
            grab.isZoomed = true
        }
    }

    private func move(_ index: Int, to raw: CGFloat) {
        let old = stops[index].location
        let new = min(max(raw, 0), 1)
        stops[index].location = new

        // A tick every whole percent…
        let percent = Int((new * 100).rounded())
        if percent != lastTickPercent {
            Haptics.tick.selectionChanged()
            Haptics.tick.prepare()
            lastTickPercent = percent
        }
        // …a firm knock when leapfrogging another stop…
        let crossed = stops.indices.contains { i in
            i != index && (old - stops[i].location) * (new - stops[i].location) < 0
        }
        if crossed {
            Haptics.knock.impactOccurred()
            Haptics.knock.prepare()
        }
        // …and a thud on first contact with the card's ends.
        let edge = new == 0 || new == 1
        if edge && !atEdge {
            Haptics.thud.impactOccurred()
        }
        atEdge = edge
    }

    private func release() {
        holdTask?.cancel()
        holdTask = nil
        guard let index = grabbedIndex else { return }
        if let id = pull.id, stops.indices.contains(index), stops[index].id == id {
            endPull(index)
        } else if grab.isZoomed {
            Haptics.release.impactOccurred()
        } else if colorEditIndex == nil {
            // Let go before the hold committed and without moving: a tap.
            // (Docked-tail drags end silently.)
            onTap?(index)
        }
        withAnimation(.stopGrab) {
            grab.isZoomed = false
            grabbedIndex = nil
        }
    }

    // MARK: - The pull

    private func updatePull(_ index: Int, dx: CGFloat,
                            letGo: CGFloat = EditMode.removePullDistance) {
        let canRemove = stops.count > 1
        if dx < 0 {
            pull.offset = 0                              // into the card: a wall
        } else if !canRemove {
            pull.offset = dx * 0.25                      // the last color just resists
        } else {
            let detached = dx >= letGo
            if detached != pull.detached {
                pull.detached = detached
                if detached {
                    Haptics.thud.impactOccurred()
                } else {
                    Haptics.tick.selectionChanged()
                }
            }
            pull.offset = Self.displacement(dx, letGo: letGo)
        }
        pull.progress = canRemove ? min(max(dx / letGo, 0), 1) : 0
        // The color melts out of the sky in step with the finger, so by the
        // let-go point it has already visibly gone.
        grab.fadingIndex = index
        grab.fade = pull.progress
    }

    /// Magnet feel: the tag lags further behind the finger the closer it
    /// gets to the let-go point, then tracks it 1:1 from there. Continuous —
    /// the only thing that changes at the let-go point is the haptic.
    private static func displacement(_ dx: CGFloat,
                                     letGo: CGFloat = EditMode.removePullDistance) -> CGFloat {
        let r = EditMode.removeResistance
        guard dx < letGo else { return letGo * (1 - r) + (dx - letGo) }
        return dx * (1 - r * dx / letGo)
    }

    private func endPull(_ index: Int) {
        if pull.detached {
            // The card already shows the sky without it; only the tag leaves.
            Haptics.release.impactOccurred()
            grab.fadingIndex = nil
            grab.fade = 0
            withAnimation(.stopLeave) {
                stops.remove(at: index)
            } completion: {
                pull = TagPull()
            }
        } else {
            withAnimation(.stopSnapBack) {
                pull.offset = 0
                pull.progress = 0
            } completion: {
                pull = TagPull()
            }
            // Gradient colors don't ride SwiftUI animations, so the melt is
            // eased back by hand, in step with the snap.
            let start = grab.fade
            Task { @MainActor in
                let frames = 20
                for i in 1...frames {
                    try? await Task.sleep(for: .milliseconds(16))
                    let t = CGFloat(i) / CGFloat(frames)
                    grab.fade = start * (1 - t) * (1 - t)
                }
                grab.fade = 0
                grab.fadingIndex = nil
            }
        }
    }

    /// The tag pop, as a pure function of the slide progress. `Animatable`
    /// so the appear-window mapping is re-evaluated every frame of an
    /// animated settle — otherwise SwiftUI would just cross-fade the endpoint
    /// opacity/scale over the whole slide and the bloom-from-the-tip is lost.
    private struct TagBloom: ViewModifier, Animatable {
        var progress: CGFloat

        var animatableData: CGFloat {
            get { progress }
            set { progress = newValue }
        }

        func body(content: Content) -> some View {
            let t = min(1, max(0, (progress - EditMode.tagsAppearAt) / EditMode.tagsAppearWindow))
            content
                // Anchor at the tail tip: leading edge, vertical center.
                .scaleEffect(EditMode.tagStartScale + (1 - EditMode.tagStartScale) * t,
                             anchor: UnitPoint(x: 0, y: 0.5))
                .opacity(min(1, t * 4))
        }
    }
}

/// The white tag that marks one gradient stop in edit mode: a rounded body
/// with a tail pointing at the stop's spot on the card, holding a swatch of
/// the stop's color. Traced 1:1 from the Figma export.
struct StopTag: View {
    let color: Color

    /// The shape's natural size once rotated tail-leading (from the SVG:
    /// a 40pt-wide upright tag, 57.15pt tall, rotated −90°).
    static let size = CGSize(width: 57.15, height: 40)

    var body: some View {
        StopTagShape()
            .fill(.white)
            // The Figma triple shadow: 22/15% + 11/5% + 5.5/5% blurs.
            .shadow(color: .black.opacity(0.15), radius: 11, y: 5.5)
            .shadow(color: .black.opacity(0.05), radius: 5.5, y: 2.75)
            .shadow(color: .black.opacity(0.05), radius: 2.75, y: 1.375)
            .overlay {
                // Swatch metrics from the export: 34.55×35.63, rx 5,
                // sitting in the body with ~2.7pt white margins.
                RoundedRectangle(cornerRadius: 5)
                    .fill(color)
                    .frame(width: 35.63, height: 34.55)
                    .offset(x: 7.95)
            }
            .frame(width: Self.size.width, height: Self.size.height)
    }
}

/// The tag outline, transcribed verbatim from the Figma SVG path (drawn
/// upright with the tail at the top, exactly as exported) and rotated −90°
/// so the tail points leading — the same way the layer is rotated in Figma.
struct StopTagShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 22, y: 37.8239))
        p.addCurve(to: CGPoint(x: 22.2396, y: 33.8002),
                   control1: CGPoint(x: 22, y: 35.7794),
                   control2: CGPoint(x: 22, y: 34.7571))
        p.addCurve(to: CGPoint(x: 23.2758, y: 31.4094),
                   control1: CGPoint(x: 22.4521, y: 32.952),
                   control2: CGPoint(x: 22.8021, y: 32.1443))
        p.addCurve(to: CGPoint(x: 26.0482, y: 28.4833),
                   control1: CGPoint(x: 23.8103, y: 30.5802),
                   control2: CGPoint(x: 24.5563, y: 29.8813))
        p.addLine(to: CGPoint(x: 33.2482, y: 21.7372))
        p.addCurve(to: CGPoint(x: 39.6271, y: 16.86),
                   control1: CGPoint(x: 36.3304, y: 18.8492),
                   control2: CGPoint(x: 37.8716, y: 17.4053))
        p.addCurve(to: CGPoint(x: 44.3729, y: 16.86),
                   control1: CGPoint(x: 41.1726, y: 16.38),
                   control2: CGPoint(x: 42.8274, y: 16.38))
        p.addCurve(to: CGPoint(x: 50.7518, y: 21.7372),
                   control1: CGPoint(x: 46.1284, y: 17.4053),
                   control2: CGPoint(x: 47.6696, y: 18.8492))
        p.addLine(to: CGPoint(x: 57.9518, y: 28.4833))
        p.addCurve(to: CGPoint(x: 60.7242, y: 31.4094),
                   control1: CGPoint(x: 59.4437, y: 29.8813),
                   control2: CGPoint(x: 60.1897, y: 30.5802))
        p.addCurve(to: CGPoint(x: 61.7604, y: 33.8002),
                   control1: CGPoint(x: 61.1979, y: 32.1443),
                   control2: CGPoint(x: 61.5479, y: 32.952))
        p.addCurve(to: CGPoint(x: 62, y: 37.8239),
                   control1: CGPoint(x: 62, y: 34.7571),
                   control2: CGPoint(x: 62, y: 35.7794))
        p.addLine(to: CGPoint(x: 62, y: 60.7272))
        p.addCurve(to: CGPoint(x: 61.1281, y: 69.1591),
                   control1: CGPoint(x: 62, y: 65.2076),
                   control2: CGPoint(x: 62, y: 67.4478))
        p.addCurve(to: CGPoint(x: 57.6319, y: 72.6553),
                   control1: CGPoint(x: 60.3611, y: 70.6644),
                   control2: CGPoint(x: 59.1372, y: 71.8883))
        p.addCurve(to: CGPoint(x: 49.2, y: 73.5272),
                   control1: CGPoint(x: 55.9206, y: 73.5272),
                   control2: CGPoint(x: 53.6804, y: 73.5272))
        p.addLine(to: CGPoint(x: 34.8, y: 73.5272))
        p.addCurve(to: CGPoint(x: 26.3681, y: 72.6553),
                   control1: CGPoint(x: 30.3196, y: 73.5272),
                   control2: CGPoint(x: 28.0794, y: 73.5272))
        p.addCurve(to: CGPoint(x: 22.8719, y: 69.1591),
                   control1: CGPoint(x: 24.8628, y: 71.8883),
                   control2: CGPoint(x: 23.6389, y: 70.6644))
        p.addCurve(to: CGPoint(x: 22, y: 60.7272),
                   control1: CGPoint(x: 22, y: 67.4478),
                   control2: CGPoint(x: 22, y: 65.2076))
        p.closeSubpath()

        // SVG space → tail-leading: shift the 40×57.15 box to the origin,
        // rotate −90° ((x, y) → (y, 40 − x)), then fit to `rect`.
        let toOrigin = CGAffineTransform(translationX: -22, y: -16.38)
        let rotate = CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 40)
        let fit = CGAffineTransform(scaleX: rect.width / StopTag.size.width,
                                    y: rect.height / StopTag.size.height)
            .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY))
        return p.applying(toOrigin.concatenating(rotate).concatenating(fit))
    }
}

#Preview {
    VStack(spacing: 24) {
        StopTag(color: Color(hex: 0xA6CADF))
        StopTag(color: Color(hex: 0xDA9096))
        StopTag(color: Color(hex: 0xEFB291))
    }
    .padding(60)
    .background(Color.canvas)
}
