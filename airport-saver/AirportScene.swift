//
//  AirportScene.swift
//  airport-saver
//
//  Scène principale : nuit à l'aéroport (fusion des directions art C —
//  ciel/atmosphère/pistes — et A — avion de ligne peint à la main).
//  Largeur adaptative : tout est calculé à partir de c.width à chaque frame,
//  seuls bâtiments + trafic restent groupés à gauche.
//

import AppKit
import Foundation

private extension PixelCanvas {
    func fillA(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ rgb: UInt32, _ alpha: CGFloat) {
        ctx.setFillColor(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: alpha
        )
        ctx.fill(CGRect(x: x, y: y, width: w, height: h))
    }

    func diskA(_ cx: Int, _ cy: Int, _ r: Int, _ rgb: UInt32, _ alpha: CGFloat, squashY: CGFloat = 1) {
        for yy in -r...r {
            let yf = CGFloat(yy) * squashY
            for xx in -r...r {
                if CGFloat(xx * xx) + yf * yf <= CGFloat(r * r) {
                    fillA(cx + xx, cy + yy, 1, 1, rgb, alpha)
                }
            }
        }
    }

    func glowPool(_ cx: Int, _ cy: Int, _ rgb: UInt32, radii: [(Int, CGFloat)], squashY: CGFloat = 1) {
        for (r, a) in radii { diskA(cx, cy, r, rgb, a, squashY: squashY) }
    }

    func disk(_ cx: Int, _ cy: Int, _ r: Int, _ rgb: UInt32) {
        for yy in -r...r {
            for xx in -r...r where xx * xx + yy * yy <= r * r {
                pixel(cx + xx, cy + yy, rgb)
            }
        }
    }

    func dither(_ x0: Int, _ y0: Int, _ w: Int, _ h: Int, _ a: UInt32, _ b: UInt32) {
        for row in 0..<h {
            for col in 0..<w {
                pixel(x0 + col, y0 + row, (col + row) % 2 == 0 ? a : b)
            }
        }
    }
}

private func lcgSequence(seed: UInt32, count: Int) -> [UInt32] {
    var s = seed
    var out: [UInt32] = []
    out.reserveCapacity(count)
    for _ in 0..<count {
        s = 1_664_525 &* s &+ 1_013_904_223
        out.append(s)
    }
    return out
}

final class AirportScene: PixelScene {
    /// `time` exposé pour que les futures scènes (avion en approche/décollage)
    /// puissent réutiliser la même horloge d'animation.
    private(set) var time: TimeInterval = 0
    private let horizon = 176
    // Runway strip (shared by drawGround's shading + drawTraffic's placement):
    // a band below the horizon, planes taxi/roll along its centerline.
    private var runwayY0: Int { horizon + 32 }
    private var runwayY1: Int { horizon + 72 }
    private var runwayGroundY: CGFloat { CGFloat(runwayY0 + runwayY1) / 2 }
    private let canvasWidth: CGFloat

    /// Gates ambient *landings* only. Self-scheduled takeoffs keep
    /// happening regardless -- a multi-screen airport should still see
    /// planes leave -- but spontaneous landings are left to
    /// FlightCoordinator (via `queueApproach()`) once there's more than
    /// one screen, so local and relayed arrivals don't double up.
    /// `queueApproach()` always forces a landing, localTraffic or not --
    /// it's an explicit request, not ambient scheduling.
    var localTraffic: Bool

    /// Fired the moment a departing flight's leading edge crosses the
    /// runway's exit edge, with its altitude and horizontal speed at that
    /// instant and which fleet variant it was -- a neighboring sky scene
    /// picks the plane up from there and keeps drawing it at the speed it
    /// actually left with, its own leading edge landing on its entry edge
    /// in the same instant (see FlightCoordinator.departureExited).
    var onDepartureExit: ((CGFloat, CGFloat, FleetVariant) -> Void)?

    /// Asked once, right when a takeoff starts rolling, which direction
    /// this flight should head (see `direction` below) -- wired to
    /// FlightCoordinator.startDeparture() so the scene and coordinator
    /// agree on the side for this specific flight from frame one. Nil (no
    /// coordinator, e.g. single-screen/preview) defaults to +1.
    var departureDirection: (() -> Int)?

