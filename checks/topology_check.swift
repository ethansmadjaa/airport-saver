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

        // Écran unique.
        let single = ScreenTopology(frames: [CGRect(x: 0, y: 0, width: 1440, height: 900)])
        assert(single.slotCount == 1)
        assert(single.mainSlot == 0)

        // Aucun écran (défensif — ne doit pas crasher).
        let empty = ScreenTopology(frames: [])
        assert(empty.slotCount == 0)
        assert(empty.mainSlot == 0)

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

        print("topology_check OK")
    }
}
