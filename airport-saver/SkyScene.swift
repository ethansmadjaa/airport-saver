//
//  SkyScene.swift
//  airport-saver
//
//  Secondary-screen night sky: same gradient bands + horizon row as
//  AirportScene (see that file's drawSky/horizon) so two adjacent physical
//  monitors read as one continuous sky. No runway (that only exists on the
//  main screen) and no moon (one moon across screens looks wrong -- the
//  main screen owns it). Stars, 1-2 drifting clouds, and planes in transit:
//  local ambient traffic when this is the only screen, otherwise fed
//  entirely by FlightCoordinator.
//

import AppKit
import Foundation
import QuartzCore

// Same PixelCanvas drawing helpers as AirportScene.swift, duplicated here
// rather than shared cross-file so each scene's rendering code stays
// self-contained (see AirportScene.swift for the source of truth).
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

/// One aircraft in transit across a secondary screen's sky. `x`/`y` are the
/// center of its sprite bounding box, in absolute canvas pixels -- the same
/// coordinate space AirportScene draws in, so a plane handed off from the
/// runway (or to it) lines up visually without any translation. `vx`/`vy`
/// are px/s; `landing` marks a flight heading toward the main screen to
/// land there (only consumed by FlightCoordinator's relay, not rendering).
struct SkyPlane {
    var x: CGFloat
    var y: CGFloat
    var vx: CGFloat
    var vy: CGFloat
    var landing: Bool
    var variant: FleetVariant
    /// Pre-rotated tilt sprites, computed once at spawn (see `SkyScene.spawn`)
    /// instead of every frame in `drawPlanes` -- `Sprites.rotated` is
    /// expensive enough (measured ~0.44ms/frame/plane at -O) that doing it
    /// per-frame per-plane shows up as real frame cost.
    let climbShape: [String]
    let descendShape: [String]
    /// Set the instant this plane's leading edge crosses this screen's edge
    /// (horizontally or vertically) and it's been relayed to the neighbor --
    /// keeps it from relaying a second time while it finishes crossing off
    /// this screen for real (see `SkyScene.update`'s overlap-handoff loop).
    var handedOff = false
}

final class SkyScene: PixelScene {
    /// Real NSScreen.screens index (this scene's identity for
    /// FlightCoordinator registration/relay) -- not a chain slot; a screen
    /// stacked above/below the main horizontal chain has no slot at all
    /// but still needs to be addressable.
    let screenIndex: Int
    private let canvasWidth: CGFloat
    private var time: TimeInterval = 0
    private(set) var planes: [SkyPlane] = []

    // Same row as AirportScene.horizon (duplicated, not shared -- see file
    // header) so the gradient seam and ground line align across screens.
    private let horizon = 176

    private var nextLocalSpawn = TimeInterval.random(in: 4...9, using: &FlightCoordinator.shared.rng)

    private struct Cloud { var x: CGFloat; let y: CGFloat; let speed: CGFloat; let art: [String] }
    private var clouds: [Cloud]

    init(screenIndex: Int, canvasWidth: Int) {
        self.screenIndex = screenIndex
        self.canvasWidth = CGFloat(canvasWidth)
        clouds = [
            Cloud(x: CGFloat.random(in: 0..<CGFloat(max(canvasWidth, 1)), using: &FlightCoordinator.shared.rng), y: 26, speed: 4, art: Sprites.cloud1),
            Cloud(x: CGFloat.random(in: 0..<CGFloat(max(canvasWidth, 1)), using: &FlightCoordinator.shared.rng), y: 66, speed: 2.5, art: Sprites.cloud2),
        ]
    }

    /// Introduces a plane at one edge, its leading edge exactly at the
    /// entry edge (center = spriteWidth/2 in from that edge) rather than
    /// fully offscreen -- when this is the far side of a handoff (see
    /// FlightCoordinator), the plane handed off here is mid-crossing the
    /// bezel, not freshly spawned, so it must already be visible right at
    /// the edge to read as one continuous plane with its other half on the
    /// origin screen. `speed` is unsigned; direction comes from `fromLeft`
    /// (enters left edge -> flies right). Width is measured off whichever
    /// tilt `vy` will select for drawing (see `currentShape`), matching the
    /// same shape/rotation the origin screen used for its own crossing
    /// check, so both halves line up pixel-for-pixel at the bezel.
    func spawn(fromLeft: Bool, y: CGFloat, speed: CGFloat, vy: CGFloat, landing: Bool, variant: FleetVariant) {
        let climbShape = Sprites.rotated(variant.shape, degrees: 12)
        let descendShape = Sprites.rotated(variant.shape, degrees: -8)
        let enteringShape = vy < -1 ? climbShape : (vy > 1 ? descendShape : variant.shape)
        let w = CGFloat(Sprites.palettedSize(enteringShape).w)
        let x = fromLeft ? -w / 2 : canvasWidth + w / 2
        planes.append(SkyPlane(x: x, y: y, vx: fromLeft ? speed : -speed, vy: vy, landing: landing, variant: variant,
                                climbShape: climbShape, descendShape: descendShape))
    }

