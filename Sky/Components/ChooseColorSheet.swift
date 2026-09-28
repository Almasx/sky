import SwiftUI
import UIKit

/// Which stop the Choose-color sheet is editing. `Identifiable` so each
/// presentation gets a fresh sheet, seeded from that stop's color.
struct ColorEditTarget: Identifiable {
    let id: Int
}

/// The color-edit sheet from the Figma (153:227): hue / saturation /
/// lightness sliders with value pills, editing one stop live. Presented as a
/// native sheet — detent, grabber, glass background and dismissal all come
/// from the system; only the content is ours.
///
/// Interaction tuned live in prototypes/color-edit.html; the header, the
/// eyedropper and the hue wake in prototypes/color-picker.html.
struct ChooseColorSheet: View {
    @Binding var hex: UInt32
    /// The eyedropper, with the pipette button's frame (global) — the lens
    /// flies out of it and back into it.
    var onPick: (CGRect) -> Void
    var onClose: () -> Void

    /// The sheet's single detent. Toolbar 68 + rows 44×3 + gaps 20×2 + 16
    /// above + 16 below — as tight as the bottom goes without the last
    /// slider fighting the home-indicator swipe.
    static let height: CGFloat = 272

    @State private var hsb: HSBColor
    @State private var pipetteFrame: CGRect = .zero

