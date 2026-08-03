// Harnais de rendu : dessine une scène dans le PixelCanvas et écrit un PNG
// (agrandi x2 nearest-neighbor) pour inspection visuelle par un agent.
//
// Compiler + lancer :
//   swiftc -o /tmp/render airport-saver/PixelCanvas.swift airport-saver/PixelScene.swift \
//     airport-saver/Sprites.swift airport-saver/RunwayPlane.swift airport-saver/ScreenTopology.swift \
//     airport-saver/AirportScene.swift airport-saver/SkyScene.swift airport-saver/FlightCoordinator.swift \
//     checks/render.swift \
//   && /tmp/render airport /tmp/airport.png 480 0.4
//
// usage: render <scene> <out.png> [width=480] [time=0.4] [seed=42]
// scènes connues : airport (AirportScene), sky (SkyScene), handoff (two-screen
// composite -- see below). `seed` pins FlightCoordinator.shared.rng so the
// same command reproduces byte-identical traffic; omit it for the default
// (still fixed at 42, not wall-clock) or pass a different value to see
// different-but-reproducible traffic.

import AppKit
import ImageIO

@main
struct Render {
    /// Two-screen composite: a sky slot to the LEFT of the main/airport
    /// slot (matches a real secondary-monitor-on-the-left setup), a forced
    /// takeoff at t=0 and a forced arrival spawned once the takeoff has had
    /// time to clear, stepped in lockstep at 1/30 up to `time`, then both
    /// canvases drawn side by side (sky left, airport right, a black bezel
    /// gap between) into one wide PNG -- there's no multi-monitor hardware
    /// to visually verify the cross-screen handoff on, so this is the
    /// stand-in: one image with both screens' output at the same instant.
    static func renderHandoff(outPath: String, width: Int, time: Double) {
        // screens[0] (the AppKit-style "main" display) sits physically on
        // the RIGHT; screens[1] is the sky screen to its LEFT. Realistic
        // 16:9 frames (1920x1080 -> logical width 480, same as
        // topology_check's assertion).
        let frames = [
            CGRect(x: 1920, y: 0, width: 1920, height: 1080),
            CGRect(x: 0, y: 0, width: 1920, height: 1080),
        ]
        FlightCoordinator.shared.configure(frames: frames)

        let airport = AirportScene(canvasWidth: width, localTraffic: false)
        airport.onDepartureExit = { altitude, speed, variant in
            FlightCoordinator.shared.departureExited(altitude: altitude, speed: speed, variant: variant)
        }
        airport.onGoAroundExit = { altitude, speed, variant, direction in
            FlightCoordinator.shared.goAroundExited(direction: direction, altitude: altitude, speed: speed, variant: variant)
        }
        airport.departureDirection = { FlightCoordinator.shared.startDeparture() }
        FlightCoordinator.shared.registerAirport(airport)

        // screens[1] in this synthetic setup is the sky screen physically
        // left of main -- its identity for FlightCoordinator is its real
        // NSScreen.screens index (1), not a chain slot.
        let sky = SkyScene(screenIndex: 1, canvasWidth: width)
        FlightCoordinator.shared.registerSky(sky)

        airport.forceTakeoff()

        // Spawned once the takeoff has long since crossed and despawned,
        // so the arrival-crossing renders show a clean single plane
        // instead of two events at once. Starts moving right across the
        // sky screen (fromLeft: true) toward main, i.e. toward the runway
        // screen on its right -- the same direction a real left-neighbor
        // arrival takes.
        //
        // A forced takeoff now spends ~10.6s taxiing in from offscreen
        // plus ~1.2s lineUp before it even starts its roll (the taxi-in
        // fix), so its exit-crossing/handoff lands around t=~20.5s and
        // it's fully offscreen by ~t=23s -- push this well past that.
        let arrivalSpawnTime = 26.0
        var arrivalSpawned = false

        var t = 0.0
        let dt = 1.0 / 30.0
        while t < time {
            if !arrivalSpawned, t >= arrivalSpawnTime {
                arrivalSpawned = true
                sky.spawn(fromLeft: true, y: 150, speed: 55, vy: 4, landing: true, variant: .random())
            }
            airport.update(dt: dt)
            sky.update(dt: dt)
            t += dt
        }

        let skyCanvas = PixelCanvas(width: width)
        skyCanvas.clear()
        sky.draw(on: skyCanvas)
        let airportCanvas = PixelCanvas(width: width)
        airportCanvas.clear()
        airport.draw(on: airportCanvas)

        let gap = 6
        let scale = 2
        let compWidth = (skyCanvas.width + gap + airportCanvas.width) * scale
        let compHeight = max(skyCanvas.height, airportCanvas.height) * scale
        guard let compCtx = CGContext(
            data: nil, width: compWidth, height: compHeight,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            print("composite context a échoué")
            exit(1)
        }
        compCtx.interpolationQuality = .none
        compCtx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        compCtx.fill(CGRect(x: 0, y: 0, width: compWidth, height: compHeight))
        if let skyImg = skyCanvas.image() {
            compCtx.draw(skyImg, in: CGRect(x: 0, y: 0, width: skyCanvas.width * scale, height: skyCanvas.height * scale))
        }
        if let airportImg = airportCanvas.image() {
            compCtx.draw(airportImg, in: CGRect(
                x: (skyCanvas.width + gap) * scale, y: 0,
                width: airportCanvas.width * scale, height: airportCanvas.height * scale
            ))
        }
        guard let compImg = compCtx.makeImage() else {
            print("composite makeImage a échoué")
            exit(1)
        }
        let url = URL(fileURLWithPath: outPath) as CFURL
        guard let dest = CGImageDestinationCreateWithURL(url, "public.png" as CFString, 1, nil) else {
            print("destination PNG a échoué")
            exit(1)
        }
        CGImageDestinationAddImage(dest, compImg, nil)
        CGImageDestinationFinalize(dest)
        print("wrote \(outPath) (t=\(time)s)")
    }

