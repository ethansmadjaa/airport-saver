// Check de RunwayPlane. Compiler et lancer :
//   swiftc -o /tmp/runway_check airport-saver/RunwayPlane.swift checks/runway_check.swift && /tmp/runway_check
import CoreGraphics

@main
struct RunwayCheck {
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
        while landing.phase != .done {
            landing.step(dt: dt, canvasWidth: w)
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
        while takeoff.phase != .done {
            takeoff.step(dt: dt, canvasWidth: w)
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

        print("runway_check OK")
    }
}