    init(hex: Binding<UInt32>, onPick: @escaping (CGRect) -> Void, onClose: @escaping () -> Void) {
        _hex = hex
        self.onPick = onPick
        self.onClose = onClose
        _hsb = State(initialValue: HSBColor(hex: hex.wrappedValue))
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            VStack(spacing: 20) {
                row(
                    fraction: wakingHue.fraction(over: 360),
                    display: wakingHue,
                    range: 360,
                    track: Self.hueTrack,
                    thumb: HSBColor(hue: hsb.hue, saturation: 1, brightness: 1).color
                )
                row(
                    fraction: $hsb.saturation,
                    display: $hsb.saturation.scaled(by: 100),
                    range: 100,
                    track: [
                        HSBColor(hue: hsb.hue, saturation: 0, brightness: hsb.brightness).color,
                        HSBColor(hue: hsb.hue, saturation: 1, brightness: hsb.brightness).color,
                    ],
                    thumb: hsb.color
                )
                row(
                    fraction: $hsb.brightness,
                    display: $hsb.brightness.scaled(by: 100),
                    range: 100,
                    track: [
                        .black,
                        HSBColor(hue: hsb.hue, saturation: hsb.saturation, brightness: 1).color,
                    ],
                    thumb: hsb.color
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
        // As tight as it goes: a fixed 16 from the sheet's real bottom edge,
        // under the home-indicator inset. Ignoring the keyboard region too
        // keeps the rows from reflowing when the number pad rises.
        .padding(.bottom, 16)
        .frame(maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea([.container, .keyboard], edges: .bottom)
        // No Done bar: typing applies live, so tapping anywhere else simply
        // puts the keyboard away.
        .contentShape(Rectangle())
        .onTapGesture {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil, from: nil, for: nil
            )
        }
        .onChange(of: hsb) {
            hex = hsb.hex
        }
        // A color from outside (the eyedropper): the thumbs glide to it.
        .onChange(of: hex) {
            guard hex != hsb.hex else { return }
            withAnimation(.stopGrab) { hsb = HSBColor(hex: hex) }
        }
        // A tick every whole displayed unit, on any slider.
        .onChange(of: displayedValues) { old, new in
            if old != new { Haptics.tick.selectionChanged() }
            Haptics.tick.prepare()
        }
    }

    /// Below this, saturation or brightness counts as zero — tuned to 1%.
    private static let grayBelow = 0.01

    /// Hue, waking the color out of gray. On a gray (saturation 0) or black
    /// (brightness 0) every hue is the same color, so the slider would move
    /// and change nothing. Instead the first hue move lifts saturation to
    /// full (and black to half brightness); those thumbs glide there, so you
    /// see where the color came from.
    private var wakingHue: Binding<Double> {
        Binding(
            get: { hsb.hue },
            set: { hue in
                if hsb.saturation < Self.grayBelow || hsb.brightness < Self.grayBelow {
                    withAnimation(.stopGrab) {
                        if hsb.saturation < Self.grayBelow { hsb.saturation = 1 }
                        if hsb.brightness < Self.grayBelow { hsb.brightness = 0.5 }
                    }
                }
                hsb.hue = hue
            }
        )
    }

    /// The Figma rainbow track: 12 even hue steps.
    private static let hueTrack: [Color] = (0...12).map {
        HSBColor(hue: Double($0) * 30, saturation: 1, brightness: 1).color
    }

    private var displayedValues: [Int] {
        [Int(hsb.hue.rounded()),
         Int((hsb.saturation * 100).rounded()),
         Int((hsb.brightness * 100).rounded())]
    }

    /// Eyedropper leading, the title centered, ✕ trailing.
    private var toolbar: some View {
        ZStack {
            // Semantic ink, like the header title — never hardcoded in modals.
            // Small and centered — a step under the screen headers' 24.
            Text("Choose color")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            HStack {
                iconButton(action: { onPick(pipetteFrame) }) {
                    // The system symbol, in the ✕'s exact treatment.
                    Image(systemName: "eyedropper.full")
                        .font(.system(size: 19, weight: .black, design: .rounded))
                }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                    pipetteFrame = $0
                }
                Spacer()
                iconButton(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 19, weight: .black, design: .rounded))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    /// The GlassIconButton glyph treatment (black, rounded, tertiary ink), a
    /// step smaller for the sheet.
    private func iconButton(action: @escaping () -> Void, @ViewBuilder glyph: () -> some View) -> some View {
        Button(action: action) {
            glyph()
                .foregroundStyle(.tertiary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(.quaternary.opacity(0.4)))
        }
        .buttonStyle(.plain)
    }

    /// One slider row: gradient track + the value pill (scrub it sideways
    /// for fine adjustment).
    private func row(
        fraction: Binding<Double>,
        display: Binding<Double>,
        range: Double,
        track: [Color],
        thumb: Color
    ) -> some View {
        HStack(spacing: 12) {
            ColorSlider(fraction: fraction, track: track, thumb: thumb)
            ValuePill(display: display, range: range)
        }
    }
}

/// A value pill that is both a scrubber and a field: drag sideways to nudge
/// the value (3pt per unit), tap to type it on the number pad. Typing updates
/// the color live; the value clamps to its range.
private struct ValuePill: View {
    @Binding var display: Double
    let range: Double

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            // The field only surfaces while typing — a resting TextField
            // ignores hierarchical styles and renders the value near-black.
            TextField("", text: $text)
                .keyboardType(.numberPad)
                .focused($focused)
                .multilineTextAlignment(.center)
                .opacity(focused ? 1 : 0)
            if !focused || text.isEmpty {
                // The value at rest — and its ghost while awaiting a digit.
                Text(value)
                    .foregroundStyle(.secondary)
                    .opacity(focused ? 0.35 : 1)
                    .allowsHitTesting(false)
            }
        }
        .font(.system(size: 24, weight: .bold, design: .rounded))
        .monospacedDigit()
        .frame(width: 85, height: 44)
        .background(Capsule().fill(.quaternary.opacity(0.55)))
        .contentShape(Capsule())
        .onTapGesture { focused = true }
        .highPriorityGesture(scrub)
        .onChange(of: focused) { _, isFocused in
            // Editing starts from a blank field (the old value stays as a
            // ghost); an empty commit keeps the old value.
            if isFocused { text = "" }
        }
        .onChange(of: text) {
            guard focused, let typed = Double(text) else { return }
            display = min(max(typed, 0), range)
        }
    }

    private var value: String {
        "\(Int(display.rounded()))"
    }

    private var scrub: some Gesture {
        var base: Double?
        return DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard !focused else { return }
                if base == nil { base = display }
                display = min(max((base ?? 0) + value.translation.width / 3, 0), range)
            }
            .onEnded { _ in base = nil }
    }
}