    /// Vertical counterpart of `spawn`: introduces a plane climbing in from
    /// the BOTTOM edge at canvas x `x` (already mapped across the physical
    /// bezel by FlightCoordinator.relayClimbOut) with its horizontal/
    /// vertical rate carried unchanged from the screen below, so the
    /// crossing reads as one continuous climb, not a fresh random spawn.
    /// Enters at the bottom of the climbing band (the same altitude the
    /// y-clamp in `update` uses as its lower bound) rather than fully
    /// offscreen, matching `spawn`'s "leading edge already at the entry
    /// edge" convention for handoffs.
    func spawnClimbing(x: CGFloat, vx: CGFloat, vy: CGFloat, variant: FleetVariant) {
        let climbShape = Sprites.rotated(variant.shape, degrees: 12)
        let descendShape = Sprites.rotated(variant.shape, degrees: -8)
        planes.append(SkyPlane(x: x, y: CGFloat(horizon) - 24, vx: vx, vy: vy, landing: false, variant: variant,
                                climbShape: climbShape, descendShape: descendShape))
    }

    /// The shape actually drawn for a plane's current vertical rate --
    /// shared by `drawPlanes` and the overlap-handoff crossing checks in
    /// `update` so both agree on the sprite's on-screen width.
    private func currentShape(_ plane: SkyPlane) -> [String] {
        if plane.vy < -1 { return plane.climbShape }
        if plane.vy > 1 { return plane.descendShape }
        return plane.variant.shape
    }

    func update(dt: TimeInterval) {
        time += dt
        FlightCoordinator.shared.tick(now: CACurrentMediaTime())

        for i in clouds.indices {
            clouds[i].x -= clouds[i].speed * CGFloat(dt)
            let w = CGFloat(Sprites.size(clouds[i].art).w)
            if clouds[i].x < -w { clouds[i].x = canvasWidth + w }
        }

        for i in planes.indices {
            planes[i].x += planes[i].vx * CGFloat(dt)
            planes[i].y += planes[i].vy * CGFloat(dt)
            // vy is carried and integrated for as long as the plane is in
            // transit (potentially several relays across screens); without
            // a clamp it drifts past the horizon into the ground band.
            planes[i].y = min(max(planes[i].y, 12), CGFloat(horizon) - 24)
        }

        // Vertical climb-out: independent of horizontal chain membership --
        // any climbing plane (on any screen, chain member or not) that
        // reaches the top of its allowed altitude band checks for a real
        // screen physically above before falling back to leveling off via
        // the y-clamp above. Runs before the horizontal check so a plane
        // relayed vertically this frame doesn't also get evaluated for a
        // horizontal handoff on the same frame.
        for i in planes.indices where !planes[i].handedOff && planes[i].vy < 0 && planes[i].y <= 12 {
            if FlightCoordinator.shared.relayClimbOut(from: screenIndex, plane: planes[i]) {
                planes[i].handedOff = true
            }
        }

        if FlightCoordinator.shared.isChainMember(screenIndex) {
            // Overlap handoff: relay the instant a plane's leading edge
            // reaches this screen's edge (not once it's fully offscreen),
            // exactly once per plane -- it keeps flying (and drawing) on
            // this screen until it's actually gone, purely for visual
            // continuity with its new copy on the neighbor.
            for i in planes.indices where !planes[i].handedOff {
                let w = CGFloat(Sprites.palettedSize(currentShape(planes[i])).w)
                let crossed = planes[i].vx > 0
                    ? planes[i].x + w / 2 >= canvasWidth
                    : planes[i].x - w / 2 <= 0
                if crossed {
                    planes[i].handedOff = true
                    FlightCoordinator.shared.skyPlaneExited(screen: screenIndex, plane: planes[i])
                }
            }
            planes.removeAll { plane in
                let w = CGFloat(Sprites.palettedSize(currentShape(plane)).w)
                return plane.x < -w || plane.x > canvasWidth + w
            }
        } else {
            // Not on the main horizontal chain (standalone, or only
            // reachable vertically) -- fed by nothing but its own ambient
            // schedule, so it's never left empty. A vertically-relayed
            // plane (handedOff above) still gets swept once it drifts far
            // enough off either side.
            planes.removeAll { $0.x < -200 || $0.x > canvasWidth + 200 }
            nextLocalSpawn -= dt
            if nextLocalSpawn <= 0 {
                nextLocalSpawn = .random(in: 10...20, using: &FlightCoordinator.shared.rng)
                spawn(
                    fromLeft: Bool.random(using: &FlightCoordinator.shared.rng),
                    y: CGFloat.random(in: 30...(CGFloat(horizon) - 20), using: &FlightCoordinator.shared.rng),
                    speed: CGFloat.random(in: 30...55, using: &FlightCoordinator.shared.rng),
                    vy: CGFloat.random(in: -3...3, using: &FlightCoordinator.shared.rng),
                    landing: false,
                    variant: .random()
                )
            }
        }
    }