    /// Fired the moment a go-around's leading edge crosses the exit edge
    /// (the far side from wherever it entered, same overlap-handoff timing
    /// as `onDepartureExit`), with its altitude/speed/variant and the
    /// flight's own `direction` -- FlightCoordinator uses `direction` to
    /// work out which side is the far side and relays it there, then
    /// schedules its retry landing. Nil (no coordinator, e.g. single-
    /// screen/preview) means this scene retries its own landing instead
    /// (see `pendingRetries`).
    var onGoAroundExit: ((CGFloat, CGFloat, FleetVariant, Int) -> Void)?

    // MARK: - Runway traffic state

    /// One flight occupying the runway itself: any ground phase (rollout,
    /// taxiIn, parkPause, taxiOut, taxiToRunway, lineUp, takeoffRoll) or a
    /// departure's climb. At most one of these exists at a time -- the
    /// runway is a single resource, which is exactly what an arrival's
    /// go-around check (`RunwayPlane.step`'s `runwayFree`) is asking about.
    private struct GroundFlight {
        var plane: RunwayPlane
        var variant: FleetVariant
        /// +1 = this flight exits/enters via the runway's RIGHT edge
        /// (legacy, default), -1 = via the LEFT edge. Decided per-flight --
        /// see `startTakeoff`/`spawnApproach` -- and applied purely as a
        /// mirror at draw time (`drawFlight`); RunwayPlane's own kinematics
        /// never see it, they always run in their native left-apron/
        /// right-exit space.
        var direction: Int
        var isDeparture: Bool
        var climbShape: [String] = []  // only used while phase == .climb (departures)
        var handedOff = false          // departure's onDepartureExit guard, see updateTraffic
    }

    /// One airborne arrival not (or no longer) on the runway: `.approach`
    /// heading in, or `.goAround` overflying after being waved off because
    /// the runway was busy at its commit point. Several can be in the air
    /// at once -- only the one that actually touches down claims the
    /// single `ground` slot above.
    private struct ArrivalFlight {
        var plane: RunwayPlane
        var variant: FleetVariant
        var direction: Int  // see GroundFlight.direction's doc -- same convention
        var descendShape: [String]  // used while phase == .approach
        var climbShape: [String]    // pitch-up tilt, used while phase == .goAround
        var handedOff = false       // onGoAroundExit guard, see updateTraffic
    }

    private var ground: GroundFlight?
    private var arrivals: [ArrivalFlight] = []

    /// Read-only world-space (screen-pixel) position of one tracked plane --
    /// debug accessor for checks/handoff_check.swift's continuity
    /// verification, never used by the real screensaver. `worldX`/`worldY`
    /// use the exact same math as `drawFlight`'s `screenX`/ground-relative Y
    /// (minus the sprite-size draw offset, since a center point is all the
    /// check needs), so this always agrees with what's actually rendered.
    struct TrackedPlane {
        let worldX: CGFloat
        let worldY: CGFloat
        let isDeparture: Bool
    }

    /// Every plane this scene is currently simulating (ground flight, if
    /// any, plus every airborne arrival), in world-space coordinates.
    var trackedPlanes: [TrackedPlane] {
        var out: [TrackedPlane] = []
        if let ground {
            out.append(TrackedPlane(worldX: worldX(ground.plane, direction: ground.direction),
                                     worldY: runwayGroundY - ground.plane.altitude,
                                     isDeparture: ground.isDeparture))
        }
        for arrival in arrivals {
            out.append(TrackedPlane(worldX: worldX(arrival.plane, direction: arrival.direction),
                                     worldY: runwayGroundY - arrival.plane.altitude,
                                     isDeparture: false))
        }
        return out
    }

    private func worldX(_ plane: RunwayPlane, direction: Int) -> CGFloat {
        direction == 1 ? plane.x : canvasWidth - plane.x
    }
    private var idleTimer: TimeInterval = 0
    private var nextIdleInterval = TimeInterval.random(in: 8...15, using: &FlightCoordinator.shared.rng)
    /// Single-screen go-around retries (see `onGoAroundExit`'s doc): each
    /// entry fires its own forced landing once `time` reaches `fireAt`,
    /// carrying the same variant so it visibly is the same plane coming
    /// back. A small list, not one slot -- more than one go-around can be
    /// in the air waiting to retry at once.
    private var pendingRetries: [(fireAt: TimeInterval, variant: FleetVariant)] = []

