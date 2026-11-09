import Foundation

// Daikin Comfort Technologies: Goodman, Amana, Daikin.
// Sources: Goodman/Amana spec sheets SS-GSX14, SS-ASX14, SS-DSXC18, SS-ASXC16, SS-ANX13, SS-AVXC20,
// SS-GSXN4, SS-GSXH5, R-32 nomenclature 2024 (Goodman and Amana), SS-GMVC96, SS-GMH95, SS-GCoil,
// SS-AASPT, SS-GAVPTC, SS-AARUF, SS-GPCM3, 2023 Goodman catalog; Daikin SS-DZ14SA, SS-DH5SE, SS-DX5SE,
// SS-DM96VC, SS-DR96SN, SS-DP5HM; ENERGY STAR heat pump and furnace datasets.

extension ModelLookup {
    private static let goodmanCapacity3 = "(?<cap>0(?:18|19|24|25|30|31|36|37|42|43|48|49|60|61)|090|120)"
    private static let goodmanCapacity2 = "(?<cap>12|18|24|30|36|42|48|60)"
    private static let goodmanAmanaDaikin = ["Goodman", "Amana", "Daikin"]

    /// First letter: G = Goodman, A = Amana, D = Daikin. DSXC/DSZC are Goodman's high-feature line.
    private static func goodmanBrand(_ letter: String?, highFeatureGoodman: Bool = false) -> [String] {
        switch letter {
        case "G": ["Goodman"]
        case "A": ["Amana"]
        default: highFeatureGoodman ? ["Goodman"] : ["Daikin"]
        }
    }

    private static func goodmanSplit(_ p: ModelParts, seer: Bool = true) -> ModelInfo {
        let kind: EquipmentKind = ["X", "C"].contains(p["type"]) ? .airConditioner : .heatPump
        let brands = p["brand"].map { goodmanBrand($0, highFeatureGoodman: true) } ?? ["Daikin"]
        return info("Goodman", brands, kind,
                    size: [tons(p["cap"]), seer ? p["seer"].map { "\($0) SEER" } : nil])
    }

    private static func goodmanPackaged(_ p: ModelParts) -> ModelInfo {
        let what: String? = switch p["type"] {
        case "C": "air conditioner"
        case "H": "heat pump"
        case "G", "U": "gas heat / electric cooling"
        case "D": "dual fuel"
        default: nil
        }
        return info("Goodman", goodmanBrand(p["brand"] ?? "D"), .packagedUnit, size: [tons(p["cap"]), what])
    }

