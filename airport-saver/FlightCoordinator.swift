//
//  FlightCoordinator.swift
//  airport-saver
//
//  Singleton shared by every screen's scene instance -- all screens animate
//  in the same process on the main thread, so this is plain mutable state,
//  no locks. Relays a plane between screens: exits one screen's edge,
//  enters the adjacent screen's opposite edge, same heading/altitude/variant.
//

import CoreGraphics
import Foundation
import QuartzCore

final class FlightCoordinator {
    static let shared = FlightCoordinator()

    private(set) var topology = ScreenTopology(frames: [])
    private var lastFrames: [CGRect] = []
    private weak var airport: AirportScene?

    /// Weak, not strong: a sky scene whose view got torn down (display
    /// sleep, screen unplug) must stop being a relay target -- a strong
    /// ref here would keep swallowing planes handed to a dead scene that
    /// no longer draws or updates.
    private struct WeakSky { weak var scene: SkyScene? }
    private var skyScenes: [Int: WeakSky] = [:]
    private var nextArrival: TimeInterval = 0

    // Alternates which side of the main screen the next departure/arrival
    // uses, when both a left and a right neighbor exist -- otherwise a
    // main screen sitting in the middle of the row always sends traffic
    // one way and the other neighbor never sees a plane.
    private var nextDepartureGoesRight = true
    private var nextArrivalGoesRight = true

    // Set by startDeparture() the instant a takeoff begins rolling and
    // consumed by departureExited() when it later crosses the runway's
    // edge -- the side is decided at the START of the roll (not at exit)
    // so AirportScene can mirror the whole animation consistently from
    // frame one, with the eventual leading-edge handoff landing on
    // whichever neighbor was actually decided on. Only one departure is
    // ever in flight on the main screen at a time, so a single slot
    // (rather than a queue, cf. queuedApproaches) is enough.
    private var pendingDeparture: (slot: Int, goingRight: Bool)?

    // Matches AirportScene's runway ground line (horizon 176 + the runway
    // band's midpoint at horizon+32...horizon+72 = 228) -- duplicated as a
    // plain constant here so a departure's exit altitude converts into a
    // sky-scene Y that lines up with the runway on handoff, without
    // exposing AirportScene's private layout internals.
    private let airportGroundY: CGFloat = 228

    private init() {}

    /// Idempotent: only recomputes topology (and resets the arrival timer)
    /// when the screen arrangement actually changed, so every scene can
    /// call this from its own init without restarting the arrival
    /// schedule. Compares the full frames array, not just the count --
    /// screens rearranged or swapped for a different size keep the same
    /// count but need a fresh topology.
    func configure(frames: [CGRect]) {
        guard frames != lastFrames else { return }
        lastFrames = frames
        topology = ScreenTopology(frames: frames)
        // Old slot indices no longer mean anything against the new
        // topology -- drop every registration rather than relay into
        // whatever scene happens to still occupy a given slot number.
        skyScenes.removeAll()
        pendingDeparture = nil
        // AirportScene.localTraffic was only ever set from hasSkySlots at
        // init; push the freshly recomputed value onto an already-live
        // airport so a topology change (a sky screen added/removed after
        // the airport scene was created) doesn't leave it stale.
        airport?.localTraffic = !hasSkySlots
        nextArrival = CACurrentMediaTime() + TimeInterval.random(in: 25...45)
    }

    func registerAirport(_ scene: AirportScene) { airport = scene }
    func registerSky(_ scene: SkyScene) { skyScenes[scene.slot] = WeakSky(scene: scene) }

    var hasSkySlots: Bool { topology.slotCount > 1 }

