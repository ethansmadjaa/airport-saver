//
//  AirportSaverView.swift
//  airport-saver
//

import AppKit
import ScreenSaver
import QuartzCore

@objc(airport_saverView)
class AirportSaverView: ScreenSaverView {

    private var canvas = PixelCanvas(width: 480) // valeur de départ, remplacée au moveToWindow
    private lazy var scene: PixelScene = makeScene()
    private var lastTime: CFTimeInterval = 0

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        animationTimeInterval = 1 / 30.0
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    /// Point unique de sélection de scène : preview -> aéroport autonome ;
    /// écran principal -> aéroport câblé au FlightCoordinator ; les autres
    /// écrans -> ciel, aussi câblé au coordinateur.
    private func makeScene() -> PixelScene {
        guard !isPreview else {
            return AirportScene(canvasWidth: canvas.width)
        }

        // window == nil (detach during display sleep/unplug) means the
        // screen this view belongs to can't be resolved; `?? 0` used to
        // silently claim to be the main screen here and register a dying
        // scene as the coordinator's airport, permanently nil-ing it out.
        // Bail to an unregistered standalone airport instead -- it won't
        // participate in cross-screen relay, but it won't break it either.
        guard let screen = window?.screen, let screenIndex = NSScreen.screens.firstIndex(of: screen) else {
            return AirportScene(canvasWidth: canvas.width)
        }

        let frames = NSScreen.screens.map(\.frame)
        FlightCoordinator.shared.configure(frames: frames)
        let topology = FlightCoordinator.shared.topology
        let slot = screenIndex < topology.slotForScreen.count ? topology.slotForScreen[screenIndex] : 0

        if screenIndex == 0 {
            let airport = AirportScene(canvasWidth: canvas.width, localTraffic: !FlightCoordinator.shared.hasSkySlots)
            airport.onDepartureExit = { altitude, speed, variant in
                FlightCoordinator.shared.departureExited(altitude: altitude, speed: speed, variant: variant)
            }
            airport.departureDirection = { FlightCoordinator.shared.startDeparture() }
            FlightCoordinator.shared.registerAirport(airport)
            return airport
        }

        let sky = SkyScene(slot: slot, canvasWidth: canvas.width)
        FlightCoordinator.shared.registerSky(sky)
        return sky
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let ratio = bounds.height > 0 ? bounds.width / bounds.height : 16.0 / 9.0
        canvas = PixelCanvas(width: max(160, Int((CGFloat(PixelCanvas.logicalHeight) * ratio).rounded())))
        scene = makeScene()
    }

    override func animateOneFrame() {
        let now = CACurrentMediaTime()
        let dt = lastTime == 0 ? 1 / 30.0 : min(now - lastTime, 0.1)
        lastTime = now
        scene.update(dt: dt)
        canvas.clear()
        scene.draw(on: canvas)
        needsDisplay = true
    }

    override func draw(_ rect: NSRect) {
        guard let g = NSGraphicsContext.current?.cgContext else { return }
        g.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        g.fill(bounds)
        guard let img = canvas.image() else { return }
        g.interpolationQuality = .none
        let scale = min(
            bounds.width / CGFloat(canvas.width),
            bounds.height / CGFloat(canvas.height)
        )
        let w = CGFloat(canvas.width) * scale
        let h = CGFloat(canvas.height) * scale
        g.draw(img, in: CGRect(
            x: (bounds.width - w) / 2,
            y: (bounds.height - h) / 2,
            width: w, height: h
        ))
    }

    override var hasConfigureSheet: Bool { false }
    override var configureSheet: NSWindow? { nil }
}