    /// Two-screen VERTICAL composite: a sky screen stacked directly ABOVE
    /// another sky screen (e.g. laptop's external monitor sitting on top of
    /// it), no airport/runway involved -- proves the new climb-out relay
    /// (FlightCoordinator.relayClimbOut / SkyScene.spawnClimbing) end to
    /// end, since there's no real vertical monitor stack to check this on.
    /// A plane is seeded already climbing near the top of the lower
    /// screen at t=0 so it reaches the relay threshold (y<=12) well before
    /// `time`; both canvases are stepped in lockstep then stacked with the
    /// lower screen's canvas at the bottom of the composite image (visual
    /// bottom = physical bottom) and a black bezel gap between them.
    static func renderVerticalHandoff(outPath: String, width: Int, time: Double) {
        let belowFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let aboveFrame = CGRect(x: 0, y: 1080, width: 1920, height: 1080)
        FlightCoordinator.shared.configure(frames: [belowFrame, aboveFrame])

        let below = SkyScene(screenIndex: 0, canvasWidth: width)
        let above = SkyScene(screenIndex: 1, canvasWidth: width)
        FlightCoordinator.shared.registerSky(below)
        FlightCoordinator.shared.registerSky(above)

        // Already climbing steeply, close to the leveling-off altitude --
        // crosses the y<=12 relay threshold within ~1s, well before a real
        // departure's climb would, so this render doesn't need to also
        // simulate a full taxi/takeoff roll.
        below.spawn(fromLeft: true, y: 40, speed: 40, vy: -6, landing: false, variant: .random())

        var t = 0.0
        let dt = 1.0 / 30.0
        while t < time {
            below.update(dt: dt)
            above.update(dt: dt)
            t += dt
        }

        let belowCanvas = PixelCanvas(width: width)
        belowCanvas.clear()
        below.draw(on: belowCanvas)
        let aboveCanvas = PixelCanvas(width: width)
        aboveCanvas.clear()
        above.draw(on: aboveCanvas)

        let gap = 6
        let scale = 2
        let compWidth = max(belowCanvas.width, aboveCanvas.width) * scale
        let compHeight = (belowCanvas.height + gap + aboveCanvas.height) * scale
        guard let compCtx = CGContext(
            data: nil, width: compWidth, height: compHeight,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            print("composite context a échoué")
            exit(1)
        }
        compCtx.interpolationQuality = .none
        compCtx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        compCtx.fill(CGRect(x: 0, y: 0, width: compWidth, height: compHeight))
        // This context's origin is bottom-left (y up, standard CG bitmap
        // convention) -- placing the BELOW screen's canvas at y=0 puts it
        // at the visual bottom of the composite and the ABOVE screen's
        // canvas above the gap puts it at the visual top, matching their
        // real physical stacking.
        if let belowImg = belowCanvas.image() {
            compCtx.draw(belowImg, in: CGRect(x: 0, y: 0, width: belowCanvas.width * scale, height: belowCanvas.height * scale))
        }
        if let aboveImg = aboveCanvas.image() {
            compCtx.draw(aboveImg, in: CGRect(
                x: 0, y: (belowCanvas.height + gap) * scale,
                width: aboveCanvas.width * scale, height: aboveCanvas.height * scale
            ))
        }
        guard let compImg = compCtx.makeImage() else {
            print("composite makeImage a échoué")
            exit(1)
        }
        let url = URL(fileURLWithPath: outPath) as CFURL
        guard let dest = CGImageDestinationCreateWithURL(url, "public.png" as CFString, 1, nil) else {
            print("destination PNG a échoué")
            exit(1)
        }
        CGImageDestinationAddImage(dest, compImg, nil)
        CGImageDestinationFinalize(dest)
        print("wrote \(outPath) (t=\(time)s)")
    }