    /// Decides which neighbor a new departure is headed for -- the slot to
    /// the right of main, or the slot to its left (entered mirrored, flying
    /// left instead of right) if that's the only neighbor, or whichever
    /// side is due next when both exist (see `nextDepartureGoesRight`), so
    /// a main screen sitting between two others doesn't always send
    /// departures the same way and leave the other neighbor's sky empty.
    ///
    /// Called by AirportScene the instant a takeoff *starts* rolling (not
    /// when it exits): the whole roll must render mirrored consistently
    /// from frame one so the eventual leading-edge crossing lines up with
    /// this decision. Returns AirportScene's direction convention (+1
    /// right, -1 left); with no sky neighbor at all there's nothing to
    /// mirror for, so this returns +1 and clears any pending target --
    /// departureExited becomes a no-op.
    func startDeparture() -> Int {
        let main = topology.mainSlot
        let hasRight = main + 1 < topology.slotCount
        let hasLeft = main - 1 >= 0
        guard hasRight || hasLeft else {
            pendingDeparture = nil
            return 1
        }
        let goRight: Bool
        if hasRight, hasLeft {
            goRight = nextDepartureGoesRight
            nextDepartureGoesRight.toggle()
        } else {
            goRight = hasRight
        }
        pendingDeparture = (goRight ? main + 1 : main - 1, goRight)
        return goRight ? 1 : -1
    }

    /// A departing flight's leading edge crossed the main screen's edge;
    /// hand it to the neighbor slot decided back in `startDeparture()`,
    /// still climbing (small negative vy), carrying the speed it actually
    /// exited the runway at rather than a guessed value.
    func departureExited(altitude: CGFloat, speed: CGFloat, variant: FleetVariant) {
        guard let dep = pendingDeparture, let sky = skyScenes[dep.slot]?.scene else { return }
        pendingDeparture = nil
        let y = max(20, min(160, airportGroundY - altitude))
        sky.spawn(fromLeft: dep.goingRight, y: y, speed: speed, vy: -3, landing: false, variant: variant)
    }

    /// A sky plane's leading edge crossed its slot's edge; relay it into
    /// the neighboring slot. If that neighbor is the main slot: a landing
    /// hands off to the runway (`queueApproach`), carrying the direction it
    /// entered from (so AirportScene mirrors the approach to match), its
    /// speed, and an altitude derived from its sky height (clamped to the
    /// runway approach's own altitude range) so the crossing reads as one
    /// continuous plane, not a jump in height. Anything else instantly
    /// skips over the main screen to the following slot. Off the band of
    /// slots entirely, the plane is simply not re-spawned (despawns).
    func skyPlaneExited(slot: Int, plane: SkyPlane) {
        let goingRight = plane.vx > 0
        var next = slot + (goingRight ? 1 : -1)
        if next == topology.mainSlot {
            if plane.landing {
                // Entering main from a lower-index (left) slot while moving
                // right means arriving via main's LEFT edge (direction -1);
                // from a higher-index (right) slot moving left means
                // arriving via main's RIGHT edge (direction +1).
                let direction = goingRight ? -1 : 1
                let altitude = min(90, max(0, airportGroundY - plane.y))
                airport?.queueApproach(variant: plane.variant, direction: direction, speed: abs(plane.vx), altitude: altitude)
                return
            }
            next += goingRight ? 1 : -1
        }
        guard next >= 0, next < topology.slotCount, let sky = skyScenes[next]?.scene else { return }
        sky.spawn(fromLeft: goingRight, y: plane.y, speed: abs(plane.vx), vy: plane.vy, landing: plane.landing, variant: plane.variant)
    }

    /// Called every frame by each sky scene's update; advances the
    /// periodic-arrival schedule when due. `nextArrival` is pushed forward
    /// on every fire (see below), so multiple sky scenes calling this with
    /// the same `now` in one frame can't double-spawn -- no extra
    /// once-per-frame guard needed.
    func tick(now: TimeInterval) {
        guard hasSkySlots, now >= nextArrival else { return }
        nextArrival = now + TimeInterval.random(in: 25...45)

        // Same left/right alternation as startDeparture: pick whichever
        // far edge is due next when main sits strictly between both edges,
        // so a middle main screen doesn't always relay arrivals in from
        // the same side.
        let main = topology.mainSlot
        let hasRight = main < topology.slotCount - 1
        let hasLeft = main > 0
        guard hasRight || hasLeft else { return }
        let goRight: Bool
        if hasRight, hasLeft {
            goRight = nextArrivalGoesRight
            nextArrivalGoesRight.toggle()
        } else {
            goRight = hasRight
        }
        let farSlot = goRight ? topology.slotCount - 1 : 0
        guard let sky = skyScenes[farSlot]?.scene else { return }
        sky.spawn(fromLeft: farSlot < main, y: CGFloat.random(in: 40...100), speed: 48, vy: 4, landing: true, variant: .random())
    }
}
