# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
make build     # xcodebuild the .saver (Debug)
make install   # build + copy to ~/Library/Screen Savers + killall legacyScreenSaver (macOS caches the bundle — the killall is required to reload)
make check     # the two CLI checks: topology_check + runway_check (swiftc, no Xcode)
make run       # open -a ScreenSaverEngine
make render    # render one frame of the airport scene to /tmp/airport.png and open it
```

There is no test target. Verification works two ways:

1. **Pure-logic CLI checks** — `RunwayPlane.swift` and `ScreenTopology.swift` import CoreGraphics only (never AppKit/ScreenSaver) so they compile standalone: `swiftc -o /tmp/x airport-saver/RunwayPlane.swift checks/runway_check.swift && /tmp/x`. Keep them pure; the checks are the contract (assert-based, print `... OK`).
2. **Visual verification via the render harness** — `checks/render.swift` compiles with all scene files into a CLI that renders any scene to a PNG at a given width and simulated time, e.g. `/tmp/render airport out.png 480 12`. Scene cases: `airport` (random traffic), `takeoff` (deterministic forced departure at t=0), `sky` (with debug-spawned planes). **Render a PNG and Read (view) it after any visual change** — this is the project's testing philosophy; several real bugs (vanishing planes, halo fringes, handoff misalignment) were only caught by looking at rendered frames, including sequences of timestamps to check motion and ultra-wide widths (645) to check layout stretching.

## Architecture

macOS screen saver (`.saver` bundle, Swift). The system instantiates **one `AirportSaverView` per screen in the same process** — this is what makes cross-screen coordination possible via a plain singleton, all on the main thread (no locks anywhere; keep it that way).

- **`PixelCanvas`** — CGContext-backed logical pixel buffer. Height is fixed at 270 (`PixelCanvas.logicalHeight`); width is per-instance, computed from the screen's aspect ratio (ultra-wide screens get wider canvases — never reintroduce a fixed 480 width). Coordinates are y-down, (0,0) top-left. The view blits it nearest-neighbor, letterboxed only by rounding.
- **`PixelScene`** protocol — `update(dt:)` + `draw(on:)`. `AirportSaverView.makeScene()` is the single routing point: preview → standalone `AirportScene`; screen 0 → `AirportScene` wired to the coordinator; other screens → `SkyScene`. If the view cannot resolve its screen (`window?.screen` nil), it must return an **unregistered** standalone scene — registering a fallback "main" corrupts the coordinator (this was a real bug).
- **`RunwayPlane`** — pure state machine for ground/air traffic on the main screen: `taxiToRunway → lineUp → takeoffRoll → climb` and `approach → rollout → taxiIn → parkPause → taxiOut`. Both flows start and end **fully off-screen** (planes taxi in/out; nothing pops). It runs in _native_ coordinates where takeoffs exit right; `AirportScene` applies a per-flight mirror (`screenX = direction == +1 ? x : canvasWidth - x`) so traffic heads toward whichever side the sky screens are on. Never put direction logic inside `RunwayPlane`.
- **`FlightCoordinator`** — singleton relaying planes between screens. Key invariants: `configure(frames:)` compares the full frames array (not just count) and resets sky registrations + `airport.localTraffic` on change; sky scenes are held **weakly**; departure/arrival sides alternate when the main screen has neighbors on both sides. Handoffs are **overlap handoffs**: fired when the sprite's _leading edge_ touches the exit edge, the neighbor spawns it with its leading edge at the entry edge, and the origin keeps drawing its copy until fully out (`handedOff` flags prevent double relays). The relayed plane's variant, speed and altitude carry across — a blue plane must land blue.
- **`Sprites`** — two sprite systems: `drawPaletted` (char grid + `[Character: UInt32]` palette — the aircraft, extracted from reference images) and the older 3-tone ASCII rasterizer (only the clouds remain). `Sprites.rotated(_:degrees:)` generates tilt variants — **compute rotations once at spawn and cache them on the plane; never call `rotated` per frame** (measured at 0.4–3.3 ms/frame/plane).
- **`ScreenTopology`** — pure 2D adjacency model from `NSScreen.screens` frames (index 0 = main screen): `neighbor(of:_:)` finds each screen's real left/right/above/below neighbor by edge-touching (within a few px) plus a minimum overlap fraction (ruling out corner-only/diagonal contact). The legacy left-to-right slot/offset API (`slotForScreen`, `screenForSlot`, `offsetForSlot`, `worldWidth`) is still there but now scoped to the **main horizontal chain** — the screens reachable from the main screen by walking left/right adjacency; a screen only reachable vertically (stacked above/below) gets no slot at all (`slotForScreen[i] == nil`).

## Constraints

- `@objc(airport_saverView)` on the view class must never be renamed — `NSPrincipalClass` in the generated Info.plist depends on it.
- Files added under `airport-saver/` join the target automatically (`PBXFileSystemSynchronizedRootGroup`); never edit `project.pbxproj` to add files. `checks/` stays outside the bundle.
- The color pipeline is deviceRGB end-to-end: every fill goes through `ctx.setFillColor(red:green:blue:alpha:)`, so hex constants land pixel-exact. Never reintroduce `CGColor(red:green:blue:alpha:)` for palette colors — that constructor is generic-RGB and shifts channels (up to ~26) on conversion into the deviceRGB context.
- Sprite grids are Swift raw strings `#"..."#` (they contain `\` and `"`); leading spaces are significant.
