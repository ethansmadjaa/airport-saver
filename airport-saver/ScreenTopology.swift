//
//  ScreenTopology.swift
//  airport-saver
//
//  Logique pure (pas d'AppKit) : modèle d'adjacence 2D à partir des frames
//  globaux des écrans -- chaque écran connaît son voisin gauche/droite/
//  dessus/dessous par contact d'arête réel (pas un simple tri par minX).
//  La chaîne horizontale principale (gauche→droite, pour l'API de slots
//  historique) est la suite d'écrans atteignables depuis l'écran principal
//  en suivant uniquement les voisins gauche/droite ; un écran empilé au-
//  dessus/dessous sans voisin horizontal n'en fait pas partie et ne reçoit
//  pas de faux slot. Vérifiée par checks/topology_check.swift.
//

import CoreGraphics

struct ScreenTopology {
    enum Direction { case left, right, above, below }

    // Tolérance pour qu'un contact d'arête compte comme une adjacence
    // (bezels/gaps réels sont de quelques px), et fraction minimale de
    // recouvrement sur la dimension partagée pour écarter un simple
    // contact de coin (écrans en diagonale) ou une coïncidence de
    // coordonnée sans vrai recouvrement.
    private static let edgeTolerance: CGFloat = 4
    private static let minOverlapFraction: CGFloat = 0.2

    private let frames: [CGRect]

    /// Un voisin par écran et par direction, calculé une fois à l'init à
    /// partir des frames bruts -- tout le routing (marche de la chaîne,
    /// relais vertical) lit ces tables plutôt que de re-dériver l'adjacence
    /// d'un tri minX/minY à chaque appel.
    private let leftNeighbor: [Int?]
    private let rightNeighbor: [Int?]
    private let aboveNeighbor: [Int?]
    private let belowNeighbor: [Int?]

    /// slotForScreen[i] = position de NSScreen.screens[i] dans la chaîne
    /// horizontale principale (gauche→droite), ou nil si l'écran i n'est
    /// pas atteignable depuis l'écran principal (index 0) via l'adjacence
    /// gauche/droite -- p.ex. un écran empilé au-dessus/dessous sans voisin
    /// horizontal propre.
    let slotForScreen: [Int?]
    /// screenForSlot[s] = index écran occupant le slot s de la chaîne
    /// (membres de la chaîne uniquement, gauche→droite).
    let screenForSlot: [Int]
    /// logicalWidths[i] = largeur logique de l'écran i (hauteur fixe 270) --
    /// tous les écrans, membres de la chaîne ou non (nécessaire pour
    /// dimensionner n'importe quel SkyScene).
    let logicalWidths: [Int]

    var slotCount: Int { screenForSlot.count }
    /// Slot de l'écran principal (NSScreen.screens[0]) dans sa propre chaîne.
    var mainSlot: Int {
        guard frames.indices.contains(0) else { return 0 }
        return slotForScreen[0] ?? 0
    }

    static func logicalWidth(for frame: CGRect) -> Int {
        guard frame.height > 0 else { return 480 }
        return max(160, Int((270 * frame.width / frame.height).rounded()))
    }

    /// Somme des largeurs logiques des slots strictement à gauche du slot s
    /// (chaîne principale uniquement).
    func offsetForSlot(_ s: Int) -> Int {
        screenForSlot.prefix(s).reduce(0) { $0 + logicalWidths[$1] }
    }

    /// Largeur logique totale du monde (chaîne principale uniquement -- un
    /// écran empilé au-dessus/dessous n'élargit pas la rangée horizontale).
    var worldWidth: Int { screenForSlot.reduce(0) { $0 + logicalWidths[$1] } }

    /// L'unique écran physique adjacent à `screen` dans `direction`, ou nil
    /// en bout d'arrangement -- c'est l'adjacence 2D réelle que ce type
    /// existe pour modéliser (arêtes qui se touchent à quelques px près,
    /// avec assez de recouvrement partagé pour écarter un contact de coin).
    func neighbor(of screen: Int, _ direction: Direction) -> Int? {
        guard frames.indices.contains(screen) else { return nil }
        switch direction {
        case .left: return leftNeighbor[screen]
        case .right: return rightNeighbor[screen]
        case .above: return aboveNeighbor[screen]
        case .below: return belowNeighbor[screen]
        }
    }

