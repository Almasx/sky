import SwiftUI

/// View mode, implemented as a hero overlay.
///
/// The gradient card itself animates from its grid cell to the detail layout —
/// only the card moves, the canvas and chrome simply fade. The card is a live,
/// grabbable object the whole time: drag it anywhere to pull it out of place,
/// let go to snap back, or flick/pull far enough to send it home to its cell.
///
/// Dragging the card horizontally slides it into edit mode: the card pins
/// against the leading edge and a tag pops out of each gradient stop, showing
/// its swatch and hex. Drag back (or flick right) to return to view mode.
struct GradientDetailOverlay: View {
    let item: SkyGradient
    let sourceFrame: CGRect
    /// The gallery "+" button's frame — a twin of it renders above the card
    /// so the card slides beneath the glass on its way home.
    var plusFrame: CGRect = .zero
    var autoCloseAfter: Double? = nil
    /// Called with the edited stops as the card heads home — edits autosave.
    var onSave: ([SkyStop]) -> Void = { _ in }
    let onClosed: () -> Void

    @State private var isExpanded = false
    @State private var dragOffset: CGSize = .zero
    /// 0 = view mode, 1 = edit mode; scrubbed live by horizontal drags.
    @State private var editProgress: CGFloat = 0
    /// The committed mode — flips only when a slide settles, not mid-scrub.
    @State private var isEditing = false
    /// Which way the current drag committed on its first movement.
    @State private var dragAxis: Axis?
    @State private var editDragBase: CGFloat = 0
    /// Stop edits diverge from `item` once the user sculpts a stop.
    @State private var editedStops: [SkyStop]?
    /// Whole-scene zoom while a stop tag is grabbed.
    @State private var grab = StopGrab()
    /// Bumps as each added stop lands — fires the landing haptic.
    @State private var landedStops = 0
    /// The stop whose color is being edited: tapping a tag slides the card
    /// back to full width and raises the Choose-color sheet.
    @State private var colorEdit: ColorEditTarget?
    /// The docked tag, outliving `colorEdit` through the slide back into edit
    /// mode — otherwise the tag re-blooms mid-dismissal and pops in size.
    @State private var dockedStop: Int?
    /// Heading home: the sheet's dismissal mustn't run the edit-mode slide.
    @State private var isClosing = false
    /// The header ✕'s frame while picking: its touches cancel, not pick.
    @State private var cancelFrame: CGRect = .zero
    /// The eyedropper pass, if one is running.
    @State private var eyedropper = EyedropperSession()

    private var stops: [SkyStop] { editedStops ?? item.stops }
    /// What the card draws: the stops, with any stop being pulled off
    /// melted into its surroundings.
    private var displayStops: [SkyStop] { stops.fading(grab.fadingIndex, by: grab.fade) }