    init(canvasWidth: Int, localTraffic: Bool = true) {
        self.canvasWidth = CGFloat(canvasWidth)
        self.localTraffic = localTraffic
    }

    /// Debug/testing hook (and FlightCoordinator's relay landing path): an
    /// arriving relay ALWAYS spawns an airborne approach instantly -- bezel
    /// continuity is sacred, so this never waits invisibly on the runway.
    /// If the runway turns out to be busy once this approach reaches its
    /// commit point, it goes around instead (see `RunwayPlane.step`'s
    /// `runwayFree`/`.goAround`). `variant` carries a relayed flight's
    /// fleet type through to the runway; nil picks a random one
    /// (deterministic sequence renders use the default).
    /// `direction`/`speed`/`altitude` matter only for relayed arrivals: a
    /// non-nil `altitude` seeds the new RunwayPlane's leading edge exactly
    /// at this screen's entry edge (instead of RunwayPlane's default
    /// fully-offscreen spawn) with a matching height and speed, so a
    /// handoff from a neighboring sky screen reads as one continuous
    /// plane -- see `spawnApproach`. Callers that just want the legacy
    /// glide-in-from-offscreen landing (ambient scheduling, this file's
    /// own render check) leave `altitude` nil.
    func queueApproach(variant: FleetVariant? = nil, direction: Int = 1, speed: CGFloat = 42, altitude: CGFloat? = nil) {
        spawnApproach(variant: variant, direction: direction, entrySpeed: speed, entryAltitude: altitude)
    }

    /// Debug/testing hook mirroring `queueApproach`: forces a takeoff to
    /// begin the moment the runway is free, bypassing the random idle
    /// scheduler. Only used by checks/render.swift (the "takeoff" case and
    /// the "handoff"/"goaround" composites), which need a takeoff to start
    /// at a known simulated time -- never called by the real screensaver.
    func forceTakeoff() {
        guard ground == nil else { return }
        startTakeoff()
    }

    func update(dt: TimeInterval) {
        time += dt
        updateTraffic(dt: dt)
    }

    func draw(on c: PixelCanvas) {
        let w = c.width
        drawSky(c, w: w)
        drawStarsAndMoon(c, w: w)
        drawDistantLights(c, w: w)
        drawBuildings(c, w: w)
        if localTraffic {
            drawParkedPlanes(c, w: w)
        }
        drawGround(c, w: w)
        drawTraffic(c, w: w)
    }

    // MARK: - Runway traffic

