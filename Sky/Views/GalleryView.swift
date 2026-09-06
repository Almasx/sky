import SwiftUI

/// The home screen: a two-column grid of captured sky gradients.
///
/// Opening a gradient uses a custom hero transition: the tapped card itself
/// morphs into the detail layout (like a photo opening in Photos) while the
/// canvas and chrome fade in around it.
struct GalleryView: View {
    @State private var selection: SkyGradient?
    @State private var cellFrames: [Int: CGRect] = [:]
    @State private var isCreating = false
    @State private var plusFrame: CGRect = .zero

    private let items = SkyGradient.samples
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
                        Button {
                            selection = item
                        } label: {
                            GradientCard(item: item)
                                .aspectRatio(177.0 / 234.0, contentMode: .fit)
                        }
                        .buttonStyle(CardPressStyle())
                        .onGeometryChange(for: CGRect.self) { proxy in
                            proxy.frame(in: .global)
                        } action: { frame in
                            cellFrames[item.id] = frame
                        }
                        // The hero layer stands in for the cell while open.
                        .opacity(selection?.id == item.id ? 0 : 1)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 32)
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
                    autoCloseAfter: debugAutoClose
                ) {
                    isCreating = false
                }
            }

            GlassIconButton(systemName: "plus") { isCreating = true }
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
                    autoCloseAfter: debugAutoClose
                ) {
                    selection = nil
                }
            }

        }
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
        #endif
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
