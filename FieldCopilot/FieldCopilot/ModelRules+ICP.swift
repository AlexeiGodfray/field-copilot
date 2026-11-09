import Foundation

// ICP (International Comfort Products, part of Carrier): Heil, Tempstar, Comfortmaker, Arcoaire,
// KeepRite, Day & Night, Airquest, Kenmore.
// Sources: ICP technical support manuals 421 04 1701 00 and 421 04 1801 00 (2012) for the brand
// letters, R4A4 spec sheet 421 65 6240 06 (2017), ICP's 2024 nomenclature, ENERGY STAR listings
// (the brands each letter is sold under, and the B, Q and W letters of the SEER2 line), DOE's certification
// database (G97 furnaces sold as Tempstar).

extension ModelLookup {
    static let icpBrands = ["Heil", "Tempstar", "Comfortmaker", "Arcoaire", "KeepRite", "Day & Night", "Airquest", "Kenmore",
                            "Smart Comfort", "Maratherm"]

    /// Outdoor units: the first letter is a brand group. N, R, B and Q are sold under every brand.
    private static func icpOutdoorBrands(_ letter: String?) -> [String] {
        switch letter {
        case "T": ["Tempstar"]
        case "H": ["Heil", "Arcoaire", "Airquest"]
        case "C": ["Comfortmaker", "Day & Night", "KeepRite"]
        case "W": ["Grandaire", "Ecotemp"]
        default: icpBrands
        }
    }

    /// "31 = 30,000 BTUH = 2½ tons" (Heil catalog 401 12 2300 18 p.10), like the other odd codes.
    private static let icpCapacity = "(?<cap>18|19|24|25|30|31|36|37|42|43|48|49|60|61)"

    private static func icpOutdoor(_ p: ModelParts) -> ModelInfo {
        let kind: EquipmentKind = p["type"] == "H" ? .heatPump : .airConditioner
        return info("ICP", icpOutdoorBrands(p["brand"]), kind, size: [tons(p["cap"])])
    }

    static let icpRules: [ModelRule] = [
        // 2007 to about 2019: R4A442GKB100 = family, refrigerant, A/H, SEER, capacity, grille, voltage, sales code, revision.
        ModelRule("(?<brand>[NRHTC])[24](?<type>[AH])[3-9]\(icpCapacity)[AGC][KHLS][A-Z]\\d(?:\\d{2})?") { icpOutdoor($0) },
        // Premium lines, about 2010–2016: TCA724GKA100 (second letter is a feature, not refrigerant).
        ModelRule("(?<brand>[NCHT])[A-Z](?<type>[AH])[5-9]\(icpCapacity)[AGC][KHLS][A-Z]\\d(?:\\d{2})?") { icpOutdoor($0) },
        // SEER2 era, about 2023 on: R4A5S42AKAWA, N5H5S24AKAAA. R4A5S-01PD says "R = Maratherm", but ENERGY STAR
        // lists R models under nearly every ICP brand, so R stays every brand.
        ModelRule("(?<brand>[NRHTCBQW])[45](?<type>[AH])\\d[STV]\(icpCapacity)[AC][KHLSW][A-Z]{3}") { icpOutdoor($0) },
        // Furnaces: F = Tempstar or Arcoaire, G = the Heil and Comfortmaker groups, N = any, R = Maratherm or
        // Smart Comfort. Kenmore sells F and G models too, and DOE lists G97CMN models under Tempstar as well.
        // AFUE 92 and motor E: N92ESN0401410A (ICP 440 21 4541 01); input 026: N95ESN0261410A (ICP N95ESN spec).
        ModelRule(#"(?<brand>[FGNR])9(?<afue>[25-8])[CEMV][STM][NMU](?<input>026|040|060|080|100|120|140)\d{4}[A-Z]\d?"#) { p in
            let brands: [String] = switch p["brand"] {
            case "F": ["Tempstar", "Arcoaire", "Kenmore"]
            case "G": ["Heil", "Comfortmaker", "Day & Night", "KeepRite", "Airquest", "Kenmore"] + (p["afue"] == "7" ? ["Tempstar"] : [])
            case "R": ["Maratherm", "Smart Comfort"]
            default: icpBrands
            }
            return info("ICP", brands, .furnace, size: [btu(p["input"], " input")])
        },
        // Ductless, made by Midea: D5CERAH09AAJ (H = heat pump), M5CVRAQ09AA1 (Q = heat pump), D5CURAA55AAK (A = air
        // conditioner), DLCURAH18AAK. In ENERGY STAR's and DOE's lists every D5C, M5C and DLC outdoor unit with an H or
        // Q there is a heat pump (201) and every one with an A an air conditioner (11).
        ModelRule(#"[DM][5L]C[A-Z]R[AB](?<type>[HQA])(?<cap>06|09|12|18|24|30|36|48|55|58|60)[A-Z]{2,3}\d{0,2}"#) { p in
            info("ICP", ductlessBrands, p["type"] == "A" ? .airConditioner : .heatPump, size: [tons(p["cap"])])
        },
    ]
}
