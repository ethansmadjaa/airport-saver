//
//  Sprites.swift
//  airport-saver
//
//  Pixel art rasterisé depuis les références ASCII d'Ethan (planes/*.txt).
//  1 caractère = 1x2 px (aspect terminal). ' ' transparent, caractères
//  légers → dim, oO0@* → hi, le reste → main.
//  Crédits arts d'origine : Paul Tomblin (aéroport), Nathan Roberts (F-16),
//  Jon Hyatt (777) — via asciiart.website, adaptés.
//

import Foundation

enum Sprites {
    private static let dimChars: Set<Character> = [".", ",", "'", "`", "~", "-", "_", "=", "^", "\""]
    private static let hiChars: Set<Character> = ["o", "O", "0", "@", "*"]

    static func size(_ art: [String], scale: Int = 1) -> (w: Int, h: Int) {
        ((art.map { $0.count }.max() ?? 0) * scale, art.count * 2 * scale)
    }

    static func draw(_ art: [String], on c: PixelCanvas, x: Int, y: Int,
                     main: UInt32, dim: UInt32, hi: UInt32,
                     scale: Int = 1, mirrored: Bool = false) {
        let cols = art.map { $0.count }.max() ?? 0
        for (row, line) in art.enumerated() {
            for (col, ch) in line.enumerated() where ch != " " {
                let rgb = hiChars.contains(ch) ? hi : (dimChars.contains(ch) ? dim : main)
                let cx = mirrored ? (cols - 1 - col) : col
                c.fill(x + cx * scale, y + row * 2 * scale, scale, 2 * scale, rgb)
            }
        }
    }

    /// Nuage 1 (planen3 bas).
    static let cloud1: [String] = [
        #"  _  _"#,
        #" ( `   )_"#,
        #"(    )    `)"#,
        #"(_   (_ .  _) _)"#,
    ]

    /// Nuage 2 (planen3 bas).
    static let cloud2: [String] = [
        #"         _"#,
        #"        (  )"#,
        #" ( `  ) . )"#,
        #"(_, _(  ,_)_)"#,
    ]

    // MARK: - Hand-drawn paletted aircraft (classic technique: 1 char = 1 logical
    // px = 1 palette color). Shape is hand-authored (silhouette inspired by
    // planes/*.txt), palette is swappable per livery.

    static func drawPaletted(_ art: [String], palette: [Character: UInt32], on c: PixelCanvas,
                              x: Int, y: Int, scale: Int = 1, mirrored: Bool = false) {
        let cols = art.map { $0.count }.max() ?? 0
        for (row, line) in art.enumerated() {
            for (col, ch) in line.enumerated() {
                guard let rgb = palette[ch] else { continue }
                let cx = mirrored ? (cols - 1 - col) : col
                c.fill(x + cx * scale, y + row * scale, scale, scale, rgb)
            }
        }
    }

    static func palettedSize(_ art: [String], scale: Int = 1) -> (w: Int, h: Int) {
        ((art.map { $0.count }.max() ?? 0) * scale, art.count * scale)
    }

    // MARK: - Reference-extracted aircraft (Ethan's planes_pixel/*.svg + *.jpg).
    // Grids were sampled from the source raster art: a border-flood-fill removes
    // background-connected pixels first (this is what keeps the silhouette free
    // of a pale anti-aliasing halo -- background never gets diluted into cell
    // averages), then cells are area-averaged + greedy color-quantized, then an
    // edge-hardening pass snaps every cell touching transparency to either fully
    // transparent (if it reads paler than the outline) or the single outline
    // color (if it doesn't) so the boundary is a crisp 1px ring, not a soft
    // multi-tone ramp. See .superpowers/sdd/.../svg-planes-report.md for the
    // full pipeline. Each palette runs darkest-to-lightest (K = outline).