    private func updateTraffic(dt: TimeInterval) {
        let dtc = CGFloat(dt)

        // Both ground flows now end fully offscreen (a departure climbs
        // out past the right edge, an arrival taxis back out past the left
        // edge after its parkPause), so .done is cleared immediately below
        // -- `ground` is never left sitting in .done across calls.
        if var flight = ground {
            flight.plane.step(dt: dtc, canvasWidth: canvasWidth)

            // Overlap handoff: fire the instant the departure's leading
            // edge reaches the exit edge (not when it's fully offscreen),
            // exactly once per flight -- RunwayPlane keeps running this
            // same plane to .done afterwards purely so it stays visible
            // (and simulated) on this screen until it's actually gone.
            // The crossing threshold is the same regardless of direction:
            // mirroring at draw time reflects both plane.x and the exit
            // edge around canvasWidth/2, so the condition on native x is
            // identical for +1 (right exit) and -1 (left exit).
            if flight.plane.phase == .climb, flight.isDeparture, !flight.handedOff {
                let halfWidth = CGFloat(Sprites.palettedSize(flight.climbShape).w) / 2
                if flight.plane.x >= canvasWidth - halfWidth {
                    flight.handedOff = true
                    onDepartureExit?(flight.plane.altitude, abs(flight.plane.speed), flight.variant)
                }
            }
            ground = flight.plane.phase == .done ? nil : flight
        }

        // Step every airborne arrival. Sequential (not mapped in one
        // pass): `runwayFree` is recomputed fresh for each one, right
        // before its own step, so a sibling arrival that just committed to
        // land earlier in this very same pass also blocks this one --
        // RunwayPlane.isCommittedToLand is what makes that visible from
        // outside without RunwayPlane knowing anything about the scene.
        for i in arrivals.indices {
            let runwayFree = ground == nil && !arrivals.contains { $0.plane.isCommittedToLand }
            arrivals[i].plane.step(dt: dtc, canvasWidth: canvasWidth, runwayFree: runwayFree)

            // Go-around overlap handoff: same leading-edge-at-the-exit-edge
            // timing as a departure's, just on the near-native-zero edge
            // (a go-around continues in native-decreasing-x, i.e. exits
            // toward x <= 0, the opposite native edge from a climb).
            if arrivals[i].plane.phase == .goAround, !arrivals[i].handedOff {
                let halfWidth = CGFloat(Sprites.palettedSize(arrivals[i].climbShape).w) / 2
                if arrivals[i].plane.x <= halfWidth {
                    arrivals[i].handedOff = true
                    let flight = arrivals[i]
                    if let onGoAroundExit {
                        onGoAroundExit(flight.plane.altitude, abs(flight.plane.speed), flight.variant, flight.direction)
                    } else {
                        // No coordinator wired (single-screen/preview):
                        // this scene has no sky to relay through, so it
                        // schedules its own retry landing instead.
                        pendingRetries.append((fireAt: time + .random(in: 15...30, using: &FlightCoordinator.shared.rng), variant: flight.variant))
                    }
                }
            }
        }

        // A landed arrival claims the runway -- at most one can reach
        // .rollout in a given pass (isCommittedToLand above guarantees
        // only one arrival is ever "cleared" to touch down at a time).
        if let landedIndex = arrivals.firstIndex(where: { $0.plane.phase == .rollout }) {
            let landed = arrivals.remove(at: landedIndex)
            ground = GroundFlight(plane: landed.plane, variant: landed.variant, direction: landed.direction, isDeparture: false)
        }
        arrivals.removeAll { $0.plane.phase == .done }

        if !pendingRetries.isEmpty {
            let due = pendingRetries.filter { $0.fireAt <= time }
            if !due.isEmpty {
                pendingRetries.removeAll { $0.fireAt <= time }
                for retry in due { spawnApproach(variant: retry.variant) }
            }
        }

        guard ground == nil else { return }

        idleTimer += dt
        guard idleTimer >= nextIdleInterval else { return }
        idleTimer = 0
        nextIdleInterval = .random(in: 8...15, using: &FlightCoordinator.shared.rng)
        // See localTraffic's doc comment: takeoffs always self-schedule,
        // ambient landings only do when there's no coordinator relaying
        // arrivals in.
        if localTraffic {
            Bool.random(using: &FlightCoordinator.shared.rng) ? spawnApproach() : startTakeoff()
        } else {
            startTakeoff()
        }
    }

    private func spawnApproach(variant: FleetVariant? = nil, direction: Int = 1, entrySpeed: CGFloat = 42, entryAltitude: CGFloat? = nil) {
        let variant = variant ?? FleetVariant.random()
        let descendShape = Sprites.rotated(variant.shape, degrees: -8)
        let climbShape = Sprites.rotated(variant.shape, degrees: 12) // pitch-up tilt, only used if this flight later goes around
        var plane = RunwayPlane.landing(canvasWidth: canvasWidth)
        if let entryAltitude {
            // Relayed arrival handed off from a neighboring sky screen:
            // seed the leading edge exactly at this screen's entry edge
            // (canvasWidth + halfWidth is RunwayPlane's own native-space
            // exit/entry point regardless of direction -- see the mirror
            // note in updateTraffic) instead of RunwayPlane's default
            // fully-offscreen spawn, and match the sky's height/speed, so
            // the crossing reads as one continuous plane.
            let halfWidth = CGFloat(Sprites.palettedSize(descendShape).w) / 2
            plane.x = canvasWidth + halfWidth
            plane.altitude = entryAltitude
            plane.speed = -abs(entrySpeed)
        }
        arrivals.append(ArrivalFlight(plane: plane, variant: variant, direction: direction, descendShape: descendShape, climbShape: climbShape))
    }

    private func startTakeoff() {
        let variant = FleetVariant.random()
        let direction = departureDirection?() ?? 1
        let climbShape = Sprites.rotated(variant.shape, degrees: 12)
        ground = GroundFlight(plane: .takeoff(canvasWidth: canvasWidth), variant: variant, direction: direction, isDeparture: true, climbShape: climbShape)
    }

