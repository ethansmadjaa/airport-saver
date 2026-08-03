//
//  PixelCanvas.swift
//  airport-saver
//
//  Buffer pixel logique (hauteur 270, largeur par écran), coordonnées y
//  vers le bas, upscalé en nearest-neighbor par la vue.
//

import AppKit

final class PixelCanvas {
    /// Hauteur logique fixe — les scènes et la vue s'y réfèrent.
    static let logicalHeight = 270

    let width: Int
    let height: Int

    let ctx: CGContext

    /// `height` defaults to `logicalHeight` (the real screensaver's fixed
    /// canvas height); callers that just need more vertical room for a
    /// debug/preview render can override it.
    init(width: Int, height: Int = PixelCanvas.logicalHeight) {
        self.width = width
        self.height = height
        ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        // (0,0) en haut à gauche, y vers le bas
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.setShouldAntialias(false)
        ctx.interpolationQuality = .none
    }

    func clear(_ rgb: UInt32 = 0x000000) {
        fill(0, 0, width, height, rgb)
    }

    func fill(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ rgb: UInt32) {
        ctx.setFillColor(Self.cgColor(rgb))
        ctx.fill(CGRect(x: x, y: y, width: w, height: h))
    }

    func pixel(_ x: Int, _ y: Int, _ rgb: UInt32) {
        fill(x, y, 1, 1, rgb)
    }

    func image() -> CGImage? {
        ctx.makeImage()
    }

    static func cgColor(_ rgb: UInt32) -> CGColor {
        CGColor(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