    /// White/orange airliner, 3/4 banked view, nose to lower-right. 92x34.
    static let airliner1Shape: [String] = [
        #".......K...................................................................................."#,
        #".KKKKKKHKK.................................................................................."#,
        #".KKSFFBBKK.................................................................................."#,
        #".KKBGGGGKS.................................................................................."#,
        #"..KFGGGGFSK................................................................................."#,
        #"..KFGGGGGFsKK..............................................................................."#,
        #"..KSGGGGGGBsHK..........................................................KKKKKKK..K.........."#,
        #"..KSFGGGGGGGsSK..................................................KKKKKKKKKWHsFWKKKKK........"#,
        #"...KKBGGGGGGGFWK.........................................KKKKKKKKKKHSFFBBGGGGGsFFFKWK......."#,
        #"....KFGGGGGGGGFWKK.....................KKKKKKK.KKKKKKKKKKKKWSsFFBGGGGGGbBBGGGGBFBBFKKKKK...."#,
        #"....KFGGGGGGGGGFWWK................KKKKKKWWWKKKKKKKWHsFFBbGGGGGGGGGGGbKKKSGGGGsKfFFFWKKSK..."#,
        #"....KSsGGGGGGGGGBsSKK.KK.......KKKKWKKKWWWHSsFFBBbGGGGGGGGGGGGGGGBBGGGWFFWGGGGFsBBBbbGbHWKK."#,
        #".....KKbGGGGGGGGGGBFFKKSKKKKKKKKKWHsFFBbGGGGGGGGGGGGGGGbBGBFBBWsGHKGGGSsBKbGGGGGGGGGGGGGsHHK"#,
        #".....KKFBGGGGGGbBBFsSKKKKKHSFFBbGGGGGGGGGGGGGGGGbBbbsFGHKGFKFbWsGFFGGGsSBKBGGGGGGGGGGGGfffWH"#,
        #".......KsBFFsHWKKKWHsFFBbGGGGGGGGGGGGGGGGbFBGsHGFKFbKSGFsbbBbGGGGGGGGGFWFKFGGGGGGGGGGBffffHK"#,
        #".....KKKKKWHSsFBBbbGGGGGGGGGGGGGbbGFsGFWFbKSGsWbBFBGBbBFFsFGGGGGGGGGGGFKWSFGGGGGGbbBBfffHKK."#,
        #"....KSFFBbbBFFsSWKsGGGGGGBBGBSBbKSGSKbBHFGFBGbBBFFSHWKKKWWHGGGGGGGGGGGGGGGbBBBBffffffffSWK.."#,
        #"...KWWFSHWKKKWSsFSSGGGGGGSKbFKFGSFGBBGGGBFsHWKKKWSsFSffffSHGGGGGGGbBBBBffffffffffSSHHWKK...."#,
        #"..KKKWHsFFBbbBBFsHHGGGGGGFFbbbGGGGGGGGGbFHsFFBBGGGbBffHWWHbbBBBffffffffffSSHHWKKKKKKKKKK...."#,
        #"KKFbbBBFFsHWKKKWHHSbBBGGGGGGGGGGGGGGGGFKKBGGGGGGBffffSHSSfffffffffSHHWKKKKKKKKKK............"#,
        #".KWWKKKKKHKKSffffffffBBBBGGGGGbGGGGGBsHFbGGGGGBBfffKKWSfffSSHWWKKKKKKKKKK..................."#,
        #".KKKKK...KKKSHHSfffffffffBBBfffGbBBBsWsBGGGGGbfffHWKHHWKKKKKKKKKK..........................."#,
        #"............KKKSHWKKSfSSfffffffffffHHFGGGGGfffSSHWHSWSHHK..................................."#,
        #"...............KKK..KKKKHHWWKSffSHKHGGGGBBfffHKHsGGGHFFK...................................."#,
        #"........................KKKKKWKKKKFGGGbBfffWKKKGGGGGssFK...................................."#,
        #".............................KSsWFBGGbfffSHKHfKBGGGbsHFK...................................."#,
        #"..............................KKsGGBBfffWKKWSfKfBfffSKfKK..................................."#,
        #".............................KKBGbbBffWKK..KKKKSffSSHKKKK..................................."#,
        #"............................KWFbGBffSSHKK..KKKHKKKKKKKKKK..................................."#,
        #"..........................KKHsBBBffSKKK.......KKK..........................................."#,
        #"..........................KKWBBBfWWK........................................................"#,
        #".........................KFBfffSHSKKK......................................................."#,
        #".........................KHHKKKKK..........................................................."#,
        #".........................KHHsHF............................................................."#,
    ]
    static let airliner1Palette: [Character: UInt32] = [
        "B": 0xD1B2AE, "F": 0x8C858A, "H": 0x3D333E, "K": 0x0E0E1F, "S": 0x5F484D,
        "G": 0xFBE6E0, "s": 0x625E67, "W": 0x24202F, "b": 0xE6D1CD, "f": 0xEA6C54,
    ]

