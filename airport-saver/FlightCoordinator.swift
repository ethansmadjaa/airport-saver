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
    /// no longer draws or updates. Keyed by real NSScreen.screens index
    /// (SkyScene.screenIndex), not chain slot -- a screen stacked above/
    /// below the main horizontal chain has no slot at all but still needs
    /// to be addressable for vertical relay.
    private struct WeakSky { weak var scene: SkyScene? }
    private var skyScenes: [Int: WeakSky] = [:]
    private var nextArrival: TimeInterval = 0
    /// NSScreen.screens index of the main/airport screen -- hardcoded like
    /// the rest of this codebase (AirportSaverView routes screenIndex == 0
    /// to the airport scene); real screen-index-based routing needs an
    /// explicit anchor to walk left/right/above/below from.
    private let mainScreen = 0

    /// Single seeding point for every scene's traffic randomness (spawn
    /// timing, fleet picks, positions, speeds) -- AirportScene/SkyScene/
    /// FleetVariant.random() all draw from this one generator via
    /// `FlightCoordinator.shared.rng` (main-thread only, same as the rest of
    /// this singleton, so a plain var is fine). Seeded from wall clock by
    /// default so normal runs stay varied; `reseed(_:)` pins it for
    /// reproducible renders.
    var rng = SplitMix64(seed: UInt64(Date().timeIntervalSince1970))

    /// Render-harness hook: pins the shared RNG to a known seed so two runs
    /// of the same command produce byte-identical traffic. Never called by
    /// the real screensaver.
    static func reseed(_ seed: UInt64) {
        shared.rng = SplitMix64(seed: seed)
    }

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
    private var pendingDeparture: (screen: Int, goingRight: Bool)?

    // A go-around's retry landing: scheduled by `goAroundExited` for
    // 20-40s later, fired by `tick(now:)` independently of the ambient
    // periodic-arrival schedule below (a retry shouldn't have to wait on
    // that unrelated timer). A list, not a slot -- more than one go-around
    // can be waiting to retry at once (cf. `pendingDeparture`, which really
    // is single-slot: only one departure is ever mid-roll on the main
    // screen at a time).
    private var pendingRetryArrivals: [(fireAt: TimeInterval, variant: FleetVariant)] = []

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
        pendingRetryArrivals.removeAll()
        // AirportScene.localTraffic was only ever set from hasSkySlots at
        // init; push the freshly recomputed value onto an already-live
        // airport so a topology change (a sky screen added/removed after
        // the airport scene was created) doesn't leave it stale.
        airport?.localTraffic = !hasSkySlots
        nextArrival = CACurrentMediaTime() + TimeInterval.random(in: 25...45, using: &rng)
    }

    func registerAirport(_ scene: AirportScene) { airport = scene }
    func registerSky(_ scene: SkyScene) { skyScenes[scene.screenIndex] = WeakSky(scene: scene) }

    var hasSkySlots: Bool { topology.slotCount > 1 }

    /// Whether `screen` is part of the main horizontal chain (reachable
    /// from the main screen via left/right adjacency). Chain members are
    /// fed entirely by relay (departures/arrivals/handoffs), so they
    /// suppress their own ambient spawns; a screen only reachable
    /// vertically (or not reachable at all) keeps generating local traffic
    /// so it's never dead -- see SkyScene.update.
    func isChainMember(_ screen: Int) -> Bool {
        topology.slotForScreen.indices.contains(screen) && topology.slotForScreen[screen] != nil
    }

    /// Decides which neighbor a new departure is headed for -- the real
    /// screen to the right of main, or to its left (entered mirrored,
    /// flying left instead of right) if that's the only neighbor, or
    /// whichever side is due next when both exist (see
    /// `nextDepartureGoesRight`), so a main screen sitting between two
    /// others doesn't always send departures the same way and leave the
    /// other neighbor's sky empty.
    ///
    /// Called by AirportScene the instant a takeoff *starts* rolling (not
    /// when it exits): the whole roll must render mirrored consistently
    /// from frame one so the eventual leading-edge crossing lines up with
    /// this decision. Returns AirportScene's direction convention (+1
    /// right, -1 left); with no sky neighbor at all there's nothing to
    /// mirror for, so this returns +1 and clears any pending target --
    /// departureExited becomes a no-op.
    func startDeparture() -> Int {
        let rightScreen = topology.neighbor(of: mainScreen, .right)
        let leftScreen = topology.neighbor(of: mainScreen, .left)
        guard rightScreen != nil || leftScreen != nil else {
            pendingDeparture = nil
            return 1
        }
        let goRight: Bool
        if rightScreen != nil, leftScreen != nil {
            goRight = nextDepartureGoesRight
            nextDepartureGoesRight.toggle()
        } else {
            goRight = rightScreen != nil
        }
        pendingDeparture = (goRight ? rightScreen! : leftScreen!, goRight)
        return goRight ? 1 : -1
    }

    /// A departing flight's leading edge crossed the main screen's edge;
    /// hand it to the neighbor screen decided back in `startDeparture()`,
    /// still climbing (small negative vy), carrying the speed it actually
    /// exited the runway at rather than a guessed value.
    func departureExited(altitude: CGFloat, speed: CGFloat, variant: FleetVariant) {
        guard let dep = pendingDeparture, let sky = skyScenes[dep.screen]?.scene else { return }
        pendingDeparture = nil
        let y = max(20, min(160, airportGroundY - altitude))
        sky.spawn(fromLeft: dep.goingRight, y: y, speed: speed, vy: -3, landing: false, variant: variant)
    }

    /// A go-around's leading edge crossed the main screen's exit edge --
    /// the far side from wherever it entered, since `AirportScene` never
    /// changes a flight's `direction` mid-flight (see RunwayPlane.goAround's
    /// doc: it keeps travelling the same native way, so it crosses the
    /// screen edge opposite its entry edge). `direction == 1` entered via
    /// the RIGHT edge, so its exit this time is via the LEFT -- and vice
    /// versa -- which is exactly the opposite of `startDeparture`'s
    /// `goRight -> direction` mapping.
    ///
    /// Relayed into the sky like a departure (same overlap-handoff
    /// mechanics as `departureExited`, just resolved here instead of via
    /// `pendingDeparture` since a go-around was never a "departure" to
    /// begin with): if nothing lies on that side, the plane simply isn't
    /// drawn again mid-transit, same as a departure with nowhere to hand
    /// off to. Either way, its retry landing is scheduled 20-40s out,
    /// carrying the same variant so it visibly is the same plane coming
    /// back around -- never re-queued immediately, per the whole point of
    /// a go-around.
    func goAroundExited(direction: Int, altitude: CGFloat, speed: CGFloat, variant: FleetVariant) {
        let exitGoingRight = direction == -1
        if let neighbor = topology.neighbor(of: mainScreen, exitGoingRight ? .right : .left),
           let sky = skyScenes[neighbor]?.scene {
            let y = max(20, min(160, airportGroundY - altitude))
            sky.spawn(fromLeft: exitGoingRight, y: y, speed: speed, vy: -3, landing: false, variant: variant)
        }
        pendingRetryArrivals.append((fireAt: CACurrentMediaTime() + .random(in: 20...40, using: &rng), variant: variant))
    }

    /// A sky plane's leading edge crossed its screen's left/right edge;
    /// relay it to the real neighboring screen in that direction. If that
    /// neighbor is the main screen: a landing hands off to the runway
    /// (`queueApproach`), carrying the direction it entered from (so
    /// AirportScene mirrors the approach to match), its speed, and an
    /// altitude derived from its sky height (clamped to the runway
    /// approach's own altitude range) so the crossing reads as one
    /// continuous plane, not a jump in height. Anything else instantly
    /// skips over the main screen to whatever lies beyond it in the same
    /// direction. Off the end of the chain entirely, the plane is simply
    /// not re-spawned (despawns).
    func skyPlaneExited(screen: Int, plane: SkyPlane) {
        let goingRight = plane.vx > 0
        let direction: ScreenTopology.Direction = goingRight ? .right : .left
        guard var next = topology.neighbor(of: screen, direction) else { return }
        if next == mainScreen {
            if plane.landing {
                // Entering main from the left while moving right means
                // arriving via main's LEFT edge (direction -1); from the
                // right moving left means arriving via main's RIGHT edge
                // (direction +1).
                let arrivalDirection = goingRight ? -1 : 1
                let altitude = min(90, max(0, airportGroundY - plane.y))
                airport?.queueApproach(variant: plane.variant, direction: arrivalDirection, speed: abs(plane.vx), altitude: altitude)
                return
            }
            guard let beyond = topology.neighbor(of: mainScreen, direction) else { return }
            next = beyond
        }
        guard let sky = skyScenes[next]?.scene else { return }
        sky.spawn(fromLeft: goingRight, y: plane.y, speed: abs(plane.vx), vy: plane.vy, landing: plane.landing, variant: plane.variant)
    }

    /// A climbing sky plane's leading edge reached the top of its screen
    /// (see SkyScene.update's y-clamp -- "the top edge" as today's leveling
    /// altitude); if a screen sits physically above it, relay the plane
    /// there instead of letting it level off, entering from the bottom edge
    /// at the matching physical x. Screens can differ in width/aspect
    /// ratio, so the physical frames (the one ruler both screens share) map
    /// the crossing x onto the target's own canvas-logical space rather
    /// than reusing a raw fraction of this screen's width. Returns whether
    /// a relay happened; false means the caller should just let its
    /// existing altitude clamp level the plane off, exactly as when there's
    /// no screen above.
    func relayClimbOut(from screen: Int, plane: SkyPlane) -> Bool {
        guard let above = topology.neighbor(of: screen, .above),
              let sky = skyScenes[above]?.scene,
              let fromFrame = topology.frame(of: screen),
              let toFrame = topology.frame(of: above),
              screen < topology.logicalWidths.count, above < topology.logicalWidths.count
        else { return false }
        let fromWidth = CGFloat(topology.logicalWidths[screen])
        let toWidth = CGFloat(topology.logicalWidths[above])
        guard fromWidth > 0, toFrame.width > 0 else { return false }
        let physicalX = fromFrame.minX + (plane.x / fromWidth) * fromFrame.width
        let clampedX = min(max(physicalX, toFrame.minX), toFrame.maxX)
        let targetX = (clampedX - toFrame.minX) / toFrame.width * toWidth
        sky.spawnClimbing(x: targetX, vx: plane.vx, vy: plane.vy, variant: plane.variant)
        return true
    }

    /// Called every frame by each sky scene's update; advances the
    /// periodic-arrival schedule when due. `nextArrival` is pushed forward
    /// on every fire (see below), so multiple sky scenes calling this with
    /// the same `now` in one frame can't double-spawn -- no extra
    /// once-per-frame guard needed.
    /// Sends one arrival in at the far end of the horizontal chain,
    /// alternating which edge is due next the same way `startDeparture`
    /// does, so a main screen sitting strictly between two others doesn't
    /// always relay arrivals in from the same side. Shared by the ambient
    /// periodic schedule (`tick`) and a go-around's forced retry -- both
    /// enter a fresh arrival the exact same way, just with a specific
    /// variant instead of a random one.
    private func spawnArrivalAtFarEnd(variant: FleetVariant) {
        let rightScreen = topology.neighbor(of: mainScreen, .right)
        let leftScreen = topology.neighbor(of: mainScreen, .left)
        guard rightScreen != nil || leftScreen != nil else { return }
        let goRight: Bool
        if rightScreen != nil, leftScreen != nil {
            goRight = nextArrivalGoesRight
            nextArrivalGoesRight.toggle()
        } else {
            goRight = rightScreen != nil
        }
        // Walk to the far end of the chain in that direction so the
        // arrival always spawns off the edge of the whole horizontal run,
        // not just main's immediate neighbor.
        var far = mainScreen
        while let next = topology.neighbor(of: far, goRight ? .right : .left) {
            far = next
        }
        guard let sky = skyScenes[far]?.scene else { return }
        sky.spawn(fromLeft: !goRight, y: CGFloat.random(in: 40...100, using: &rng), speed: 48, vy: 4, landing: true, variant: variant)
    }

    func tick(now: TimeInterval) {
        guard hasSkySlots else { return }

        if now >= nextArrival {
            nextArrival = now + TimeInterval.random(in: 25...45, using: &rng)
            spawnArrivalAtFarEnd(variant: .random())
        }

        guard !pendingRetryArrivals.isEmpty else { return }
        let due = pendingRetryArrivals.filter { $0.fireAt <= now }
        guard !due.isEmpty else { return }
        pendingRetryArrivals.removeAll { $0.fireAt <= now }
        for retry in due { spawnArrivalAtFarEnd(variant: retry.variant) }
    }
}
