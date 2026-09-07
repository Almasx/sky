import SwiftUI

/// The circular glass control used across the app — the system Liquid Glass
/// button style, which handles sizing, press response, refraction and shadow.
///
/// A button can carry a second glyph and swap to it — the gallery's "+"
/// becomes a "✓" while the grid is in jiggle mode. The swap isn't a true
/// morph: the outgoing glyph shrinks and blurs away as the incoming one
/// sharpens in behind it.
struct GlassIconButton: View {
    let systemName: String
    var alternateSystemName: String? = nil
    var showsAlternate = false
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            ZStack {
                glyph(systemName)
                    .swapped(out: showsAlternate)
                if let alternate = alternateSystemName {
                    glyph(alternate)
                        .swapped(out: !showsAlternate)
                }
            }
            .animation(.glyphMorph, value: showsAlternate)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.large)
    }

    private func glyph(_ name: String) -> some View {
        // Pushed past the Figma spec (19pt heavy, #B4B4B4) for a chunkier
        // glyph: black weight, rounded terminals to match the label type,
        // slightly larger, in the adaptive tertiary label ink.
        Image(systemName: name)
            .font(.system(size: 21, weight: .black, design: .rounded))
            .foregroundStyle(.tertiary)
    }
}

private extension View {
    /// Scale-and-blur crossfade, one side of it.
    func swapped(out: Bool) -> some View {
        self
            .scaleEffect(out ? 0.4 : 1)
            .blur(radius: out ? 6 : 0)
            .opacity(out ? 0 : 1)
    }
}

#Preview {
    @Previewable @State var done = false
    HStack(spacing: 24) {
        GlassIconButton(systemName: "chevron.left")
        GlassIconButton(systemName: "plus", alternateSystemName: "checkmark", showsAlternate: done) {
            done.toggle()
        }
        GlassIconButton(systemName: "arrow.uturn.backward")
    }
    .padding(60)
    .background(Color.canvas)
}
