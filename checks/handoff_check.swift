// Check de continuité du handoff. Compiler et lancer :
//   swiftc -o /tmp/handoff_check airport-saver/PixelCanvas.swift airport-saver/PixelScene.swift \
//     airport-saver/Sprites.swift airport-saver/RunwayPlane.swift airport-saver/ScreenTopology.swift \
//     airport-saver/AirportScene.swift airport-saver/SkyScene.swift airport-saver/FlightCoordinator.swift \
//     checks/handoff_check.swift \
//   && /tmp/handoff_check
//
// Reconstructs each screen's world-space view of a relayed plane during the
// overlap window (the two-screen composite from checks/render.swift's
// "handoff" scene: a sky screen to the LEFT of the main/airport screen) and
// asserts the two screens agree on where it is.
//
// Accessor over pixel-scanning: this reads plane positions straight from
// AirportScene.trackedPlanes / SkyScene.planes (both already exact CGFloat
// state, the former added for this check) rather than scanning rendered
// canvases for a sprite's bounding box. That's the more robust option --
// it's exact (no rounding to drawn integer pixels, no silhouette-detection
// ambiguity from rotated sprites or overlapping planes), it doesn't need a
// render pass at all, and it can never drift out of sync with a sprite art
// change, since it reads the very state the renderer itself draws from.
//
// Both screens share the same canvasWidth (480) and physically abut with no
// gap, so "world X" here is plain logical-pixel concatenation (sky spans
// [0, width), airport spans [width, 2*width)) rather than a physical-frame
// conversion through ScreenTopology -- simpler, and exact for this
// same-width composite (the general physical-frame math is FlightCoordinator's
// own job, already exercised by the relay calls this check makes).
//
// X and Y are NOT both checked the same way, on purpose (see measurements in
// .superpowers/sdd/2026-08-02-airport-saver-ascii/devqol-report.md):
// - X: both copies are independently simulated after the handoff (the
//   origin keeps running its own kinematics purely for its own draw-until-
//   gone tail; the neighbor's copy is a fresh, separately-evolving object),
//   but they start from the exact same instant and (over the short window
//   the sprite is actually crossing the boundary) their speeds are close
//   enough that X agreement holds to sub-pixel precision for a good while --
//   checked continuously across a real multi-frame window.
// - Y: FlightCoordinator deliberately re-maps altitude into each sky
//   screen's fixed vertical band (`max(20, min(160, ...))` for a departure,
//   `min(90, max(0, ...))` for an arrival -- see departureExited/
//   skyPlaneExited) and a departure's on-screen climb rate is intentionally
//   faster near the runway than its "cruising away" sky rate (documented as
//   "small negative vy" in departureExited). So Y is only continuous AT the
//   instant of the relay, not afterwards -- checked once, right there,
//   using the exact same clamp formula FlightCoordinator itself uses (this
//   also guards the 228 ground-Y constant, duplicated by design in
//   AirportScene/FlightCoordinator/this file, from silently drifting apart).

import AppKit

@main
struct HandoffCheck {
    static let dt = 1.0 / 30.0
    static let width = 480
    // Matches AirportScene.runwayGroundY / FlightCoordinator.airportGroundY
    // (both currently 228) -- see file header.
    static let groundY: CGFloat = 228

    // Same two-screen layout as render.swift's "handoff" composite: sky
    // screen (index 1) physically LEFT of main/airport (index 0).
    static let frames = [
        CGRect(x: 1920, y: 0, width: 1920, height: 1080),
        CGRect(x: 0, y: 0, width: 1920, height: 1080),
    ]

    static let xTolerance: CGFloat = 1.0 // logical px
    static let yTolerance: CGFloat = 1.0 // logical px
    // How many frames past the relay instant X stays checked -- measured
    // divergence crosses 1px around frame +19 for a departure (the two
    // simulations' accelerations start to differ); 15 frames (~0.5s) is
    // comfortably inside that and covers roughly how long the sprite
    // actually takes to cross the shared edge.
    static let xWindowFrames = 15

    /// world X in logical px, treating sky as [0, width) and airport as
    /// [width, 2*width) -- see file header for why this skips the
    /// physical-frame conversion.
    static func airportWorldX(_ localX: CGFloat) -> CGFloat { CGFloat(width) + localX }
    static func skyWorldX(_ localX: CGFloat) -> CGFloat { localX }