    /// Blue/gray airliner, 3/4 banked view, nose to lower-right. 95x41.
    static let airliner2Shape: [String] = [
        #"...KKKKKKKKK..................................................................................."#,
        #"...KKKKKKKKK..................................................................................."#,
        #"...KKHSFfffHKK................................................................................."#,
        #"...KKHFFGGGHKKK................................................................................"#,
        #"...KKHSFFGGGfKK................................................................................"#,
        #"...KKHSSFFGGGWKK..............................................................................."#,
        #".....KKSFFFGGGHKK.............................................................................."#,
        #".....KKSSFFFGGGWKK............................................................................."#,
        #".....KKSSFFFFGGsKWKK..........................................................................."#,
        #".....KKSSSFFFFGGGWKK..........................................................................."#,
        #".....KKSSSSFFFFGGHKWK.........................................................................."#,
        #".....KKSSSSFFFFbGGGKK.............KKKKKKKKKKK.................................................."#,
        #".....KKHHSSSFFFFGGGWKKKK..........KKKKKKKKKKH.................................................."#,
        #".......KKSSSFFFFFGGGfKKK..........KWKsffBBBBWKKKK.............................................."#,
        #".......KKSSSSFFFFFGGGssWKKKKKKKKKKKWKKHHHHHHHHWKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKK........"#,
        #".......KKSSSSSFFFFbGGGGWKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKK........"#,
        #"......KKKSFFFFFFFFFbGGGfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffsKKKK......"#,
        #".....KKKWbbbbFFFFFFFbGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGsKK......"#,
        #"..KKKWKHFbbbbbFFFFFFFFbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbHssFbbbssGfKWKK...."#,
        #"..KKKKKHHHHHHHHHHFFFFFHKKHbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbHHWFbbFWHGfWKKK...."#,
        #"KKKWWKKWWWWWWWWWWSSFFFSSSFFHHFFHHFFHHFFHHFFHHFFHHFFHFFFFHFFHHFFHHFFHHFFHHFFFFFbbbbbHHffHHWKKK.."#,
        #"KKfffffBGGGGGGGGGHKFFFFFFFFWKFFKWFFKWFFKHFFKHFSKSFSKSFFSKSFHKFFHKFFWKFFWKFFFFFFbbbbbbbbbGGGWKK."#,
        #"KKWWWWWWWWWWWWWWWKKSSSSSSSSHHSSHHSSHHSSHSSSHSSSHSSSHSSSSHSSSHSSSHSSHHSSHHSSSSSSSFFbbbbbbbbGfsWK"#,
        #"..KKKKKKKKWWWWWWWWHFFSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSFFbbbbbbbGGKW"#,
        #"..KKKKKKKHWWssssssffffsHHsffffffffffffffffffsHHHHHHHHHHHHHHHHHHHffffffffffffHHHffffffBBBBBBBfKH"#,
        #".........KKKfsssssffBBHWWsBBBBBBBBBBBBBBBBBBHKKKKKKKKKKKKKKKKKKKWBBBBBBBBBBBHWWfBBBBBBBBBBffsKW"#,
        #"...........KKKKKWssssfffBBBBBBBBBBBBBBBBBfWWWffffBGGGGGGGGBBffsWKBBBBBBBBBBBBBBBBBBBBBBBBfsHKKK"#,
        #"...........KKKKKKHssssssffBBBBBBBBBBBBBff.KKfBBBGGGGGGGGGBffHKKKfBBBBBBBBBBBBBBBBBBBBBBfsssWKK."#,
        #"................KKKKKKHsssssssssssssssHKKWBBBBGGGGGGGGGBBsKKWHssssssssssssssssssssssssssHKKKK.."#,
        #"................KKKKKKHsssssssssssssssHWWHBBGGGGGGGGGBBsHKKHHsssssssssssssssssssssssssssHKKK..."#,
        #"......................KKKKKKKKKKKKKKKKHBBBBGGGGGGGBfsHKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKK......"#,
        #"......................KKKKKKKKKKKWKKWWHBBGGGGGGGBBsHHHGGGGsKKKKKKKKKKKKKKKKKKKKKKKKKKKKKK......"#,
        #"..................................KKfBBGGGGGGGBsHWWHGGGGGGsKK.................................."#,
        #"...............................KKKssBBGGGGGGHWWWfKWfBBBBBGHKK.................................."#,
        #"...............................KKKfBGGGGGBffWKKWGKWfffffffHKK.................................."#,
        #".............................KKHffGGGGGGsKKKH..KKKHsssssssHKK.................................."#,
        #"...........................KKWWHBGGGfsssHKKKK..KKKWHHHHHHHHKK.................................."#,
        #"...........................KKHfBBBBfKKKKK.........KKKKKKKKK...................................."#,
        #"...........................KWHHHHHHHKKKKK.........KKKKKKKKK...................................."#,
        #"...........................KKKKKKKKK..........................................................."#,
        #"...........................KHHHHHHHK..........................................................."#,
    ]
    static let airliner2Palette: [Character: UInt32] = [
        "H": 0x3B4F58, "W": 0x26292B, "K": 0x09090A, "S": 0x0570B0, "F": 0x12A9EA,
        "G": 0xBAF0F1, "s": 0x737879, "f": 0x82A2A5, "b": 0x52E1F9, "B": 0xB1B2B2,
    ]

