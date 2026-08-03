//
//  RunwayPlane.swift
//  airport-saver
//
//  Pure kinematic simulation of one aircraft moving through a landing or
//  takeoff on the runway. No rendering, no AppKit -- only CoreGraphics for
//  CGFloat, so this compiles standalone in checks/runway_check.swift.
//
//  Geometry (x, touchdown/rotate/apron points) is expressed relative to
//  canvasWidth so a flight looks the same shape on any monitor; velocities
//  and accelerations are fixed px/s constants -- pixel-art motion reads as
//  constant speed regardless of window width, it doesn't scale with it.

import CoreGraphics

/// Stage of a single flight through the runway simulation. Landings run
/// approach -> rollout -> taxiIn -> parkPause -> taxiOut -> done; takeoffs
/// run taxiToRunway -> lineUp -> takeoffRoll -> climb -> done. Both flows
/// now start and end fully offscreen -- no more "parked forever" plane
/// left sitting at the apron, no more instant apron pop for a departure.
enum RunwayPhase: Equatable {
    case approach
    case rollout
    case taxiIn
    case parkPause
    case taxiOut
    case taxiToRunway
    case lineUp
    case takeoffRoll
    case climb
    case done
}

/// Kinematic state of one aircraft. `x` is the plane's horizontal reference
/// point (its center, not a bounding-box edge -- the sprite isn't known at
/// this layer) in logical canvas pixels; `altitude` is height above the
/// runway surface in the same units; `speed` is signed horizontal velocity
/// in px/s (negative = moving left).
struct RunwayPlane {
    var phase: RunwayPhase
    var x: CGFloat
    var altitude: CGFloat
    var speed: CGFloat

    // MARK: - Tuning

    private static let entryMargin: CGFloat = 120         // off-screen spawn/exit distance for airborne approach/climb
    private static let groundEntryMargin: CGFloat = 80    // off-screen spawn/exit distance for ground taxi, fully clears the widest sprite (~107px wide)
    private static let touchdownFraction: CGFloat = 0.62  // where a landing's wheels touch
    private static let rotateFraction: CGFloat = 0.72     // where a departure lifts off
    private static let apronX: CGFloat = 90               // fixed: traffic parks near the buildings, which stay pinned to screen-left regardless of canvasWidth

    private static let approachAltitude: CGFloat = 90
    private static let approachSpeed: CGFloat = -42
    private static let rolloutDeceleration: CGFloat = 9   // px/s^2, brings |speed| down to taxiSpeed
    private static let taxiSpeed: CGFloat = -16           // px/s, ground taxi magnitude -- taxiIn/taxiOut use it negative (toward/away from apron), taxiToRunway uses -taxiSpeed (positive, offscreen-left to apron)
    private static let parkPauseDuration: CGFloat = 6     // s, engine-off dwell at the apron before taxiing back out
    private static let lineUpDuration: CGFloat = 1.2      // s, holding at the threshold before rolling
    private static let takeoffAcceleration: CGFloat = 9   // px/s^2
    private static let climbSpeedGain: CGFloat = 6        // px/s^2, gentle continued acceleration once airborne
    private static let climbRate: CGFloat = 28            // px/s vertical, during climb

    /// Only meaningful during `.lineUp`; how long we've been holding.
    private var lineUpTimer: CGFloat = 0
    /// Only meaningful during `.parkPause`; how long we've been sitting at the apron.
    private var parkPauseElapsed: CGFloat = 0

    static func landing(canvasWidth: CGFloat) -> RunwayPlane {
        RunwayPlane(phase: .approach, x: canvasWidth + entryMargin, altitude: approachAltitude, speed: approachSpeed)
    }

    // canvasWidth unused: both apronX and groundEntryMargin are fixed on
    // purpose (see apronX's doc above -- traffic parks near the
    // screen-left buildings regardless of monitor width), so a takeoff's
    // start position never needs it. Parameter kept for call-site symmetry
    // with .landing(canvasWidth:) -- both are called the same way from
    // AirportScene.startLanding/startTakeoff.
    static func takeoff(canvasWidth _: CGFloat) -> RunwayPlane {
        RunwayPlane(phase: .taxiToRunway, x: -groundEntryMargin, altitude: 0, speed: -taxiSpeed)
    }

    mutating func step(dt: CGFloat, canvasWidth: CGFloat) {
        let touchdownX = canvasWidth * Self.touchdownFraction
        let rotateX = canvasWidth * Self.rotateFraction
        let exitX = canvasWidth + Self.entryMargin

        switch phase {
        case .approach:
            x += speed * dt
            let totalDistance = (canvasWidth + Self.entryMargin) - touchdownX
            let remaining = max(x - touchdownX, 0)
            altitude = totalDistance > 0 ? Self.approachAltitude * (remaining / totalDistance) : 0
            if x <= touchdownX {
                x = touchdownX
                altitude = 0
                phase = .rollout
            }

        case .rollout:
            x += speed * dt
            altitude = 0
            // On a narrow canvas the apron can be closer than the braking
            // distance needs -- check it before the speed-based transition
            // so rollout can't overshoot past it (which would otherwise
            // hand taxiIn an x already below apronX, snapping back up to
            // it next step: a visible backward teleport).
            if x <= Self.apronX {
                x = Self.apronX
                speed = 0
                phase = .parkPause
            } else {
                speed = min(speed + Self.rolloutDeceleration * dt, Self.taxiSpeed)
                if speed >= Self.taxiSpeed {
                    phase = .taxiIn
                }
            }

        case .taxiIn:
            x += speed * dt
            altitude = 0
            if x <= Self.apronX {
                x = Self.apronX
                speed = 0
                phase = .parkPause
            }

        case .parkPause:
            altitude = 0
            speed = 0
            parkPauseElapsed += dt
            if parkPauseElapsed >= Self.parkPauseDuration {
                phase = .taxiOut
                speed = Self.taxiSpeed // resume rolling the same direction taxiIn arrived from
            }

        case .taxiOut:
            x += speed * dt
            altitude = 0
            if x <= -Self.groundEntryMargin {
                phase = .done
            }

        case .taxiToRunway:
            x += speed * dt
            altitude = 0
            if x >= Self.apronX {
                x = Self.apronX
                speed = 0
                phase = .lineUp
            }

        case .lineUp:
            altitude = 0
            speed = 0
            lineUpTimer += dt
            if lineUpTimer >= Self.lineUpDuration {
                phase = .takeoffRoll
            }

        case .takeoffRoll:
            speed += Self.takeoffAcceleration * dt
            x += speed * dt
            altitude = 0
            if x >= rotateX {
                phase = .climb
            }

        case .climb:
            speed += Self.climbSpeedGain * dt
            x += speed * dt
            altitude += Self.climbRate * dt
            if x >= exitX {
                phase = .done
            }

        case .done:
            break
        }
    }
}