/// One gradient-track slider: a 44pt capsule with a ringed 36pt thumb that
/// spikes up while dragged (the grow tuned in the prototype).
private struct ColorSlider: View {
    @Binding var fraction: Double
    let track: [Color]
    let thumb: Color

    @GestureState private var isDragging = false

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(colors: track, startPoint: .leading, endPoint: .trailing))
                ColorThumb(color: thumb)
                    .scaleEffect(isDragging ? 1.15 : 1)
                    .offset(x: 4 + fraction * (width - 44))
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isDragging) { _, state, _ in state = true }
                    .onChanged { value in
                        fraction = min(max((value.location.x - 22) / (width - 44), 0), 1)
                    }
            )
        }
        .frame(height: 44)
        .animation(.stopGrab, value: isDragging)
    }
}

/// The slider thumb: a 36pt ringed disc of the color. Also marks the
/// eyedropper lens's sampled point — the thumb you're about to set.
struct ColorThumb: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .overlay(Circle().stroke(.white, lineWidth: 3))
            .frame(width: 36, height: 36)
            // Flatten first, or the ring casts its own shadow inward
            // onto the fill; the shadow belongs to the thumb as one.
            .compositingGroup()
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            .shadow(color: .black.opacity(0.18), radius: 7, y: 3)
    }
}

// MARK: - HSB working space

/// The picker edits in HSB — the same axes as Figma's own color picker, so
/// values cross-check 1:1 with the design tool; stops store hex.
struct HSBColor: Equatable {
    /// Degrees, 0–360.
    var hue: Double
    var saturation: Double
    var brightness: Double

    init(hue: Double, saturation: Double, brightness: Double) {
        self.hue = hue
        self.saturation = saturation
        self.brightness = brightness
    }

    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        let hi = max(r, g, b), lo = min(r, g, b)
        let d = hi - lo
        brightness = hi
        saturation = hi == 0 ? 0 : d / hi
        guard d > 0 else {
            hue = 0
            return
        }
        switch hi {
        case r: hue = (((g - b) / d).truncatingRemainder(dividingBy: 6) * 60)
            .truncatingRemainder(dividingBy: 360)
        case g: hue = ((b - r) / d + 2) * 60
        default: hue = ((r - g) / d + 4) * 60
        }
        if hue < 0 { hue += 360 }
    }

    private var rgb: (Double, Double, Double) {
        let c = brightness * saturation
        let x = c * (1 - abs((hue / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = brightness - c
        let (r, g, b): (Double, Double, Double) = switch hue {
        case ..<60: (c, x, 0)
        case ..<120: (x, c, 0)
        case ..<180: (0, c, x)
        case ..<240: (0, x, c)
        case ..<300: (x, 0, c)
        default: (c, 0, x)
        }
        return (r + m, g + m, b + m)
    }

    var color: Color {
        Color(hue: hue / 360, saturation: saturation, brightness: brightness)
    }

    var hex: UInt32 {
        let (r, g, b) = rgb
        let to255 = { (v: Double) in UInt32((v * 255).rounded()) }
        return to255(r) << 16 | to255(g) << 8 | to255(b)
    }
}

// MARK: - Binding lenses

private extension Binding where Value == Double {
    /// The value as a 0–1 fraction of `max`.
    func fraction(over max: Double) -> Binding<Double> {
        Binding(get: { wrappedValue / max }, set: { wrappedValue = $0 * max })
    }

    /// The value scaled up for display (0–1 → 0–100).
    func scaled(by factor: Double) -> Binding<Double> {
        Binding(get: { wrappedValue * factor }, set: { wrappedValue = $0 / factor })
    }
}

@MainActor
private enum Haptics {
    static let tick = UISelectionFeedbackGenerator()
}

#Preview {
    @Previewable @State var hex: UInt32 = 0xF5A623
    Color.canvas
        .sheet(isPresented: .constant(true)) {
            ChooseColorSheet(hex: $hex, onPick: { _ in }) {}
                .presentationDetents([.height(ChooseColorSheet.height)])
                .presentationBackgroundInteraction(.enabled)
                .presentationDragIndicator(.visible)
        }
}