    // MARK: - Structural family variants (grid surgery, not scaling)
    //
    // Derived from airliner1Shape / airliner2Shape by literal column and row
    // surgery on the character grid -- not resampled/upscaled -- so each
    // variant differs in real fuselage length or deck configuration, like a
    // real aircraft family:
    //  - shortShape:      airliner1Shape with an 8-column fuselage bay
    //                     (a window bay in the clean constant-section tube,
    //                     between the cockpit and the wing) cut out.
    //  - stretchedShape:  airliner2Shape with a 12-column fuselage bay
    //                     duplicated into that same kind of clean tube
    //                     section, plus two extra wing rows.
    // Both reuse the same K/S/F/B/H/G/s/W/b/f alphabet as the two base
    // shapes, so every palette below (and airliner1Palette/airliner2Palette)
    // renders correctly on all of them.

    /// Short regional variant of airliner1Shape (fuselage bay + windows removed). 84x34.
    static let shortShape: [String] = [
        #".......K............................................................................"#,
        #".KKKKKKHKK.........................................................................."#,
        #".KKSFFBBKK.........................................................................."#,
        #".KKBGGGGKS.........................................................................."#,
        #"..KFGGGGFSK........................................................................."#,
        #"..KFGGGGGFsKK......................................................................."#,
        #"..KSGGGGGGBsHK..................................................KKKKKKK..K.........."#,
        #"..KSFGGGGGGGsSK.................................................KKWHsFWKKKKK........"#,
        #"...KKBGGGGGGGFWK.........................................KKKKKKKBGGGGGsFFFKWK......."#,
        #"....KFGGGGGGGGFWKK.....................KKKKKKK.KKKKKKKKKKKKWSsFFBBGGGGBFBBFKKKKK...."#,
        #"....KFGGGGGGGGGFWWK................KKKKKKWWWKKKKKKKWHsFFBbGGGGGGKSGGGGsKfFFFWKKSK..."#,
        #"....KSsGGGGGGGGGBsSKK.KK.......KKKKWKKKWWWHSsFFBBbGGGGGGGGGGGGGGFWGGGGFsBBBbbGbHWKK."#,
        #".....KKbGGGGGGGGGGBFFKKSKKKKKKKKKWHsFFBbGGGGGGGGGGGGGGGbBGBFBBWsBKbGGGGGGGGGGGGGsHHK"#,
        #".....KKFBGGGGGGbBBFsSKKKKKHSFFBbGGGGGGGGGGGGGGGGbBbbsFGHKGFKFbWsBKBGGGGGGGGGGGGfffWH"#,
        #".......KsBFFsHWKKKWHsFFBbGGGGGGGGGGGGGGGGbFBGsHGFKFbKSGFsbbBbGGGFKFGGGGGGGGGGBffffHK"#,
        #".....KKKKKWHSsFBBbbGGGGGGGGGGGGGbbGFsGFWFbKSGsWbBFBGBbBFFsFGGGGGWSFGGGGGGbbBBfffHKK."#,
        #"....KSFFBbbBFFsSWKsGGGGGGBBGBSBbKSGSKbBHFGFBGbBBFFSHWKKKWWHGGGGGGGbBBBBffffffffSWK.."#,
        #"...KWWFSHWKKKWSsFSSGGGGGGSKbFKFGSFGBBGGGBFsHWKKKWSsFSffffSHGGGGGfffffffffSSHHWKK...."#,
        #"..KKKWHsFFBbbBBFsHHGGGGGGFFbbbGGGGGGGGGbFHsFFBBGGGbBffHWWHbbBBBffSSHHWKKKKKKKKKK...."#,
        #"KKFbbBBFFsHWKKKWHHSbBBGGGGGGGGGGGGGGGGFKKBGGGGGGBffffSHSSfffffffKKKKKKKK............"#,
        #".KWWKKKKKHKKSffffffffBBBBGGGGGbGGGGGBsHFbGGGGGBBfffKKWSfffSSHWWKK..................."#,
        #".KKKKK...KKKSHHSfffffffffBBBfffGbBBBsWsBGGGGGbfffHWKHHWKKKKKKKKK...................."#,
        #"............KKKSHWKKSfSSfffffffffffHHFGGGGGfffSSHWHSWSHHK..........................."#,
        #"...............KKK..KKKKHHWWKSffSHKHGGGGBBfffHKHsGGGHFFK............................"#,
        #"........................KKKKKWKKKKFGGGbBfffWKKKGGGGGssFK............................"#,
        #".............................KSsWFBGGbfffSHKHfKBGGGbsHFK............................"#,
        #"..............................KKsGGBBfffWKKWSfKfBfffSKfKK..........................."#,
        #".............................KKBGbbBffWKK..KKKKSffSSHKKKK..........................."#,
        #"............................KWFbGBffSSHKK..KKKHKKKKKKKKKK..........................."#,
        #"..........................KKHsBBBffSKKK.......KKK..................................."#,
        #"..........................KKWBBBfWWK................................................"#,
        #".........................KFBfffSHSKKK..............................................."#,
        #".........................KHHKKKKK..................................................."#,
        #".........................KHHsHF....................................................."#,
    ]

