// Check de ScreenTopology. Compiler et lancer :
//   swiftc -o /tmp/topology_check airport-saver/ScreenTopology.swift checks/topology_check.swift && /tmp/topology_check
import CoreGraphics

@main
struct TopologyCheck {
    static func main() {
        // Principal au centre, un écran à gauche, un à droite.
        let t = ScreenTopology(frames: [
            CGRect(x: 0, y: 0, width: 1920, height: 1080),
            CGRect(x: -1920, y: 0, width: 1920, height: 1080),
            CGRect(x: 1920, y: 0, width: 1920, height: 1080),
        ])
        assert(t.slotForScreen == [1, 0, 2], "principal doit être au slot 1")
        assert(t.screenForSlot == [1, 0, 2], "slots gauche→droite = écrans 1,0,2")
        assert(t.mainSlot == 1)
        assert(t.slotCount == 3)
        assert(t.neighbor(of: 0, .left) == 1, "voisin gauche du principal = écran 1")
        assert(t.neighbor(of: 0, .right) == 2, "voisin droit du principal = écran 2")
        assert(t.neighbor(of: 1, .right) == 0)
        assert(t.neighbor(of: 2, .left) == 0)
        assert(t.neighbor(of: 0, .above) == nil)
        assert(t.neighbor(of: 0, .below) == nil)

        // Écran unique.
        let single = ScreenTopology(frames: [CGRect(x: 0, y: 0, width: 1440, height: 900)])
        assert(single.slotCount == 1)
        assert(single.mainSlot == 0)
        assert(single.neighbor(of: 0, .left) == nil)
        assert(single.neighbor(of: 0, .right) == nil)

        // Aucun écran (défensif — ne doit pas crasher).
        let empty = ScreenTopology(frames: [])
        assert(empty.slotCount == 0)
        assert(empty.mainSlot == 0)
        assert(empty.neighbor(of: 0, .right) == nil)

        // Largeurs logiques : 1920x1080 → 480 ; ultra-large 3440x1440 → 645
        let wide = ScreenTopology(frames: [
            CGRect(x: 0, y: 0, width: 3440, height: 1440),   // principal ultra-large, à gauche
            CGRect(x: 3440, y: 0, width: 1920, height: 1080), // secondaire 16:9 à droite
        ])
        assert(wide.logicalWidths == [645, 480], "645 = round(270*3440/1440)")
        assert(wide.offsetForSlot(0) == 0)
        assert(wide.offsetForSlot(1) == 645, "offset du slot 1 = largeur du slot 0")
        assert(wide.worldWidth == 1125)
        assert(ScreenTopology.logicalWidth(for: CGRect(x: 0, y: 0, width: 1920, height: 1080)) == 480)

        // (a) Portable + écran directement AU-DESSUS : adjacence verticale
        // détectée, l'écran empilé ne reçoit aucun slot horizontal, et la
        // chaîne principale ne contient que le portable seul.
        let laptopPlusAbove = ScreenTopology(frames: [
            CGRect(x: 0, y: 0, width: 1440, height: 900),   // portable (principal)
            CGRect(x: 0, y: 900, width: 1440, height: 900), // écran externe empilé au-dessus
        ])
        assert(laptopPlusAbove.neighbor(of: 0, .above) == 1, "l'écran du dessus doit être détecté")
        assert(laptopPlusAbove.neighbor(of: 1, .below) == 0, "réciproque : le portable est en dessous")
        assert(laptopPlusAbove.neighbor(of: 0, .left) == nil)
        assert(laptopPlusAbove.neighbor(of: 0, .right) == nil)
        assert(laptopPlusAbove.slotForScreen[1] == nil, "l'écran empilé ne doit pas avoir de faux slot horizontal")
        assert(laptopPlusAbove.slotCount == 1, "la chaîne principale ne contient que le portable")
        assert(laptopPlusAbove.mainSlot == 0)

        // (b) Forme en L : principal à l'origine, un écran à droite, un
        // troisième au-dessus de celui de droite. La chaîne horizontale
        // s'arrête à [principal, droite] ; le troisième n'a pas de slot.
        let lShape = ScreenTopology(frames: [
            CGRect(x: 0, y: 0, width: 1920, height: 1080),      // principal
            CGRect(x: 1920, y: 0, width: 1920, height: 1080),   // à droite du principal
            CGRect(x: 1920, y: 1080, width: 1920, height: 1080), // au-dessus de l'écran de droite
        ])
        assert(lShape.screenForSlot == [0, 1], "chaîne = [principal, droite]")
        assert(lShape.slotCount == 2)
        assert(lShape.neighbor(of: 1, .above) == 2, "au-dessus de l'écran de droite = le troisième")
        assert(lShape.neighbor(of: 2, .below) == 1)
        assert(lShape.slotForScreen[2] == nil, "le troisième écran (empilé) n'a pas de slot horizontal")
        assert(lShape.neighbor(of: 0, .right) == 1, "pas de fausse adjacence droite vers l'écran 2 (pas de recouvrement vertical)")

        // (c) Tolérance : un écart de 2px doit quand même compter comme
        // adjacent (bezels/rapports d'arrangement réels ne sont jamais
        // pixel-parfaits).
        let tinyGap = ScreenTopology(frames: [
            CGRect(x: 0, y: 0, width: 1920, height: 1080),
            CGRect(x: 1922, y: 0, width: 1920, height: 1080), // 2px d'écart
        ])
        assert(tinyGap.neighbor(of: 0, .right) == 1, "un écart de 2px doit rester adjacent")
        assert(tinyGap.neighbor(of: 1, .left) == 0)
        assert(tinyGap.slotCount == 2)

        // (d) Contact en diagonale uniquement (coin à coin) : aucune
        // adjacence ne doit être détectée dans aucune direction, le
        // recouvrement partagé étant nul.
        let diagonalOnly = ScreenTopology(frames: [
            CGRect(x: 0, y: 0, width: 1920, height: 1080),
            CGRect(x: 1920, y: 1080, width: 1920, height: 1080), // touche seulement au coin (1920,1080)
        ])
        assert(diagonalOnly.neighbor(of: 0, .right) == nil, "contact en coin seul != adjacence droite")
        assert(diagonalOnly.neighbor(of: 0, .above) == nil, "contact en coin seul != adjacence au-dessus")
        assert(diagonalOnly.neighbor(of: 1, .left) == nil)
        assert(diagonalOnly.neighbor(of: 1, .below) == nil)
        assert(diagonalOnly.slotCount == 1, "sans adjacence réelle, l'écran 1 reste hors chaîne")

        print("topology_check OK")
    }
}
