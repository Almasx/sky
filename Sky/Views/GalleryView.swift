import SwiftUI

/// The home screen: a two-column grid of captured sky gradients.
///
/// Opening a gradient uses a custom hero transition: the tapped card itself
/// morphs into the detail layout (like a photo opening in Photos) while the
/// canvas and chrome fade in around it.
///
/// Hold a tile and the grid wakes into jiggle mode — the home-screen idiom:
/// every tile wobbles, a glass "−" lands on each, and the "+" becomes a "✓".
/// Tap a "−" to delete, drag a tile to move it; a "↺" appears bottom-left
/// once something has changed and puts the grid back the way it was. "✓" (or
/// a tap on the canvas) commits everything to the store in one go.
struct GalleryView: View {
    @State private var selection: SkyGradient?
    @State private var cellFrames: [Int: CGRect] = [:]
    @State private var isCreating = false
    @State private var plusFrame: CGRect = .zero

    @State private var store = SkyStore()

    // Jiggle mode.
    /// While the grid is awake, edits happen on this working copy; ✓ commits it.
    @State private var draft: [SkyGradient]?
    @State private var drag: TileDrag?
    /// A just-dropped tile's leftover offset, springing to zero.
    @State private var settling: TileSettle?
    /// Bumps per delete — fires the haptic.
    @State private var deletions = 0

