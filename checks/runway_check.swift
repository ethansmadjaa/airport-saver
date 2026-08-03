// Check de RunwayPlane. Compiler et lancer :
//   swiftc -o /tmp/runway_check airport-saver/RunwayPlane.swift checks/runway_check.swift && /tmp/runway_check
import CoreGraphics
import Foundation

@main
struct RunwayCheck {
    // MARK: - Duration invariants
    //
    // Per-phase durations at w=480, measured by instrumenting the
    // simulation loops below (accumulating dt while `phase` holds a given
    // value) then printed as a table every run -- if a future edit to a
    // tuning constant in RunwayPlane derails a phase's length, this table
    // makes the failure self-explanatory instead of just "assertion
    // failed". Windows are generous (+/-40% around the measured value, see
    // MEASURED comments) so real jitter/future tuning tweaks don't trip
    // this, but a genuinely deranged constant (10x, a dropped decel term,
    // a sign flip) still will. RunwayPlane's simulation is deterministic
    // (no randomness), so these are exact, reproducible values, not
    // statistics.
    // MEASURED (w=480, dt=1/30): approach=7.233s, rollout=2.900s,
    // taxiIn=7.733s, parkPause=6.033s, taxiOut=10.633s, taxiToRunway=10.633s,
    // takeoffRoll=7.533s, climb=3.267s, goAround(climb-out)=7.300s.
    static let windows: [String: ClosedRange<CGFloat>] = [
        "approach": 4.32...10.08,
        "rollout": 1.72...4.01,
        "taxiIn": 4.66...10.87,
        "parkPause": 3.60...8.40,
        "taxiOut": 6.38...14.89,
        "taxiToRunway": 6.38...14.89,
        "takeoffRoll": 4.54...10.59,
        "climb": 1.98...4.62,
        "goAround": 4.38...10.22,
    ]

    static func padName(_ s: String) -> String {
        s.count < 14 ? s + String(repeating: " ", count: 14 - s.count) : s
    }

    static func assertWindow(_ name: String, _ measured: CGFloat) {
        guard let range = windows[name] else {
            assertionFailure("no duration window declared for phase \(name)")
            return
        }
        let measuredStr = String(format: "%6.3fs", Double(measured))
        let windowStr = String(format: "%.2f...%.2f", Double(range.lowerBound), Double(range.upperBound))
        print("  \(padName(name)) \(measuredStr)  (window \(windowStr))")
        assert(range.contains(measured), "\(name) duration \(measured)s outside expected window \(range) -- a tuning constant likely drifted")
    }