    static func main() {
        let args = CommandLine.arguments
        guard args.count >= 3 else {
            print("usage: render <scene> <out.png> [width] [time]")
            exit(1)
        }
        let sceneName = args[1]
        let outPath = args[2]
        let width = args.count > 3 ? Int(args[3]) ?? 480 : 480
        let time = args.count > 4 ? Double(args[4]) ?? 0.4 : 0.4
        // Traffic (spawn timing, fleet picks, positions/speeds) all draws
        // from FlightCoordinator.shared.rng (see FlightCoordinator.swift) --
        // pinning it here before any scene exists makes "same command, same
        // seed" produce a byte-identical PNG; a different seed still
        // exercises real randomness, just reproducibly.
        let seed = args.count > 5 ? UInt64(args[5]) ?? 42 : 42
        FlightCoordinator.reseed(seed)

        if sceneName == "handoff" {
            renderHandoff(outPath: outPath, width: width, time: time)
            return
        }
        if sceneName == "vertical-handoff" {
            renderVerticalHandoff(outPath: outPath, width: width, time: time)
            return
        }

        let scene: PixelScene
        switch sceneName {
        case "airport":
            let airport = AirportScene(canvasWidth: width)
            // Traffic is randomized by design; force a deterministic landing
            // at t=0 so sequence renders (motion verification) are
            // reproducible. Never called by the real screensaver.
            airport.queueApproach()
            scene = airport
        case "takeoff":
            let airport = AirportScene(canvasWidth: width)
            // Same idea as "airport" above, but forces a deterministic
            // departure instead of an arrival (queueApproach only forces
            // landings) -- reuses the forceTakeoff() debug hook already
            // wired up for the "handoff" composite below.
            airport.forceTakeoff()
            scene = airport
        case "goaround":
            // Deterministic go-around contract: a takeoff claims the
            // runway (ground) at t=0 and holds it for ~19s of taxi/lineup/
            // roll plus its climb; an arrival forced at the very same
            // instant reaches its own commit point (~0.72*canvasWidth,
            // around t=6s at the default approach speed/entry) while the
            // takeoff is still on the ground -- guaranteed to go around
            // instead of waiting invisibly. No coordinator wired, so this
            // exercises AirportScene's own single-screen retry
            // (pendingRetries), not a cross-screen relay -- see "handoff"
            // for that side of it.
            let airport = AirportScene(canvasWidth: width, localTraffic: false)
            airport.forceTakeoff()
            airport.queueApproach()
            scene = airport
        case "sky":
            let sky = SkyScene(screenIndex: 1, canvasWidth: width)
            // Ambient spawns are randomly timed (and off entirely once a
            // FlightCoordinator with sky slots exists); seed two planes
            // directly so this render is never just empty sky: one level
            // crossing, one visibly descending (tilt + landing light).
            sky.spawn(fromLeft: true, y: 55, speed: 40, vy: 0, landing: false, variant: .random())
            sky.spawn(fromLeft: false, y: 110, speed: 35, vy: 5, landing: true, variant: .random())
            scene = sky
        default:
            print("scène inconnue: \(sceneName)")
            exit(1)
        }

        let canvas = PixelCanvas(width: width)
        var t = 0.0
        while t < time {
            scene.update(dt: 1.0 / 30.0)
            t += 1.0 / 30.0
        }
        canvas.clear()
        scene.draw(on: canvas)

        guard let img = canvas.image() else {
            print("makeImage a échoué")
            exit(1)
        }
        let scale = 2
        guard let big = CGContext(
            data: nil, width: canvas.width * scale, height: canvas.height * scale,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            print("context upscale a échoué")
            exit(1)
        }
        big.interpolationQuality = .none
        big.draw(img, in: CGRect(x: 0, y: 0, width: canvas.width * scale, height: canvas.height * scale))
        guard let out = big.makeImage() else {
            print("upscale makeImage a échoué")
            exit(1)
        }

        let url = URL(fileURLWithPath: outPath) as CFURL
        guard let dest = CGImageDestinationCreateWithURL(url, "public.png" as CFString, 1, nil) else {
            print("destination PNG a échoué")
            exit(1)
        }
        CGImageDestinationAddImage(dest, out, nil)
        CGImageDestinationFinalize(dest)
        print("wrote \(outPath)")
    }
}