    private var isJiggling: Bool { draft != nil }
    /// Anything to take back? The store holds the grid as it was on waking.
    private var hasChanges: Bool { draft.map { $0 != store.items } ?? false }
    private var items: [SkyGradient] { draft ?? store.items }
    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
    ]

    var body: some View {
        // Layer order, bottom to top: grid → create overlay → the "+" button
        // → detail overlay. While an overlay is open the real button hides
        // and a pixel-identical twin inside the overlay stands in for it,
        // fading with the fog so the handoff is invisible.
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(items) { item in
                        tile(item)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 32)
                // The empty canvas between and around the tiles: hold it to
                // wake the grid, tap it to settle.
                .background {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { if isJiggling { exitJiggle() } }
                        .onLongPressGesture(minimumDuration: Jiggle.holdDuration) { enterJiggle() }
                }
            }
            .background(Color.canvas.ignoresSafeArea())
            // Native progressive blur where content runs under the bottom bar.
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .safeAreaBar(edge: .bottom, alignment: .trailing) {
                // Invisible twin of the "+" button: reserves the bar space so
                // scroll content insets correctly, while the real button draws
                // in the top layer of the ZStack.
                GlassIconButton(systemName: "plus")
                    .hidden()
                    .padding(.trailing, 20)
            }

            if isCreating {
                GradientCreateOverlay(
                    sourceFrame: plusFrame,
                    autoCloseAfter: debugAutoClose,
                    onSave: { title, stops in store.add(title: title, stops: stops) }
                ) {
                    isCreating = false
                }
            }

            // ↺: mirrors the "+", only there once there's something to take back.
            if hasChanges {
                GlassIconButton(systemName: "arrow.uturn.backward") { revert() }
                    .padding(.leading, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }

            // The "+" — a "✓" while the grid is awake.
            GlassIconButton(
                systemName: "plus",
                alternateSystemName: "checkmark",
                showsAlternate: isJiggling
            ) {
                if isJiggling { exitJiggle() } else { isCreating = true }
            }
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { frame in
                plusFrame = frame
            }
            // While an overlay is open its twin stands in for the button
            // (pixel-identical, so the handoff is invisible).
            .opacity(selection == nil && !isCreating ? 1 : 0)
            .allowsHitTesting(!isCreating && selection == nil)
            .padding(.trailing, 20)

            if let item = selection {
                GradientDetailOverlay(
                    item: item,
                    sourceFrame: cellFrames[item.id] ?? .zero,
                    plusFrame: plusFrame,
                    autoCloseAfter: debugAutoClose,
                    onSave: { stops in store.update(item.id, stops: stops) }
                ) {
                    selection = nil
                }
            }

        }
        // A firm knock as the grid wakes, a soft tap as it settles.
        .sensoryFeedback(trigger: isJiggling) { _, awake in
            awake ? .impact(flexibility: .rigid) : .impact(flexibility: .soft)
        }
        // A tick as a dragged tile claims a new slot, and as a tile is deleted.
        .sensoryFeedback(.selection, trigger: drag?.to)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: deletions)
        #if DEBUG
        // Scripted navigation for automated screenshots/recordings:
        // launch with SKY_AUTOPLAY_ITEM=<index> to zoom into that gradient.
        .task {
            guard let value = ProcessInfo.processInfo.environment["SKY_AUTOPLAY_ITEM"],
                  let index = Int(value), items.indices.contains(index) else { return }
            try? await Task.sleep(for: .seconds(1.5))
            selection = items[index]
        }
        // Launch with SKY_AUTOPLAY_CREATE=1 to open create mode.
        .task {
            guard ProcessInfo.processInfo.environment["SKY_AUTOPLAY_CREATE"] != nil else { return }
            try? await Task.sleep(for: .seconds(1.5))
            isCreating = true
        }
        // Launch with SKY_AUTOPLAY_JIGGLE=1 to wake the grid.
        .task {
            guard ProcessInfo.processInfo.environment["SKY_AUTOPLAY_JIGGLE"] != nil else { return }
            try? await Task.sleep(for: .seconds(1.5))
            enterJiggle()
        }
        #endif
    }

    // MARK: - Tiles

    private func tile(_ item: SkyGradient) -> some View {
        let lifted = drag?.id == item.id || settling?.id == item.id
        return Button {
            // Taps do nothing while the grid is awake — the badge and the
            // drag are the controls; the "+" (now "✓") is the way out.
            guard !isJiggling else { return }
            selection = item
        } label: {
            GradientCard(item: item)
                .aspectRatio(177.0 / 234.0, contentMode: .fit)
        }
        .buttonStyle(CardPressStyle())
        // The badge rides the wobble with the card (one object, like a home
        // screen icon) but sits outside the press-down scale — a tap on it
        // must not shrink it.
        .overlay(alignment: .topLeading) {
            if isJiggling {
                DeleteBadge { delete(item) }
                    .padding(Jiggle.badgeInset - 7)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        // The picked-up tile stops wobbling and lifts under the finger.
        .modifier(Wobble(isOn: isJiggling && drag?.id != item.id))
        .scaleEffect(lifted ? Jiggle.liftScale : 1)
        // Radius 0 when down: a blurred shadow, even a clear one, is an
        // offscreen pass per frame on every wobbling tile.
        .shadow(color: .black.opacity(lifted ? 0.22 : 0), radius: lifted ? 20 : 0, y: lifted ? 10 : 0)
        .offset(offset(for: item))
        .zIndex(lifted ? 1 : 0)
        // Asleep: holding the tile wakes the grid. (The button still fires on
        // release, into the guard above.) Awake: dragging it moves it.
        .simultaneousGesture(
            LongPressGesture(minimumDuration: Jiggle.holdDuration)
                .onEnded { _ in enterJiggle() },
            including: isJiggling ? .subviews : .all
        )
        .highPriorityGesture(tileDrag(item), including: isJiggling ? .all : .subviews)
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            cellFrames[item.id] = frame
        }
        // The hero layer stands in for the cell while open.
        .opacity(selection?.id == item.id ? 0 : 1)
        .transition(.asymmetric(
            insertion: .scale(scale: 0.8).combined(with: .opacity).animation(.tileReturn),
            removal: .scale(scale: 0.01).combined(with: .opacity).animation(.tileVanish)
        ))
    }

    // MARK: - Jiggle mode

    private func enterJiggle() {
        guard draft == nil else { return }
        withAnimation(.badgePop) { draft = store.items }
    }

    /// ✓: everything settles and the changes land in the store together.
    private func exitJiggle() {
        guard let edited = draft, drag == nil else { return }
        store.replaceAll(edited)
        withAnimation(.gridReflow) { draft = nil }
    }

    private func delete(_ item: SkyGradient) {
        guard var edited = draft else { return }
        edited.removeAll { $0.id == item.id }
        deletions += 1
        withAnimation(.gridReflow) { draft = edited }
    }

    /// ↺: the grid goes back to how it was on waking — deleted tiles grow
    /// back into their slots, moved ones slide home.
    private func revert() {
        guard isJiggling else { return }
        withAnimation(.gridReflow) { draft = store.items }
    }

    // MARK: - Moving a tile

    /// While a tile is dragged nothing moves in the array: the dragged tile
    /// rides the finger and the others are *offset* into the slots they'd
    /// take, so the whole thing is one spring per slot change. The array
    /// only changes on drop, in a transaction that changes nothing on screen.
    private func tileDrag(_ item: SkyGradient) -> some Gesture {
        DragGesture(minimumDistance: Jiggle.dragSlop, coordinateSpace: .global)
            .onChanged { value in
                if drag == nil {
                    guard let from = items.firstIndex(where: { $0.id == item.id }) else { return }
                    let slots = items.compactMap { cellFrames[$0.id] }
                    guard slots.count == items.count else { return }
                    withAnimation(.tileLift) {
                        drag = TileDrag(id: item.id, from: from, slots: slots, to: from)
                    }
                }
                guard var d = drag, d.id == item.id else { return }
                d.translation = value.translation
                let center = CGPoint(
                    x: d.slots[d.from].midX + d.translation.width,
                    y: d.slots[d.from].midY + d.translation.height
                )
                let nearest = d.slots.indices.min {
                    hypot(d.slots[$0].midX - center.x, d.slots[$0].midY - center.y)
                        < hypot(d.slots[$1].midX - center.x, d.slots[$1].midY - center.y)
                } ?? d.from
                if nearest != d.to {
                    d.to = nearest
                    withAnimation(.gridReflow) { drag = d }
                } else {
                    drag = d
                }
            }
            .onEnded { _ in drop() }
    }

    private func drop() {
        guard let d = drag, let edited = draft else { return }
        var moved = edited
        moved.insert(moved.remove(at: d.from), at: d.to)
        // The tile is wherever the finger left it; hand that position over to
        // `settling` so the array move itself changes nothing on screen…
        let leftover = CGSize(
            width: d.slots[d.from].minX + d.translation.width - d.slots[d.to].minX,
            height: d.slots[d.from].minY + d.translation.height - d.slots[d.to].minY
        )
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) {
            draft = moved
            drag = nil
            settling = TileSettle(id: d.id, offset: leftover)
        }
        // …then it springs the last bit into its slot.
        withAnimation(.gridReflow) { settling = nil }
    }

    /// Where a tile draws relative to its cell: the dragged one follows the
    /// finger, the ones between it and its target slot shift by one cell.
    private func offset(for item: SkyGradient) -> CGSize {
        if let s = settling, s.id == item.id { return s.offset }
        guard let d = drag, let i = items.firstIndex(where: { $0.id == item.id }) else { return .zero }
        if item.id == d.id { return d.translation }
        var j = i
        if d.from < d.to, i > d.from, i <= d.to { j = i - 1 }
        else if d.to < d.from, i >= d.to, i < d.from { j = i + 1 }
        guard j != i else { return .zero }
        return CGSize(
            width: d.slots[j].minX - d.slots[i].minX,
            height: d.slots[j].minY - d.slots[i].minY
        )
    }

    private var debugAutoClose: Double? {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        guard env["SKY_AUTOPLAY_ITEM"] != nil || env["SKY_AUTOPLAY_CREATE"] != nil else { return nil }
        // Leave edit mode on screen longer — it opens 1s into the overlay.
        return env["SKY_AUTOPLAY_EDIT"] != nil ? 8 : 2.5
        #else
        nil
        #endif
    }

}