    func draw(on c: PixelCanvas) {
        let w = c.width
        drawSky(c, w: w)
        drawStars(c, w: w)
        drawClouds(c)
        drawGround(c, w: w)
        drawPlanes(c)
    }

    // MARK: - Sky (identical band table to AirportScene.drawSky)

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

    private func drawStars(_ c: PixelCanvas, w: Int) {
        let starCount = max(90, w * 110 / 480)
        // Seed offset by screenIndex so neighboring screens don't render an
        // identical starfield -- the gradient/horizon still line up.
        let seq = lcgSequence(seed: 1000 &+ UInt32(screenIndex), count: starCount)
        for (i, v) in seq.enumerated() {
            let x = Int(v % UInt32(w))
            let y = Int((v >> 8) % UInt32(horizon - 6))
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
    }

    private func drawClouds(_ c: PixelCanvas) {
        for cloud in clouds {
            Sprites.draw(cloud.art, on: c, x: Int(cloud.x), y: Int(cloud.y),
                         main: 0x2E3650, dim: 0x1C2438, hi: 0x3A4468)
        }
    }

    // MARK: - Ground (no runway -- just a dark band + a distant skyline glow)

    private func drawGround(_ c: PixelCanvas, w: Int) {
        c.fill(0, horizon, w, c.height - horizon, 0x0E1120)

        let speckleCount = max(120, w * 140 / 480)
        let seq = lcgSequence(seed: 900 &+ UInt32(screenIndex), count: speckleCount)
        for v in seq {
            let x = Int(v % UInt32(w))
            let y = horizon + Int((v >> 8) % UInt32(c.height - horizon))
            c.pixel(x, y, (v >> 16) % 2 == 0 ? 0x161A2C : 0x08090F)
        }

        // Sparse distant city lights, low along the horizon -- a hint that
        // the airport continues off past this screen, without drawing an
        // actual runway here.
        let lightCount = max(20, w * 24 / 480)
        let lightSeq = lcgSequence(seed: 500 &+ UInt32(screenIndex), count: lightCount)
        for v in lightSeq {
            let x = Int(v % UInt32(w))
            let y = horizon + 2 + Int((v >> 10) % 22)
            let warm = (v >> 4) % 3 != 0
            c.pixel(x, y, warm ? 0xFFD9A0 : 0x9FE0FF)
        }
    }

    // MARK: - Planes

    private func drawPlanes(_ c: PixelCanvas) {
        for plane in planes {
            let mirrored = plane.vx < 0 // base art faces right
            let shape = currentShape(plane)
            let size = Sprites.palettedSize(shape)
            let drawX = Int(plane.x) - size.w / 2
            let drawY = Int(plane.y) - size.h / 2

            if plane.vy > 1 { // descending
                drawLandingLight(c, x: drawX, y: drawY, size: size, mirrored: mirrored)
            }
            Sprites.drawPaletted(shape, palette: plane.variant.palette, on: c, x: drawX, y: drawY, mirrored: mirrored)
            drawBeacon(c, x: drawX, y: drawY, size: size)
        }
    }

    private func drawLandingLight(_ c: PixelCanvas, x: Int, y: Int, size: (w: Int, h: Int), mirrored: Bool) {
        let noseX = mirrored ? x : x + size.w
        let noseY = y + Int(Double(size.h) * 0.72)
        let dir = mirrored ? -1 : 1
        for i in 1...4 {
            let falloff = 1 - Double(i) * 0.2
            c.glowPool(noseX + dir * i * 4, noseY + i * 2, 0xFFDD7A, radii: [(3, 0.14 * falloff), (1, 0.5 * falloff)])
        }
        c.pixel(noseX, noseY, 0xFFF6D6)
    }

    private func drawBeacon(_ c: PixelCanvas, x: Int, y: Int, size: (w: Int, h: Int)) {
        guard Int(time * 1.4) % 2 == 0 else { return }
        let bx = x + size.w / 2
        c.pixel(bx, y, 0xFF3B3B)
        c.glowPool(bx, y, 0xFF3B3B, radii: [(2, 0.35)])
    }
}
