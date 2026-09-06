import SwiftUI

/// The circular glass control used across the app — the system Liquid Glass
/// button style, which handles sizing, press response, refraction and shadow.
struct GlassIconButton: View {
    let systemName: String
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            // Pushed past the Figma spec (19pt heavy, #B4B4B4) for a chunkier
            // glyph: black weight, rounded terminals to match the label type,
            // slightly larger, in the adaptive tertiary label ink.
            Image(systemName: systemName)
                .font(.system(size: 21, weight: .black, design: .rounded))
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.large)
    }
}

#Preview {
    HStack(spacing: 24) {
        GlassIconButton(systemName: "chevron.left")
        GlassIconButton(systemName: "plus")
        GlassIconButton(systemName: "checkmark")
    }
    .padding(60)
    .background(Color.canvas)
}