    var body: some View {
        ZStack {
            Color.canvas
                .opacity(backgroundOpacity)
                .ignoresSafeArea()

            // Hero card layer, in screen coordinates.
            GeometryReader { proxy in
                let rect = heroRect(in: proxy.size)
                GradientCard(
                    item: SkyGradient(id: item.id, title: item.title, stops: displayStops),
                    cornerRadius: isExpanded ? 55 : 24,
                    labelOpacity: isExpanded ? 0 : 1
                )
                .frame(width: rect.width, height: rect.height)
                .overlay {
                    StopTagColumn(
                        stops: Binding(get: { stops }, set: { editedStops = $0 }),
                        cardSize: rect.size,
                        progress: editProgress,
                        grab: $grab,
                        colorEditIndex: dockedStop,
                        // Not part of the pick: gone for the whole pass.
                        hidesDocked: eyedropper.hidesTag,
                        onTap: openColorEdit
                    )
                }
                // Grabbing a stop zooms the whole scene — card and tag
                // together — around the grabbed stop.
                .scaleEffect(grab.isZoomed ? EditMode.grabZoom : 1, anchor: grab.anchor)
                // The drag shrink and slides are pure render-server
                // transforms — the card's layout size never changes during a
                // drag, so its contents render once and get reused.
                .scaleEffect(dragScale)
                .offset(cardTranslation(in: proxy.size))
                .position(x: rect.midX, y: rect.midY)
                .gesture(cardDrag(in: proxy.size))
            }
            .ignoresSafeArea()

            // Pixel-identical twin of the gallery's "+" button, drawn above
            // the card layer. The real button hides while the detail is open;
            // the twin fades in step with the fog, so the closing card slides
            // beneath the glass and lands with nothing left to snap.
            if plusFrame != .zero {
                GeometryReader { _ in
                    GlassIconButton(systemName: "plus")
                        .position(x: plusFrame.midX, y: plusFrame.midY)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .opacity(1 - backgroundOpacity)
            }

            // The working "+", in the very spot the twin occupies: while the
            // overlay is open it adds a color; on the way home it fades out
            // as the twin fades in, so it reads as one button that changed job.
            if plusFrame != .zero {
                GeometryReader { _ in
                    GlassIconButton(systemName: "plus") { addStop() }
                        .position(x: plusFrame.midX, y: plusFrame.midY)
                }
                .ignoresSafeArea()
                .opacity(chromeOpacity)
                .opacity(grab.isZoomed || colorEdit != nil || eyedropper.stop != nil ? 0 : 1)
                .allowsHitTesting(chromeOpacity > 0.5 && !grab.isZoomed && colorEdit == nil && eyedropper.stop == nil)
            }

            // The eyedropper's zoomed sky and glass lens: above the card,
            // below the header (the title holds its place through a pass, and
            // the header's trailing button is the pass's ✕) and the sheet.
            SkyEyedropper(
                stops: displayStops,
                cardFrame: { size in
                    let t = cardTranslation(in: size)
                    return heroRect(in: size).offsetBy(dx: t.width, dy: t.height)
                },
                session: eyedropper,
                cancelFrame: cancelFrame,
                onFinish: finishPick
            )

            header
                .opacity(chromeOpacity)
                // The chrome joins the fade-away while a stop is grabbed.
                .opacity(grab.isZoomed ? 0 : 1)
        }
        // A soft tap as the card commits either way: into edit mode or back.
        .sensoryFeedback(.impact(flexibility: .soft), trigger: isEditing)
        // A firm knock as a new stop's tag lands.
        .sensoryFeedback(.impact(flexibility: .rigid), trigger: landedStops)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: colorEdit?.id)
        // The Choose-color sheet, editing the tapped stop live. Native sheet:
        // detent, grabber, glass and swipe-to-dismiss come from the system.
        .sheet(item: $colorEdit, onDismiss: {
            if isClosing { return }
            // Dropped for the eyedropper, not closed: the card stays put.
            if eyedropper.swallowsDismiss {
                eyedropper.swallowsDismiss = false
                return
            }
            closeColorEdit()
        }) { target in
            // ✕ starts the card slide NOW, in step with the sheet's exit —
            // onDismiss (which also covers swipe) would only fire after it.
            ChooseColorSheet(hex: stopHexBinding(target.id), onPick: { startPick(target.id, from: $0) }) {
                closeColorEdit()
                colorEdit = nil
            }
                .presentationDetents([.height(ChooseColorSheet.height)])
                .presentationBackgroundInteraction(.enabled)
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            withAnimation(.heroOpen) {
                isExpanded = true
            }
        }
        .task {
            // Scripted dismissal for automated recordings.
            guard let delay = autoCloseAfter else { return }
            try? await Task.sleep(for: .seconds(delay))
            close()
        }
        #if DEBUG
        // Launch with SKY_AUTOPLAY_EDIT=1 (with SKY_AUTOPLAY_ITEM) to slide
        // into edit mode for automated screenshots/recordings.
        .task {
            guard ProcessInfo.processInfo.environment["SKY_AUTOPLAY_EDIT"] != nil else { return }
            try? await Task.sleep(for: .seconds(1))
            isEditing = true
            withAnimation(.editSlide) { editProgress = 1 }
        }
        #endif
    }

    // MARK: - Chrome

