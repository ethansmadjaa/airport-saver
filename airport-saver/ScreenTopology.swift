//
//  ScreenTopology.swift
//  airport-saver
//
//  Logique pure (pas d'AppKit) : ordonne les écrans gauche→droite
//  à partir de leurs frames globaux. Vérifiée par checks/topology_check.swift.
//

import CoreGraphics

struct ScreenTopology {
    /// slotForScreen[i] = slot (position gauche→droite) de NSScreen.screens[i]
    let slotForScreen: [Int]
    /// screenForSlot[s] = index écran occupant le slot s
    let screenForSlot: [Int]
    /// logicalWidths[i] = largeur logique de l'écran i (hauteur fixe 270)
    let logicalWidths: [Int]

    var slotCount: Int { screenForSlot.count }
    /// Slot de l'écran principal (NSScreen.screens[0]).
    var mainSlot: Int { slotForScreen.first ?? 0 }

    static func logicalWidth(for frame: CGRect) -> Int {
        guard frame.height > 0 else { return 480 }
        return max(160, Int((270 * frame.width / frame.height).rounded()))
    }

    /// Somme des largeurs logiques des slots strictement à gauche du slot s.
    func offsetForSlot(_ s: Int) -> Int {
        screenForSlot.prefix(s).reduce(0) { $0 + logicalWidths[$1] }
    }

    /// Largeur logique totale du monde (tous écrans).
    var worldWidth: Int { logicalWidths.reduce(0, +) }

    init(frames: [CGRect]) {
        let order = frames.indices.sorted { frames[$0].minX < frames[$1].minX }
        var slots = [Int](repeating: 0, count: frames.count)
        for (slot, screen) in order.enumerated() {
            slots[screen] = slot
        }
        slotForScreen = slots
        screenForSlot = order
        logicalWidths = frames.map(Self.logicalWidth(for:))
    }
}
