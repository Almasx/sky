# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Sky is a SwiftUI iOS app (iOS 26 deployment target, iPhone only) for capturing and browsing sky gradients. Pure SwiftUI, no external dependencies, no test targets. The UI is implemented from a Figma design — color stops and layout metrics in the code are taken verbatim from the Figma fills.

## Build & Run

There is one Xcode scheme, `Sky`. Build from the command line with:

```sh
xcodebuild -project Sky.xcodeproj -scheme Sky -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

`scripts/dev.sh` is the Xcode Run button, headless: it builds, installs, and relaunches the app on the connected iPhone (`--sim` for the simulator), then rebuilds on every Swift file save (`--once` to skip watching).

Uses iOS 26 APIs (`.glass` button style / Liquid Glass, `scrollEdgeEffectStyle`, `safeAreaBar`), so building requires a recent Xcode with the iOS 26 SDK.

## Prototyping workflow

Interactions are prototyped in `prototypes/*.html` before being built in Swift: a single self-contained HTML file with the phone mock (402×874, geometry copied verbatim from the app/Figma) plus a side panel of tuning sliders (spring duration/bounce, thresholds, toggles) so the feel can be iterated live. Once an interaction feels right, port it to SwiftUI using the tuned values. New prototypes default their springs to the app's existing vocabulary in `Sky/Animations.swift` (quick, subtle: ~0.2–0.4s, bounce 0–0.2); once values ship there, sync the prototype defaults back to them. Serve with `python3 -m http.server` in `prototypes/` (the Chrome extension can't open `file://`).

- `stop-picker.html` — drag a stop tag vertically to move its gradient location (zoom-in scene, hex→% label morph).
- `color-edit.html` — tap a tag: card springs to full width (Figma 152:2332), tapped tag docks at the right edge, and a glass "Choose color" sheet (Figma 153:227) rises with hue/sat/lightness sliders + scrubbable value pills. The card's aspect ratio is deliberate and NEVER changes; when a low stop would hide behind the sheet, the whole scene rides up (`--shift-y`) just enough to clear it, following the stop as it moves. In edit mode, dragging a tag moves its stop (label reads out %); tapping opens the sheet. DECIDED: while the sheet is up the stop is NOT movable — the docked tail is an indicator only (the A/B/C reposition affordances remain in the panel for reference, default off). The card travel reuses `Animation.editSlide` (0.22s/0). Ported as `ChooseColorSheet` (native sheet: detent/grabber/glass/swipe from the system) + tap-vs-grab split in `StopTagColumn` + `colorEditShift` in both overlays.
- `bottom-bar.html` — adding and removing colors in stops mode. A glass "+" (bottom trailing, where the gallery's plus lives) adds a color Figma-style: midpoint of the biggest gap, interpolated color, tag slides in from the right; a panel menu of reactions (sideways kick, ripple, card line, pulse…) shows the rest of the scene acknowledging it. Pulling a tag to the right, away from the card, past a threshold detaches it and it flies off the edge, removing the stop. Panel picks a 2/3/6-color example gradient. Not yet ported to Swift. `#edit+add2` in the URL deep-links to stops mode with two inserts, for screenshots.