    private var header: some View {
        VStack {
            ZStack {
                Text(item.title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)

                HStack {
                    // Out of the way while picking: the ✕ is the way out.
                    GlassIconButton(systemName: "chevron.left") { close() }
                        .opacity(eyedropper.isPicking ? 0 : 1)
                        .allowsHitTesting(!eyedropper.isPicking)
                    Spacer()
                    // The pass's cancel, where the create header's ✓ sits.
                    if eyedropper.isPicking {
                        GlassIconButton(systemName: "xmark") { finishPick(nil) }
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                                cancelFrame = $0
                            }
                            .transition(.scale(scale: 0.4).combined(with: .opacity))
                    }
                }
                .animation(.glyphMorph, value: eyedropper.isPicking)
            }
            .padding(16)

            Spacer()
        }
    }

    // MARK: - Adding a color

    /// Figma-style add: a stop appears at the midpoint of the biggest gap,
    /// in the color already there, its tag sliding in from the right. From
    /// picture mode the card slides into stops first and the newcomer
    /// arrives a beat later, so it reads as the thing that just happened.
    /// The haptic fires when the tag lands, not when it's sent.
    private func addStop() {
        let fromPicture = !isEditing
        if fromPicture {
            isEditing = true
            withAnimation(.editSlide) { editProgress = 1 }
        }
        Task { @MainActor in
            if fromPicture { try? await Task.sleep(for: .milliseconds(250)) }
            withAnimation(.stopEnter) {
                editedStops = stops.addingStop()
            }
            try? await Task.sleep(for: .milliseconds(110))
            landedStops += 1
        }
    }

    // MARK: - Hero geometry

    /// The card's laid-out frame: its grid cell when collapsed, the detail
    /// layout when open. The drag pull, shrink, and edit slide sit on top as
    /// transforms (`dragScale` / `cardTranslation`), never in the layout.
    private func heroRect(in size: CGSize) -> CGRect {
        guard isExpanded else { return sourceFrame }

        // Detail layout from the design: full width minus 16pt margins,
        // 370:548.66 aspect, centered on screen.
        let width = size.width - 32
        let height = width * 548.66 / 370.0
        return CGRect(
            x: (size.width - width) / 2,
            y: (size.height - height) / 2,
            width: width,
            height: height
        )
    }

    /// Gentle shrink while the card is pulled out of place.
    private var dragScale: CGFloat {
        max(0.7, 1 - dragDistance / 1000)
    }

    /// The drag pull plus the edit-mode slide off the leading edge.
    private func cardTranslation(in size: CGSize) -> CGSize {
        CGSize(
            width: dragOffset.width - size.width * EditMode.hiddenFraction * editProgress,
            height: dragOffset.height - colorEditShift(in: size)
        )
    }

    /// While the color sheet is up, the card rides up just enough that the
    /// edited stop clears it — the card's aspect ratio never changes. Scaled
    /// by the slide progress, so it travels in lockstep with the slide.
    private func colorEditShift(in size: CGSize) -> CGFloat {
        guard let index = dockedStop, stops.indices.contains(index) else { return 0 }
        let rect = heroRect(in: size)
        let stopY = rect.minY + stops[index].location * rect.height
        let sheetTop = size.height - ChooseColorSheet.height
        return max(0, stopY - (sheetTop - 44)) * (1 - min(1, max(0, editProgress)))
    }

    private var dragDistance: CGFloat {
        hypot(dragOffset.width, dragOffset.height)
    }

    /// 0 at rest → 1 when the drag is clearly a dismissal.
    private var dragProgress: CGFloat {
        min(1, dragDistance / 260)
    }

    private var backgroundOpacity: Double {
        isExpanded ? 1 - 0.9 * dragProgress : 0
    }

    /// The chrome ducks out almost immediately once a drag starts.
    private var chromeOpacity: Double {
        isExpanded ? 1 - min(1, dragDistance / 90) : 0
    }

    // MARK: - Interaction

    /// One drag gesture, split by its opening direction: horizontal drags
    /// scrub the edit slide, vertical drags stay the grab-to-dismiss.
    private func cardDrag(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                // While the color sheet is up, the card holds still — the
                // sheet's own grabber/swipe is the way out.
                guard colorEdit == nil else { return }
                if dragAxis == nil {
                    let t = value.translation
                    // Once the card is pinned in edit mode, every drag slides.
                    dragAxis = editProgress > 0 || abs(t.width) > abs(t.height)
                        ? .horizontal : .vertical
                    editDragBase = editProgress
                }
                switch dragAxis {
                case .horizontal:
                    let shift = size.width * EditMode.hiddenFraction
                    var p = editDragBase - value.translation.width / shift
                    if p < 0 { p *= 0.3 }               // rubber-band past view…
                    if p > 1 { p = 1 + (p - 1) * 0.3 }  // …and past edit
                    editProgress = p
                case .vertical:
                    // Direct manipulation: the card tracks the finger 1:1.
                    dragOffset = value.translation
                case nil:
                    break
                }
            }
            .onEnded { value in
                guard colorEdit == nil else { return }
                defer { dragAxis = nil }
                switch dragAxis {
                case .horizontal:
                    // Flick wins; otherwise settle to the nearer state.
                    let shift = size.width * EditMode.hiddenFraction
                    let predicted = editDragBase - value.predictedEndTranslation.width / shift
                    isEditing = predicted > 0.5
                    withAnimation(.editSlide) {
                        editProgress = isEditing ? 1 : 0
                    }
                case .vertical:
                    let predicted = hypot(
                        value.predictedEndTranslation.width,
                        value.predictedEndTranslation.height
                    )
                    if predicted > 240 {
                        close()
                    } else {
                        withAnimation(.spring(duration: 0.4, bounce: 0.35)) {
                            dragOffset = .zero
                        }
                    }
                case nil:
                    break
                }
            }
    }

    // MARK: - Color editing

    /// A tag was tapped: the card slides back to full width — riding up if
    /// the stop would sit behind the sheet — with the tapped tag docked at
    /// its right edge, and the Choose-color sheet rises.
    private func openColorEdit(_ index: Int) {
        dockedStop = index
        withAnimation(.editSlide) {
            colorEdit = ColorEditTarget(id: index)
            editProgress = 0
        }
    }

    /// The sheet is gone (✕ or swipe): the card slides back into edit mode.
    /// The tag stays docked (full bloom, label hidden) until the slide lands,
    /// then hands back to the edit-mode look.
    private func closeColorEdit() {
        withAnimation(.editSlide) {
            editProgress = 1
        } completion: {
            guard colorEdit == nil else { return }   // already reopened
            withAnimation(.editSlide) {
                dockedStop = nil
            }
        }
    }

    // MARK: - Eyedropper

    /// The sheet's pipette: the sheet drops, the docked tag goes, and the sky
    /// zooms up. The card holds still beneath the zoom.
    private func startPick(_ index: Int, from button: CGRect) {
        eyedropper.begin(stop: index, from: CGPoint(x: button.midX, y: button.midY))
        colorEdit = nil
        withAnimation(.heroOpen) { eyedropper.isZoomed = true }
    }

    /// Lifted (a color) or cancelled (nil): the lens goes at once, the sky
    /// zooms back into the card and the sheet rises again, seeded from the
    /// stop as it now is. The tag rides back in on top of the sky's edge.
    private func finishPick(_ hex: UInt32?) {
        guard let index = eyedropper.stop else { return }
        if let hex { stopHexBinding(index).wrappedValue = hex }
        colorEdit = ColorEditTarget(id: index)
        // One motion home: the sky into the card, the lens into the pipette.
        // Hidden only once the spring has fully landed — a "logically
        // complete" spring still has a sliver of travel left.
        withAnimation(.heroClose, completionCriteria: .removed) {
            eyedropper.isPicking = false
            eyedropper.isZoomed = false
        } completion: {
            guard !eyedropper.isPicking else { return }   // picking again
            // The eyedropper's riding tag hands over to the real one, on the
            // same spot.
            eyedropper.hidesTag = false
            eyedropper.stop = nil
        }
    }

    private func stopHexBinding(_ index: Int) -> Binding<UInt32> {
        Binding(
            get: { stops[index].hex },
            set: { newHex in
                // Recolor in place: the stop keeps its identity, so its tag
                // stays the same view instead of leaving and re-entering.
                var edited = stops
                edited[index].hex = newHex
                editedStops = edited
            }
        )
    }

    private func close() {
        if let edited = editedStops { onSave(edited) }
        isEditing = false
        // The sheet (and any eyedropper pass) leaves with the card, not after
        // it lands; the ride-up unwinds on the card's own spring.
        isClosing = true
        colorEdit = nil
        eyedropper = EyedropperSession()
        withAnimation(.heroClose) {
            isExpanded = false
            dragOffset = .zero
            editProgress = 0
            dockedStop = nil
        } completion: {
            onClosed()
        }
    }
}

#Preview {
    GalleryView()
}