    /// Stretched long-haul variant of airliner2Shape (fuselage bay + windows inserted, wing slightly enlarged). 107x42.
    static let stretchedShape: [String] = [
        #"...KKKKKKKKK..............................................................................................."#,
        #"...KKKKKKKKK..............................................................................................."#,
        #"...KKHSFfffHKK............................................................................................."#,
        #"...KKHFFGGGHKKK............................................................................................"#,
        #"...KKHSFFGGGfKK............................................................................................"#,
        #"...KKHSSFFGGGWKK..........................................................................................."#,
        #".....KKSFFFGGGHKK.........................................................................................."#,
        #".....KKSSFFFGGGWKK........................................................................................."#,
        #".....KKSSFFFFGGsKWKK......................................................................................."#,
        #".....KKSSSFFFFGGGWKK......................................................................................."#,
        #".....KKSSSSFFFFGGHKWK......................................................................................"#,
        #".....KKSSSSFFFFbGGGKK.............KKKKKKKKKKK.............................................................."#,
        #".....KKHHSSSFFFFGGGWKKKK..........KKKKKKKKKKH.............................................................."#,
        #".......KKSSSFFFFFGGGfKKK..........KWKsffBBBBWKKKK.........................................................."#,
        #".......KKSSSSFFFFFGGGssWKKKKKKKKKKKWKKHHHHHHHHWKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKK........"#,
        #".......KKSSSSSFFFFbGGGGWKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKK......"#,
        #"......KKKSFFFFFFFFFbGGGfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffsKKKK...."#,
        #".....KKKWbbbbFFFFFFFbGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGsKK......"#,
        #"..KKKWKHFbbbbbFFFFFFFFbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbHbbbbbbbbbbbHssFbbbssGfKWKK...."#,
        #"..KKKKKHHHHHHHHHHFFFFFHKKHbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbHbbbbbbbbbbbHHWFbbFWHGfWKKK...."#,
        #"KKKWWKKWWWWWWWWWWSSFFFSSSFFHHFFHHFFHHFFHHFFHHFFHHFFHFFFFHFFHHFFHHFFHHFFHHFFFFFFHHFFHHFFFFFbbbbbHHffHHWKKK.."#,
        #"KKfffffBGGGGGGGGGHKFFFFFFFFWKFFKWFFKWFFKHFFKHFSKSFSKSFFSKSFHKFFHKFFWKFFWKFFFFFFWKFFWKFFFFFFbbbbbbbbbGGGWKK."#,
        #"KKWWWWWWWWWWWWWWWKKSSSSSSSSHHSSHHSSHHSSHSSSHSSSHSSSHSSSSHSSSHSSSHSSHHSSHHSSSSSSHHSSHHSSSSSSSFFbbbbbbbbGfsWK"#,
        #"..KKKKKKKKWWWWWWWWHFFSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSFFbbbbbbbGGKW."#,
        #"..KKKKKKKHWWssssssffffsHHsffffffffffffffffffsHHHHHHHHHHHHHHHHHHHffffffffffffHfffffffffffHHHffffffBBBBBBBfKH"#,
        #".........KKKfsssssffBBHWWsBBBBBBBBBBBBBBBBBBHKKKKKKKKKKKKKKKKKKKWBBBBBBBBBBBHBBBBBBBBBBBHWWfBBBBBBBBBBffsKW"#,
        #"...........KKKKKWssssfffBBBBBBBBBBBBBBBBBfWWWffffBGGGGGGGGBBffsWKBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBfsHKKK"#,
        #"...........KKKKKKHssssssffBBBBBBBBBBBBBff.KKfBBBGGGGGGGGGBffHKKKfBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBfsssWKK."#,
        #"................KKKKKKHsssssssssssssssHKKWBBBBGGGGGGGGGBBsKKWHssssssssssssssssssssssssssssssssssssssHKKKK.."#,
        #"................KKKKKKHsssssssssssssssHWWHBBGGGGGGGGGBBsHKKHHsssssssssssssssssssssssssssssssssssssssHKKK..."#,
        #"......................KKKKKKKKKKKKKKKKHBBBBGGGGGGGBfsHKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKK......"#,
        #"......................KKKKKKKKKKKWKKWWHBBGGGGGGGBBsHHHGGGGsKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKK......"#,
        #"..................................KKfBBGGGGGGGBsHWWHGGGGGGsKK.............................................."#,
        #"...............................KKKssBBGGGGGGHWWWfKWfBBBBBGHKK.............................................."#,
        #"...............................KKKfBGGGGGBffWKKWGKWfffffffHKK.............................................."#,
        #"...............................KKKfBGGGGGBffWKKWGKWfffffffHKK.............................................."#,
        #".............................KKHffGGGGGGsKKKH..KKKHsssssssHKK.............................................."#,
        #"...........................KKWWHBGGGfsssHKKKK..KKKWHHHHHHHHKK.............................................."#,
        #"...........................KKHfBBBBfKKKKK.........KKKKKKKKK................................................"#,
        #"...........................KWHHHHHHHKKKKK.........KKKKKKKKK................................................"#,
        #"...........................KKKKKKKKK......................................................................."#,
        #"...........................KHHHHHHHK......................................................................."#,
    ]