    private func drawTraffic(_ c: PixelCanvas, w: Int) {
        // Ground flight first, then airborne arrivals on top -- with
        // different altitudes there's no real z-order ambiguity, but
        // matches the natural reading order (taxiway, then sky).
        if let ground {
            drawFlight(c, plane: ground.plane, variant: ground.variant, direction: ground.direction,
                       isDeparture: ground.isDeparture, descendShape: [], climbShape: ground.climbShape)
        }
        for arrival in arrivals {
            drawFlight(c, plane: arrival.plane, variant: arrival.variant, direction: arrival.direction,
                       isDeparture: false, descendShape: arrival.descendShape, climbShape: arrival.climbShape)
        }
    }

    private func drawFlight(_ c: PixelCanvas, plane: RunwayPlane, variant: FleetVariant, direction: Int,
                             isDeparture: Bool, descendShape: [String], climbShape: [String]) {
        let baseMirrored = !isDeparture // landing flies right-to-left; base art faces right
        // direction mirrors the whole draw around the canvas: -1 flips
        // both where the plane sits on screen and which way its sprite
        // faces, so a flight sent left still noses in the direction it's
        // actually moving. RunwayPlane's own `plane.x` never changes --
        // it always runs in its native left-apron/right-exit space.
        let mirrored = direction == 1 ? baseMirrored : !baseMirrored

        let shape: [String]
        switch plane.phase {
        case .approach: shape = descendShape
        case .climb, .goAround: shape = climbShape // goAround reuses the climb (pitch-up) tilt
        default: shape = variant.shape // level on the ground: rollout, taxiIn, parkPause, taxiOut, taxiToRunway, lineUp, takeoffRoll
        }

        let size = Sprites.palettedSize(shape)
        let screenX = direction == 1 ? plane.x : canvasWidth - plane.x
        let drawX = Int((screenX - CGFloat(size.w) / 2).rounded())
        let drawY = Int((runwayGroundY - plane.altitude).rounded()) - size.h

        if plane.altitude > 4 {
            drawLandingLight(c, plane: plane, bboxX: drawX, bboxY: drawY, size: size, mirrored: mirrored)
        }
        Sprites.drawPaletted(shape, palette: variant.palette, on: c, x: drawX, y: drawY, mirrored: mirrored)
        drawBeacon(c, bboxX: drawX, bboxY: drawY, size: size)
    }

    /// Warm pixel cone ahead of the nose, only while airborne.
    private func drawLandingLight(_ c: PixelCanvas, plane: RunwayPlane, bboxX: Int, bboxY: Int,
                                   size: (w: Int, h: Int), mirrored: Bool) {
        let noseX = mirrored ? bboxX : bboxX + size.w
        let noseY = bboxY + Int(Double(size.h) * 0.72)
        let dir = mirrored ? -1 : 1
        for i in 1...4 {
            let falloff = 1 - Double(i) * 0.2
            c.glowPool(noseX + dir * i * 4, noseY + i * 2, 0xFFDD7A, radii: [(3, 0.14 * falloff), (1, 0.5 * falloff)])
        }
        c.pixel(noseX, noseY, 0xFFF6D6)
    }

    /// Slow red beacon blink on top of the fuselage, ground or air.
    private func drawBeacon(_ c: PixelCanvas, bboxX: Int, bboxY: Int, size: (w: Int, h: Int)) {
        guard Int(time * 1.4) % 2 == 0 else { return }
        let bx = bboxX + size.w / 2
        c.pixel(bx, bboxY, 0xFF3B3B)
        c.glowPool(bx, bboxY, 0xFF3B3B, radii: [(2, 0.35)])
    }

    // MARK: - Sky

    private func drawSky(_ c: PixelCanvas, w: Int) {
        let bands: [(Int, UInt32)] = [
            (0, 0x090A20),
            (34, 0x11123A),
            (64, 0x1A1B4A),
            (92, 0x2A1D52),
            (116, 0x452152),
            (138, 0x66294D),
            (156, 0x8C3E45),
            (168, 0xB56A3E),
        ]
        for i in 0..<bands.count {
            let y0 = bands[i].0
            let y1 = i + 1 < bands.count ? bands[i + 1].0 : horizon
            c.fill(0, y0, w, y1 - y0, bands[i].1)
        }
        for i in 0..<bands.count - 1 {
            let seam = bands[i + 1].0
            c.dither(0, seam - 1, w, 2, bands[i].1, bands[i + 1].1)
        }
    }

    // MARK: - Stars + moon