    /// Frame physique de `screen` (tel que passé à l'init) -- utilisé pour
    /// projeter la position x d'un avion qui grimpe à travers un bezel
    /// vertical partagé sur un voisin de largeur/ratio différent.
    func frame(of screen: Int) -> CGRect? {
        frames.indices.contains(screen) ? frames[screen] : nil
    }

    init(frames: [CGRect]) {
        self.frames = frames
        logicalWidths = frames.map(Self.logicalWidth(for:))

        func overlap(_ a: ClosedRange<CGFloat>, _ b: ClosedRange<CGFloat>) -> CGFloat {
            max(0, min(a.upperBound, b.upperBound) - max(a.lowerBound, b.lowerBound))
        }
        func vOverlapFraction(_ a: CGRect, _ b: CGRect) -> CGFloat {
            let shorter = min(a.height, b.height)
            guard shorter > 0 else { return 0 }
            return overlap(a.minY...a.maxY, b.minY...b.maxY) / shorter
        }
        func hOverlapFraction(_ a: CGRect, _ b: CGRect) -> CGFloat {
            let shorter = min(a.width, b.width)
            guard shorter > 0 else { return 0 }
            return overlap(a.minX...a.maxX, b.minX...b.maxX) / shorter
        }
        func bestNeighbor(of i: Int, touches: (CGRect, CGRect) -> Bool,
                           overlapFraction: (CGRect, CGRect) -> CGFloat) -> Int? {
            var best: (index: Int, overlap: CGFloat)?
            for j in frames.indices where j != i {
                guard touches(frames[i], frames[j]) else { continue }
                let frac = overlapFraction(frames[i], frames[j])
                guard frac >= Self.minOverlapFraction else { continue }
                if best == nil || frac > best!.overlap { best = (j, frac) }
            }
            return best?.index
        }

        rightNeighbor = frames.indices.map { i in
            bestNeighbor(of: i,
                touches: { a, b in abs(b.minX - a.maxX) <= Self.edgeTolerance },
                overlapFraction: vOverlapFraction)
        }
        leftNeighbor = frames.indices.map { i in
            bestNeighbor(of: i,
                touches: { a, b in abs(b.maxX - a.minX) <= Self.edgeTolerance },
                overlapFraction: vOverlapFraction)
        }
        aboveNeighbor = frames.indices.map { i in
            bestNeighbor(of: i,
                touches: { a, b in abs(b.minY - a.maxY) <= Self.edgeTolerance },
                overlapFraction: hOverlapFraction)
        }
        belowNeighbor = frames.indices.map { i in
            bestNeighbor(of: i,
                touches: { a, b in abs(b.maxY - a.minY) <= Self.edgeTolerance },
                overlapFraction: hOverlapFraction)
        }

        // Chaîne principale : marche à gauche puis à droite depuis l'écran
        // principal (index 0) via l'adjacence réelle, jamais un tri minX --
        // un écran seulement atteignable verticalement ne rejoint jamais
        // cette chaîne et ne reçoit pas de slot horizontal.
        var chain: [Int] = []
        var slots = [Int?](repeating: nil, count: frames.count)
        if frames.indices.contains(0) {
            chain = [0]
            var visited: Set<Int> = [0]
            var cur = 0
            while let l = leftNeighbor[cur], !visited.contains(l) {
                chain.insert(l, at: 0)
                visited.insert(l)
                cur = l
            }
            cur = 0
            while let r = rightNeighbor[cur], !visited.contains(r) {
                chain.append(r)
                visited.insert(r)
                cur = r
            }
            for (slot, screen) in chain.enumerated() { slots[screen] = slot }
        }
        screenForSlot = chain
        slotForScreen = slots
    }
}