    // MARK: - Liveries
    //
    // Palettes are cheap: same 10-key alphabet (K/S/F/B/H/G/s/W/b/f), new
    // colors. K is always the darkest (outline), G the lightest (fuselage
    // main) so any palette drops onto any shape above -- fuselage stays
    // white/light, only the accent/stripe/tail hues change. All tuned to
    // stay readable against the night sky in AirportScene.

    /// Teal / cyan livery.
    static let tealPalette: [Character: UInt32] = [
        "K": 0x0A1416, "W": 0x122A2C, "H": 0x1E4B4D, "S": 0x0E7A7A, "s": 0x4C8C8C,
        "F": 0x179E9E, "B": 0xAFDCD6, "b": 0xD3ECE7, "G": 0xF2FBF9, "f": 0x2FC2B4,
    ]

    /// Crimson / red livery.
    static let crimsonPalette: [Character: UInt32] = [
        "K": 0x1A0808, "W": 0x2A1010, "H": 0x531515, "S": 0x8C1F1F, "s": 0x9C5B5B,
        "F": 0xC22A2A, "B": 0xE9B9B4, "b": 0xF2D6D2, "G": 0xFBEEEA, "f": 0xE8622F,
    ]

    /// Forest green livery.
    static let forestPalette: [Character: UInt32] = [
        "K": 0x0C1509, "W": 0x1A2B12, "H": 0x2E4A1E, "S": 0x3E6B22, "s": 0x7C9A6B,
        "F": 0x4F8A2A, "B": 0xC9DAB6, "b": 0xE1EBD3, "G": 0xF5FAEF, "f": 0xE0A72E,
    ]