    private func drawStarsAndMoon(_ c: PixelCanvas, w: Int) {
        let moonX = Int((Double(w) * 0.82).rounded())
        let moonY = 48
        let starCount = max(90, w * 110 / 480)
        let seq = lcgSequence(seed: 42, count: starCount)
        for (i, v) in seq.enumerated() {
            let x = Int(v % UInt32(w))
            let y = Int((v >> 8) % UInt32(horizon - 6))
            let dx = x - moonX, dy = y - moonY
            if dx * dx + dy * dy < 26 * 26 { continue }
            let phase = Double(v % 1000) / 1000.0 * .pi * 2
            let twinkle = sin(time * 1.6 + phase)
            if i % 13 == 0 {
                c.pixel(x, y, 0xFFFFFF)
                if twinkle > -0.2 {
                    c.pixel(x - 1, y, 0x8FA6E0)
                    c.pixel(x + 1, y, 0x8FA6E0)
                    c.pixel(x, y - 1, 0x8FA6E0)
                    c.pixel(x, y + 1, 0x8FA6E0)
                }
            } else if i % 3 == 0 {
                c.pixel(x, y, twinkle > 0.6 ? 0xFFFFFF : 0xBFD4FF)
            } else if twinkle > -0.75 {
                c.pixel(x, y, 0x565E90)
            }
        }

        c.glowPool(moonX, moonY, 0xFFF2B8, radii: [(20, 0.05), (15, 0.07), (11, 0.10)])
        c.disk(moonX, moonY, 9, 0xF3ECC8)
        c.disk(moonX + 4, moonY - 3, 8, 0x11123A)
    }

    // MARK: - Distant city lights

    private func drawDistantLights(_ c: PixelCanvas, w: Int) {
        let lightCount = max(50, w * 56 / 480)
        let seq = lcgSequence(seed: 7, count: lightCount)
        for v in seq {
            let x = Int(v % UInt32(w))
            let y = horizon - 1 - Int((v >> 20) % 3)
            let warm = (v >> 4) % 3 != 0
            c.pixel(x, y, warm ? 0xFFD9A0 : 0x9FE0FF)
        }
    }

    // MARK: - Buildings

    private func drawBuildings(_ c: PixelCanvas, w: Int) {
        let base = horizon
        let bldg: UInt32 = 0x161A28
        let roof: UInt32 = 0x232A40
        let rim: UInt32 = 0x6B4A4A
        let window: UInt32 = 0xFFCB6E

        // warm ambient haze where the buildings meet the horizon glow
        c.fillA(0, base - 14, w, 14, 0xB56A3E, 0.10)

        hangar(c, x: 20, baseY: base, w: 52, h: 24, color: bldg, roofColor: roof, rim: rim, window: window, cols: 6)
        hangar(c, x: 86, baseY: base, w: 38, h: 32, color: bldg, roofColor: roof, rim: rim, window: window, cols: 4)

        let tx = 158
        c.fill(tx, base - 10, 10, 10, bldg)
        c.fill(tx + 3, base - 44, 4, 34, bldg)
        c.fill(tx + 1, base - 54, 8, 10, roof)
        c.fill(tx, base - 56, 10, 2, rim)
        c.pixel(tx + 2, base - 50, window)
        c.pixel(tx + 4, base - 50, window)
        c.pixel(tx + 6, base - 50, window)
        c.pixel(tx + 4, base - 36, window)
        c.pixel(tx + 4, base - 26, window)

        c.fill(tx + 4, base - 62, 1, 6, bldg)

        // red obstruction light — blinks, slower than the beacon
        if Int(time * 0.9) % 2 == 0 {
            c.pixel(tx + 4, base - 63, 0xFF2020)
            c.glowPool(tx + 4, base - 63, 0xFF2020, radii: [(3, 0.30)])
        }

        let beaconOn = Int(time * 1.2) % 2 == 0
        let beaconColor: UInt32 = beaconOn ? 0x39FF6A : 0xEFFFFA
        c.pixel(tx + 4, base - 55, beaconColor)
        c.glowPool(tx + 4, base - 55, beaconColor, radii: [(5, 0.28), (3, 0.45)])
    }