    static let goodmanRules: [ModelRule] = [
        // Split outdoor, SEER era (about 2006–2022): GSX140361 = brand, split, X AC / Z HP (C/H = R-22), SEER, capacity.
        ModelRule("(?<brand>[GAD])[SNV](?<type>[XZCH])C?(?<seer>1[3-8]|20)\(goodmanCapacity3)[1-5](?:[A-Z]{1,2})?") { goodmanSplit($0) },
        // Split outdoor, SEER2 R-410A (2023 on): GSXN403610A.
        ModelRule("(?<brand>[GA])S(?<type>[XZ])[BCHMNSV][03-9][0NS]\(goodmanCapacity2)[134][0-9A-Z](?:[A-Z]{1,2})?") { goodmanSplit($0, seer: false) },
        // R-32 (2024 on): GLXS5BA3610AA (top discharge), GXV9SA3610AA (side discharge).
        ModelRule("(?<brand>[GA])L(?<type>[XZ])[ST][3-9][BMCN][ANS]\(goodmanCapacity2)1[0-9A-Z](?:[A-Z]{1,2})?") { goodmanSplit($0, seer: false) },
        ModelRule("(?<brand>[GA])(?<type>[XZ])V[3-9]S[ANS]\(goodmanCapacity2)1[0-9A-Z](?:[A-Z]{1,2})?") { goodmanSplit($0, seer: false) },
        // Daikin split: DZ14SA0361K (legacy), DH5SEA3610AA (SEER2; C/H = R-32).
        ModelRule("D(?<type>[XZ])(?<seer>1[3-8]|20)[STV][ACDN]\(goodmanCapacity3)[1-4](?:[A-Z]{1,2})?") { goodmanSplit($0) },
        ModelRule("D(?<type>[XZCH])[03-9][STV][QECSB][ANS]\(goodmanCapacity2)[134][0-9A-Z](?:[A-Z]{1,2})?") { goodmanSplit($0, seer: false) },
        // Daikin ductless: RX09BXVJU (X = heat pump), RKF09AXVJU (K = air conditioner), 2MXL18WMVJU (2 to 5 zones). In
        // ENERGY STAR's and DOE's lists every RX and 2MX to 5MX is a heat pump (158) and every RK an air conditioner (19).
        ModelRule(#"R(?<type>[XK])[A-Z]{0,2}(?<cap>06|09|12|15|18|24|30|36|42|48)[A-Z]{3,6}"#) { p in
            info("Goodman", ["Daikin"], p["type"] == "X" ? .heatPump : .airConditioner, size: [tons(p["cap"])])
        },
        ModelRule(#"[2-5]MX[A-Z]{1,2}(?<cap>\d{2})[A-Z]{3,6}"#) { p in
            info("Goodman", ["Daikin"], .heatPump, size: [tons(p["cap"])])
        },
        // Packaged: GPHM53641A, GPGM33608031AA, DP5HM…, legacy GPC1460M41A.
        ModelRule(#"(?<brand>[GAD])P(?<type>[CHGDU])[HM][35](?<cap>24|30|36|42|48|60|61)(?:0[4-9]0|1[0-4]0)?[34][13](?:[A-Z]{1,2})?"#) { goodmanPackaged($0) },
        ModelRule(#"DP(?:[35]|1[3-6])(?<type>[CHGD])[HM](?<cap>24|30|36|42|48|60|61)(?:0[4-9]0|1[0-4]0)?[34][13](?:[A-Z]{1,2})?"#) { goodmanPackaged($0) },
        ModelRule(#"(?<brand>[GA])P(?<type>[CHGD])1[3-6](?<cap>18|24|30|36|42|48|60)(?:0[4-9][05]|1[0-4][05])?[HM]4[13](?:[A-Z]{1,2})?"#) { goodmanPackaged($0) },
        // Furnaces: GMVC960803BN = brand, configuration, motor, valve, AFUE, input, airflow, width, NOx.
        ModelRule(#"(?<brand>[GA])[MCDKHR][VES9H][MCST]?(?<afue>80|9[2-7]|8|9)(?<input>030|040|045|060|070|080|090|100|115|120|140)[2-5][A-D][NXU]?(?:[A-Z]{1,2})?"#) { p in
            info("Goodman", goodmanBrand(p["brand"]), .furnace, size: [btu(p["input"], " input"), afue(p["afue"])])
        },
        // Daikin furnaces put AFUE first: DM96VC0603BN.
        ModelRule(#"D[MCRD](?<afue>80|9[2-7])[MVHST][CESN](?<input>030|040|060|080|100|120)[2-5][A-D][NXU](?:[A-Z]{1,2})?"#) { p in
            info("Goodman", ["Daikin"], .furnace, size: [btu(p["input"], " input"), afue(p["afue"])])
        },
        // Coils, shared by all three brands: CAPF3743C6 (4-digit capacity range), CAPFA2422B6 (2-digit capacity).
        ModelRule(#"C[AHS][UCP][FT](?<range>1729|1824|1830|2430|3030|3036|3131|3137|3636|3642|3743|4860|4961)[A-DN][246](?:[A-Z]{1,2})?"#) { p in
            info("Goodman", goodmanAmanaDaikin, .evaporatorCoil, size: [tonsRange(p["range"])])
        },
        ModelRule(#"C[AHS][UCPH][FTE][AS](?<cap>1[7-9]|[2-5][0-9]|6[01])(?:14|18|22|26|30)[A-DN][2346](?:[A-Z]{1,2})?"#) { p in
            info("Goodman", goodmanAmanaDaikin, .evaporatorCoil, size: [tons(p["cap"])])
        },
        // Air handlers. Legacy ASPT/ARUF/AVPTC: the leading A means air handler, not Amana, and Daikin sells them too
        // (SS-DARUF); 2-digit sizes are ambiguous. A 4-digit code is a range, except on wall-mount AWUF, where it's the
        // capacity and the heater: "A W U F 24 05 … Heater Kit 05 = 5 kW" (SS-AAWUF).
        ModelRule(#"A(?<type>[CDERSVW])[UPN][FTV]C?(?<cap>\d{2}|\d{4})[B-D]?1[46]?(?:[A-Z]{1,2})?"#) { p in
            let code = p["cap"]!
            let size: [String?] = p["type"] == "W" && code.count == 4
                ? [tons(String(code.prefix(2))), Int(code.suffix(2)).flatMap { $0 > 0 ? "\($0) kW heater" : nil }]
                : [tonsRange(code)]
            return info("Goodman", goodmanAmanaDaikin, .airHandler, size: size)
        },
        // Daikin air handlers: DV37PTCB14 (SS-DVPTC); 2-digit sizes are ambiguous.
        ModelRule(#"DV\d{2}PTC[A-D]\d{2}(?:[A-Z]{1,2})?"#) { _ in
            info("Goodman", ["Daikin"], .airHandler)
        },
        // Newer: AMST36BU1400 = corporate (A, sold by all three brands) or Daikin (D) air handler; the size is
        // nominal: "Nominal Capacity … 36 - 3.0 Tons" (SS-DAMST).
        ModelRule("(?<brand>[AD])[CHMWF][SV][EFT]\(goodmanCapacity2)[BCDSLM][PUNH][01][346]\\d\\d(?:[A-Z]{1,2})?") { p in
            info("Goodman", p["brand"] == "D" ? ["Daikin"] : goodmanAmanaDaikin, .airHandler, size: [tons(p["cap"])])
        },
    ]
}
