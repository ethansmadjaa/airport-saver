//
//  PixelScene.swift
//  airport-saver
//

import Foundation

protocol PixelScene: AnyObject {
    func update(dt: TimeInterval)
    func draw(on c: PixelCanvas)
}