/// A tile being dragged to a new slot.
private struct TileDrag {
    let id: Int
    let from: Int
    /// Every cell's frame as the drag began — the slots, which stay put
    /// while the tiles move between them.
    let slots: [CGRect]
    var translation: CGSize = .zero
    var to: Int
}

/// A dropped tile's leftover offset, springing to zero.
private struct TileSettle {
    let id: Int
    let offset: CGSize
}

/// One gradient tile — reused by the grid and by the hero transition layer.
struct GradientCard: View {
    let item: SkyGradient
    var cornerRadius: CGFloat = 24
    var labelOpacity: Double = 1
    /// 0 = rounded rect, 1 = a true circle — see `CardShape`.
    var circleness: CGFloat = 0

    var body: some View {
        item.linearGradient
            .overlay(alignment: .bottomLeading) {
                Text(item.title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.inkMuted)
                    .blendMode(.overlay)
                    .padding(.leading, 12)
                    .padding(.bottom, 15)
                    .opacity(labelOpacity)
            }
            .clipShape(CardShape(cornerRadius: cornerRadius, circleness: circleness))
    }
}

/// Card clip that can morph from a rounded rectangle into a true circle.
///
/// At `circleness` 1 the path is a circle of the bounds' smaller dimension,
/// centered — not a capsule — so mid-flight frames of the hero trip home read
/// as an actual circle even while the frame is still taller than it is wide.
struct CardShape: Shape {
    var cornerRadius: CGFloat
    var circleness: CGFloat = 0

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(cornerRadius, circleness) }
        set {
            cornerRadius = newValue.first
            circleness = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let width = rect.width + (side - rect.width) * circleness
        let height = rect.height + (side - rect.height) * circleness
        let box = CGRect(
            x: rect.midX - width / 2,
            y: rect.midY - height / 2,
            width: width,
            height: height
        )
        let radius = cornerRadius + (min(width, height) / 2 - cornerRadius) * circleness
        return RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: box)
    }
}

/// Gentle Photos-style press-down on the grid tiles.
struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .animation(.snappy(duration: 0.25, extraBounce: 0.1), value: configuration.isPressed)
    }
}

#Preview {
    GalleryView()
}