    private func hangar(_ c: PixelCanvas, x: Int, baseY: Int, w: Int, h: Int,
                         color: UInt32, roofColor: UInt32, rim: UInt32, window: UInt32, cols: Int) {
        c.fill(x, baseY - h, w, h, color)
        c.fill(x - 2, baseY - h - 4, w + 4, 4, roofColor)
        c.fill(x - 2, baseY - h - 4, w + 4, 1, rim)
        let winY = baseY - h + 5
        for i in 0..<cols {
            let wx = x + 4 + i * (w - 10) / max(cols - 1, 1)
            if (i + x) % 3 != 0 {
                c.fill(wx, winY, 3, 4, window)
            } else {
                c.fill(wx, winY, 3, 4, 0x2A2416)
            }
        }
    }

    // MARK: - Parked planes (silhouettes)
    //
    // The detailed hand-drawn hero jet used to sit here statically -- now
    // that the same banked-pose sprite genuinely moves as runway traffic,
    // a frozen copy of it next to real motion read as broken, not parked
    // (this is the "reads as a takeoff roll when grounded" issue noted
    // during the sprite work). Removed; these simpler silhouettes don't
    // have that problem since they're not shared with the moving traffic.

    private func drawParkedPlanes(_ c: PixelCanvas, w: Int) {
        parkedPlane(c, x: 306, baseY: horizon, len: 28)
        parkedPlane(c, x: 350, baseY: horizon, len: 20)
    }

    private func parkedPlane(_ c: PixelCanvas, x: Int, baseY: Int, len: Int) {
        let body: UInt32 = 0x1E2436
        let win: UInt32 = 0xFFE3A0
        let y = baseY - 7
        c.fill(x, y, len, 4, body)                    // fuselage
        c.fill(x + len - 8, y - 5, 3, 5, body)         // tail fin
        c.fill(x + len - 5, y - 2, 2, 2, body)         // fin tip
        c.fill(x + 6, y + 4, 10, 2, body)              // wing
        var i = 3
        while i < len - 8 {
            c.pixel(x + i, y + 1, win)
            i += 4
        }
    }

    // MARK: - Ground + runway

    private func drawGround(_ c: PixelCanvas, w: Int) {
        c.fill(0, horizon, w, c.height - horizon, 0x0E1120)

        let speckleCount = max(120, w * 140 / 480)
        let seq = lcgSequence(seed: 99, count: speckleCount)
        for v in seq {
            let x = Int(v % UInt32(w))
            let y = horizon + Int((v >> 8) % UInt32(c.height - horizon))
            c.pixel(x, y, (v >> 16) % 2 == 0 ? 0x161A2C : 0x08090F)
        }

        let ry0 = runwayY0, ry1 = runwayY1
        c.fill(0, ry0, w, ry1 - ry0, 0x181C2C)
        c.dither(0, ry0, w, 2, 0x0E1120, 0x181C2C)
        c.dither(0, ry1 - 2, w, 2, 0x181C2C, 0x0E1120)

        var x = 10
        while x < w - 10 {
            c.fill(x, (ry0 + ry1) / 2, 8, 2, 0xD8DCE8)
            x += 20
        }

        // warm-white edge lights, paired top row + bottom row, each with a soft
        // glow pool that shimmers subtly (phase offset per light so they don't
        // all pulse in lockstep).
        var lx = 30
        var idx = 0
        while lx < w - 30 {
            let shimmer = 0.85 + 0.15 * sin(time * 3 + Double(idx) * 0.7)
            for ly in [ry0, ry1 - 1] {
                c.glowPool(lx, ly, 0xFFCB7A, radii: [(5, 0.16 * shimmer), (3, 0.24 * shimmer)], squashY: 1.3)
                c.fill(lx - 1, ly, 3, 1, 0xFFF7DE)
                c.pixel(lx, ly, 0xFFFFFF)
            }
            lx += 34
            idx += 1
        }

        // red threshold bar, left end
        for ly in [ry0, ry1 - 1] {
            c.glowPool(9, ly, 0xFF3B3B, radii: [(9, 0.16), (5, 0.28)], squashY: 1.4)
            c.fill(3, ly, 12, 1, 0xFF6B5A)
        }
        // green threshold bar, right end
        for ly in [ry0, ry1 - 1] {
            c.glowPool(w - 10, ly, 0x39FF6A, radii: [(9, 0.16), (5, 0.28)], squashY: 1.4)
            c.fill(w - 15, ly, 12, 1, 0x7CFFA0)
        }
    }
}