    /// Departure crossing: a forced takeoff relayed from the airport screen
    /// onto its sky neighbor.
    static func checkDepartureCrossing() {
        FlightCoordinator.reseed(42)
        FlightCoordinator.shared.configure(frames: frames)

        let airport = AirportScene(canvasWidth: width, localTraffic: false)
        airport.onDepartureExit = { altitude, speed, variant in
            FlightCoordinator.shared.departureExited(altitude: altitude, speed: speed, variant: variant)
        }
        airport.departureDirection = { FlightCoordinator.shared.startDeparture() }
        FlightCoordinator.shared.registerAirport(airport)
        let sky = SkyScene(screenIndex: 1, canvasWidth: width)
        FlightCoordinator.shared.registerSky(sky)
        airport.forceTakeoff()

        var sawBothSides = false
        var checkedYAtInstant = false
        var framesSinceHandoff = -1
        var maxDX: CGFloat = 0

        var t = 0.0
        while t < 30 {
            let skyCountBefore = sky.planes.count
            airport.update(dt: dt)

            // The instant a relay fires, sky.spawn() has just run inside the
            // onDepartureExit callback -- before sky.update() gets to apply
            // its own (tighter) y-clamp -- so this is the one true "as
            // relayed" reading, letting us check FlightCoordinator's
            // documented clamp formula directly.
            if !checkedYAtInstant, sky.planes.count > skyCountBefore,
               let dep = airport.trackedPlanes.first(where: { $0.isDeparture }) {
                checkedYAtInstant = true
                framesSinceHandoff = 0
                let expectedSkyY = max(20, min(160, dep.worldY))
                let actualSkyY = sky.planes[0].y
                print(String(format: "departure relay instant: airport worldY=%.2f -> expected sky Y=%.2f, actual sky Y=%.2f",
                             dep.worldY, expectedSkyY, actualSkyY))
                assert(abs(expectedSkyY - actualSkyY) <= yTolerance,
                       "departure handoff: sky Y didn't match FlightCoordinator's documented altitude clamp")
            }

            sky.update(dt: dt)

            if framesSinceHandoff >= 0, framesSinceHandoff <= xWindowFrames,
               let dep = airport.trackedPlanes.first(where: { $0.isDeparture }), let skyPlane = sky.planes.first {
                sawBothSides = true
                let dx = airportWorldX(dep.worldX) - skyWorldX(skyPlane.x)
                maxDX = max(maxDX, abs(dx))
                assert(abs(dx) <= xTolerance, "departure handoff: world-x disagreed by \(dx) at frame +\(framesSinceHandoff)")
                framesSinceHandoff += 1
            } else if framesSinceHandoff > xWindowFrames {
                break
            }
            t += dt
        }

        assert(checkedYAtInstant, "departure handoff never fired -- plane never appeared on both sides")
        assert(sawBothSides, "departure handoff: plane never tracked on both sides during the X window")
        print(String(format: "departure crossing: max |world-x delta| over %d frames = %.3f (tolerance %.1f)", xWindowFrames, maxDX, xTolerance))
    }

    /// Arrival crossing: a plane spawned on the sky screen heading toward
    /// main, relayed into a runway approach.
    static func checkArrivalCrossing() {
        FlightCoordinator.reseed(42)
        FlightCoordinator.shared.configure(frames: frames)

        let airport = AirportScene(canvasWidth: width, localTraffic: false)
        FlightCoordinator.shared.registerAirport(airport)
        let sky = SkyScene(screenIndex: 1, canvasWidth: width)
        FlightCoordinator.shared.registerSky(sky)

        // Fast (140 px/s) so it crosses well before the airport's own
        // ambient idle-takeoff scheduler (8-15s) could fire and add an
        // unrelated flight to trackedPlanes.
        sky.spawn(fromLeft: true, y: 150, speed: 140, vy: 4, landing: true, variant: .random())

        var sawBothSides = false
        var checkedYAtInstant = false
        var framesSinceHandoff = -1
        var maxDX: CGFloat = 0

        var t = 0.0
        while t < 8 {
            airport.update(dt: dt)
            let airportCountBefore = airport.trackedPlanes.count

            // queueApproach (triggered from inside sky.update() via
            // skyPlaneExited) runs here; the new arrival hasn't been
            // stepped yet this frame (airport.update() already ran, above),
            // so this is the one true "as relayed" reading, same idea as
            // the departure case.
            sky.update(dt: dt)

            if !checkedYAtInstant, airport.trackedPlanes.count > airportCountBefore, let skyPlane = sky.planes.first {
                checkedYAtInstant = true
                framesSinceHandoff = 0
                let expectedAltitude = min(90, max(0, groundY - skyPlane.y))
                let expectedWorldY = groundY - expectedAltitude
                let actualWorldY = airport.trackedPlanes[0].worldY
                print(String(format: "arrival relay instant: sky Y=%.2f -> expected airport worldY=%.2f, actual worldY=%.2f",
                             skyPlane.y, expectedWorldY, actualWorldY))
                assert(abs(expectedWorldY - actualWorldY) <= yTolerance,
                       "arrival handoff: airport worldY didn't match FlightCoordinator's documented altitude clamp")
            }

            if framesSinceHandoff >= 0, framesSinceHandoff <= xWindowFrames,
               let arr = airport.trackedPlanes.first, let skyPlane = sky.planes.first {
                sawBothSides = true
                let dx = airportWorldX(arr.worldX) - skyWorldX(skyPlane.x)
                maxDX = max(maxDX, abs(dx))
                assert(abs(dx) <= xTolerance, "arrival handoff: world-x disagreed by \(dx) at frame +\(framesSinceHandoff)")
                framesSinceHandoff += 1
            } else if framesSinceHandoff > xWindowFrames {
                break
            }
            t += dt
        }

        assert(checkedYAtInstant, "arrival handoff never fired -- plane never appeared on both sides")
        assert(sawBothSides, "arrival handoff: plane never tracked on both sides during the X window")
        print(String(format: "arrival crossing: max |world-x delta| over %d frames = %.3f (tolerance %.1f)", xWindowFrames, maxDX, xTolerance))
    }

    static func main() {
        checkDepartureCrossing()
        checkArrivalCrossing()
        print("handoff_check OK")
    }
}