    /// Violet livery.
    static let violetPalette: [Character: UInt32] = [
        "K": 0x140A1E, "W": 0x241237, "H": 0x442064, "S": 0x6B2E96, "s": 0x9C7CB0,
        "F": 0x8E44C4, "B": 0xD8C2E8, "b": 0xE9DDF2, "G": 0xFAF6FC, "f": 0xE2578F,
    ]

    // MARK: - Rotation (climb / descend tilt)

    /// Rotates a character grid by `degrees` around its own center, nearest-
    /// neighbor, transparent (".") fill outside the source. Positive degrees
    /// pitch the nose up (climb), negative pitch it down (descend) -- meant
    /// for small angles (+-8, +-15) so a parked/level shape can be shown
    /// climbing or descending without hand-drawing a new grid.
    ///
    /// Rotation of a hard-edged silhouette leaves stray single pixels that
    /// break the 1px outline; after sampling, any painted pixel with no
    /// orthogonal painted neighbor is dropped (a despeckle pass) so the
    /// result reads as clean as the source.
    static func rotated(_ grid: [String], degrees: Int) -> [String] {
        let rows = grid.count
        let cols = grid.map { $0.count }.max() ?? 0
        guard rows > 0, cols > 0, degrees != 0 else { return grid }

        var src = grid.map { Array($0) }
        for i in 0..<src.count where src[i].count < cols {
            src[i] += Array(repeating: Character("."), count: cols - src[i].count)
        }

        let theta = -Double(degrees) * .pi / 180
        let cosT = cos(theta), sinT = sin(theta)
        let cx = Double(cols) / 2, cy = Double(rows) / 2

        // Expand the canvas so the rotated silhouette never clips a corner.
        let corners = [(0.0, 0.0), (Double(cols), 0.0), (0.0, Double(rows)), (Double(cols), Double(rows))]
        let maxR = corners.reduce(0.0) { acc, p in
            let dx = p.0 - cx, dy = p.1 - cy
            return max(acc, (dx * dx + dy * dy).squareRoot())
        }
        let outSize = max(1, Int(ceil(maxR * 2)))
        let ocx = Double(outSize) / 2, ocy = Double(outSize) / 2

        var out = Array(repeating: Array(repeating: Character("."), count: outSize), count: outSize)
        for oy in 0..<outSize {
            for ox in 0..<outSize {
                let dx = Double(ox) + 0.5 - ocx
                let dy = Double(oy) + 0.5 - ocy
                let sx = dx * cosT + dy * sinT + cx
                let sy = -dx * sinT + dy * cosT + cy
                let ix = Int(sx.rounded(.down))
                let iy = Int(sy.rounded(.down))
                if ix >= 0, ix < cols, iy >= 0, iy < rows {
                    out[oy][ox] = src[iy][ix]
                }
            }
        }

        // Despeckle: drop painted pixels with no orthogonal painted neighbor.
        var cleaned = out
        for y in 0..<outSize {
            for x in 0..<outSize where out[y][x] != "." {
                let hasNeighbor = [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)].contains { nx, ny in
                    nx >= 0 && nx < outSize && ny >= 0 && ny < outSize && out[ny][nx] != "."
                }
                if !hasNeighbor { cleaned[y][x] = "." }
            }
        }
        return cleaned.map { String($0) }
    }
}