    static func main() {
        let w: CGFloat = 480
        let dt: CGFloat = 1.0 / 30.0

        // Landing: altitude never negative, passes through rollout, a
        // parkPause dwell, and a taxiOut roll-away, and reaches done well
        // under 60s of simulated time fully offscreen left (no more
        // "stays parked at the apron forever" -- it taxis back out).
        var landing = RunwayPlane.landing(canvasWidth: w)
        var sawRollout = false
        var sawParkPause = false
        var sawTaxiOut = false
        var landingTime: CGFloat = 0
        var landingDurations: [RunwayPhase: CGFloat] = [:]
        while landing.phase != .done {
            let phaseBefore = landing.phase
            landing.step(dt: dt, canvasWidth: w)
            landingDurations[phaseBefore, default: 0] += dt
            landingTime += dt
            assert(landing.altitude >= 0, "landing altitude went negative")
            assert(landingTime < 60, "landing did not reach done within 60s")
            if landing.phase == .rollout { sawRollout = true }
            if landing.phase == .parkPause { sawParkPause = true }
            if landing.phase == .taxiOut { sawTaxiOut = true }
        }
        assert(sawRollout, "landing never passed through rollout")
        assert(sawParkPause, "landing never passed through parkPause")
        assert(sawTaxiOut, "landing never passed through taxiOut")
        assert(landing.altitude == 0, "landing finished airborne")
        assert(landing.x < 0, "landing did not finish fully offscreen left")

        // Takeoff: starts fully offscreen left, taxis slowly to the
        // lineup point (no more instant apron pop), then rolls and climbs
        // out past the right edge with a substantial climb altitude.
        var takeoff = RunwayPlane.takeoff(canvasWidth: w)
        assert(takeoff.x < 0, "takeoff did not start fully offscreen left")
        assert(takeoff.phase == .taxiToRunway, "takeoff did not start in taxiToRunway")
        var sawTaxiToRunway = false
        var sawLineUp = false
        var takeoffTime: CGFloat = 0
        var takeoffDurations: [RunwayPhase: CGFloat] = [:]
        while takeoff.phase != .done {
            let phaseBefore = takeoff.phase
            takeoff.step(dt: dt, canvasWidth: w)
            takeoffDurations[phaseBefore, default: 0] += dt
            takeoffTime += dt
            assert(takeoff.altitude >= 0, "takeoff altitude went negative")
            assert(takeoffTime < 60, "takeoff did not reach done within 60s")
            if takeoff.phase == .taxiToRunway { sawTaxiToRunway = true }
            if takeoff.phase == .lineUp { sawLineUp = true }
        }
        assert(sawTaxiToRunway, "takeoff never passed through taxiToRunway")
        assert(sawLineUp, "takeoff never passed through lineUp")
        assert(takeoff.x > w, "takeoff did not exit past the right edge")
        assert(takeoff.altitude > 40, "takeoff altitude too low at exit")

        // Go-around: an approach stepped with the runway busy (runwayFree:
        // false) must divert at its commit point instead of ever reaching
        // rollout -- climb back to a cruise-ish altitude, exit fully
        // offscreen the far side (still moving in the same direction it
        // was already travelling), never touch down, altitude never
        // negative, done well under 60s.
        var goAround = RunwayPlane.landing(canvasWidth: w)
        var sawGoAround = false
        var maxGoAroundAltitude: CGFloat = 0
        var goAroundTime: CGFloat = 0
        var goAroundPhaseDuration: CGFloat = 0
        while goAround.phase != .done {
            let phaseBefore = goAround.phase
            goAround.step(dt: dt, canvasWidth: w, runwayFree: false)
            if phaseBefore == .goAround { goAroundPhaseDuration += dt }
            goAroundTime += dt
            assert(goAround.altitude >= 0, "go-around altitude went negative")
            assert(goAround.phase != .rollout, "go-around touched down despite a busy runway")
            assert(goAroundTime < 60, "go-around did not reach done within 60s")
            if goAround.phase == .goAround {
                sawGoAround = true
                maxGoAroundAltitude = max(maxGoAroundAltitude, goAround.altitude)
            }
        }
        assert(sawGoAround, "go-around never entered .goAround phase")
        assert(maxGoAroundAltitude >= 60, "go-around did not climb back to a cruise-ish altitude")
        assert(goAround.x < 0, "go-around did not exit fully offscreen")

        // Unobstructed landing must be byte-identical to before: `step`'s
        // new `runwayFree` parameter defaults to `true`, so a landing that
        // never passes `runwayFree: false` must never divert.
        var unobstructed = RunwayPlane.landing(canvasWidth: w)
        while unobstructed.phase != .done {
            unobstructed.step(dt: dt, canvasWidth: w)
            assert(unobstructed.phase != .goAround, "unobstructed landing went around")
        }

        print("phase durations (w=480):")
        assertWindow("approach", landingDurations[.approach] ?? 0)
        assertWindow("rollout", landingDurations[.rollout] ?? 0)
        assertWindow("taxiIn", landingDurations[.taxiIn] ?? 0)
        assertWindow("parkPause", landingDurations[.parkPause] ?? 0)
        assertWindow("taxiOut", landingDurations[.taxiOut] ?? 0)
        assertWindow("taxiToRunway", takeoffDurations[.taxiToRunway] ?? 0)
        assertWindow("takeoffRoll", takeoffDurations[.takeoffRoll] ?? 0)
        assertWindow("climb", takeoffDurations[.climb] ?? 0)
        assertWindow("goAround", goAroundPhaseDuration)

        print("runway_check OK")
    }
}
