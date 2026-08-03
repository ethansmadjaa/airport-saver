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
// usage: render <scene> <out.png> [width=480] [time=0.4]
// scènes connues : airport (AirportScene), sky (SkyScene), handoff (two-screen
// composite -- see below).

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
        airport.departureDirection = { FlightCoordinator.shared.startDeparture() }
        FlightCoordinator.shared.registerAirport(airport)

        let sky = SkyScene(slot: 0, canvasWidth: width)
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

        if sceneName == "handoff" {
            renderHandoff(outPath: outPath, width: width, time: time)
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
        case "sky":
            let sky = SkyScene(slot: 1, canvasWidth: width)
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