/// One fleet "type" a scene can spawn: a hull shape paired with a livery
/// palette. Runway traffic (AirportScene) picks a random one per flight;
/// exposed at the top level (not nested in Sprites) so a future sky scene
/// can accept the same value from `onDepartureExit` without depending on
/// AirportScene.
struct FleetVariant {
    let shape: [String]
    let palette: [Character: UInt32]

    private static let shapes: [[String]] = [
        Sprites.airliner1Shape, Sprites.airliner2Shape, Sprites.shortShape, Sprites.stretchedShape,
    ]
    private static let liveries: [[Character: UInt32]] = [
        Sprites.airliner1Palette, Sprites.airliner2Palette, Sprites.tealPalette,
        Sprites.crimsonPalette, Sprites.forestPalette, Sprites.violetPalette,
    ]

    static func random(using rng: inout SplitMix64) -> FleetVariant {
        FleetVariant(shape: shapes.randomElement(using: &rng)!, palette: liveries.randomElement(using: &rng)!)
    }

    /// No-arg convenience so call sites (AirportScene/SkyScene/render
    /// checks) stay tidy -- draws from the single shared, seedable RNG
    /// (see FlightCoordinator.rng).
    static func random() -> FleetVariant {
        random(using: &FlightCoordinator.shared.rng)
    }
}

/// Seedable PRNG (splitmix64) -- the sole source of traffic randomness
/// (spawn timing, fleet picks, positions, speeds) across every scene, so a
/// render can be reproduced bit-for-bit by reseeding
/// `FlightCoordinator.shared.rng` (see `FlightCoordinator.reseed(_:)`)
/// instead of relying on stdlib's non-seedable `Bool`/`*.random(in:)`.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
