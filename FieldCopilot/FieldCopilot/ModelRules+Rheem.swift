import Foundation

// Rheem Manufacturing HVAC: Rheem, Ruud and Rheem-built private labels.
// Sources: Rheem RA14 parts list 92-42800, RA14AZ, RA14AY, RP14AZ, RP16AZ, R951V, R802V, R98V, RH2TY,
// RCFY, RCF spec sheets; Ruud RA14 spec A22-220, U96V, R96P, R801T specs and BIM pages; RANL, RPNL,
// RAKA, RGPN, RHLL parts lists; WP14AZ "Rheem Select" spec; ENERGY STAR heat pump and furnace datasets.

extension ModelLookup {
    /// Since about 2014 Ruud uses the same R-prefixed model numbers as Rheem, so R means either.
    /// U is Ruud only; the other letters are Rheem-built private labels, as ENERGY STAR lists them.
    private static func rheemBrands(_ letter: String?) -> [String] {
        switch letter {
        case "U": ["Ruud"]
        case "W": ["WeatherKing", "Rheem", "Ruud", "Rheem Select", "Ruud Choice", "Fujitsu"]
        case "S": ["Sure Comfort", "Russell"]
        case "WL": ["Whirlpool"]
        case "FR", "FW": ["Friedrich"]
        case "ML": ["Mainline"]
        case "TZ": ["Thermal Zone"]
        default: ["Rheem", "Ruud"]
        }
    }

    /// Input codes are nominal. Condensing furnaces are rated "060 = 56,000 … 085 = 84,000 … 100 = 98,000" (R96V
    /// spec G11-540), and R951T's table rates 040 at 42,000 and 115 at 112,000 though its key says 40,000 and
    /// 115,000. 80% furnaces: "100 = 98,000 BTU/HR" (R801T parts list). Other codes are the input in thousands.
    private static let rheemCondensingInput = ["040": 42, "060": 56, "085": 84, "100": 98, "115": 112]
    private static let rheemEightyPercentInput = ["100": 98]

    private static func rheemFurnace(_ p: ModelParts) -> ModelInfo {
        let rated = p["afue"] == "80" ? rheemEightyPercentInput : rheemCondensingInput
        return info("Rheem", rheemBrands(p["brand"]), .furnace,
                    size: [input(p["input"], rated: rated), afue(p["afue"]),
                           p["tons"].flatMap { tons(String(Int($0)! * 12)) }.map { "\($0) airflow" }])
    }

    static let rheemRules: [ModelRule] = [
        // Outdoor, 2014 on: RA1436AJ1NA, RP14AZ36AJ2NA = brand, A AC / P heat pump / D side-discharge HP,
        // SEER series, (region and refrigerant Z = R-410A, Y = R-454B), capacity, series, voltage, stages, controls,
        // options (LHP, A40 vertical louvers). Friedrich is FW with SA for its legacy AC (spec AFR-352).
        ModelRule(#"(?<brand>WL|FW|FR|ML|TZ|[RUWS])(?<cat>[APD]|SA)\d{2}(?:[ANS](?<refr>[ZY]))?(?<cap>18|24|30|36|42|48|60)[A-Z][JCDY][123V][NCVX][A-Z]?(?:LHP|A40)?"#) { p in
            let refrigerant: String? = switch p["refr"] {
            case "Z": "R-410A"
            case "Y": "R-454B"
            default: nil
            }
            // ENERGY STAR also lists R outdoor units under Rheem's private labels.
            let brands = rheemBrands(p["brand"]) + (p["brand"] == "R" ? ["Sure Comfort", "Russell", "Friedrich"] : [])
            let ac = ["A", "SA"].contains(p["cat"])
            return info("Rheem", brands, ac ? .airConditioner : .heatPump, size: [tons(p["cap"]), refrigerant])
        },
        // Outdoor before about 2014: RANL-018JAZ (R = Rheem, U = Ruud; A = AC, P = heat pump).
        // Compressor Z, S or C ("C= Scroll/Serial Communicating"); "025= 24,000 … 039= 39,000" (RASL parts list).
        ModelRule(#"(?<brand>[RU])(?<cat>[AP])[A-Z]{2}-?(?<cap>0(?:18|24|25|30|31|36|37|39|42|43|48|49|60))[JCDYTN][A-Z][ZSC]"#) { p in
            info("Rheem", p["brand"] == "U" ? ["Ruud"] : ["Rheem"], p["cat"] == "A" ? .airConditioner : .heatPump,
                 size: [tons(p["cap"])])
        },
        // Furnaces, about 2023 on: R951V0403A17M4SCAP = brand, AFUE, stages, motor, input, cooling tons, series, width, position.
        ModelRule(#"(?<brand>WL|FR|[RUWS])(?<afue>80|9\d)[12M][VTPW](?<input>\d{3})(?<tons>[2-6])[A-Z](?:14|17|21|24)(?:M4|DZ|UP|UH)[SNU]?[CNG]?[A-Z]?[PS]?"#) { rheemFurnace($0) },
        // Furnaces, 2010s: U96VA0402317MSA (90%+), U801TA075417ZSA (80%).
        ModelRule(#"(?<brand>[RU])(?<afue>9\d)[VPT][A-Z](?<input>\d{3})[12M](?<tons>[2-6])(?:14|17|21|24)[MUZDH][SNX][A-Z]"#) { rheemFurnace($0) },
        ModelRule(#"(?<brand>[RU])(?<afue>80)[12][TPSVC][A-Z](?<input>\d{3})(?<tons>[2-6])(?:14|17|21|24)[MUZDH][SNX][A-Z]"#) { rheemFurnace($0) },
        // Legacy gas furnaces: RGPN-07EAMGR. The input code is a per-series lookup, so no size.
        ModelRule(#"(?<brand>[RU])G[A-Z]{2}-?(?:0[4-9]|1[0-5])[A-Z]{3,5}"#) { p in
            info("Rheem", p["brand"] == "U" ? ["Ruud"] : ["Rheem"], .furnace)
        },
        // Air handlers: RH2TY2417STANAA; the capacity is a maximum.
        ModelRule(#"(?<brand>[RUWS])H[123][TVPA][YZ]?(?<cap>18|24|25|30|36|42|48|60)(?:14|17|21|24)[SMHU][TEP][A-Z]{3,5}"#) { p in
            info("Rheem", rheemBrands(p["brand"]), .airHandler, size: [tons(p["cap"]).map { "up to \($0)" }])
        },
        // RHLL-HM3821JA exists, but the key doesn't list 38, so it gets no size.
        ModelRule(#"(?<brand>[RU])H[A-Z]{2}-?[A-Z]{2}(?<cap>18|24|25|30|36|38|42|48|60)(?:14|17|21|24)[AJD][A-Z]"#) { p in
            info("Rheem", p["brand"] == "U" ? ["Ruud"] : ["Rheem"], .airHandler,
                 size: [p["cap"] == "38" ? nil : tons(p["cap"]).map { "up to \($0)" }])
        },
        // Coils: RCFY2414STAAMCL (F = furnace coil, H = air-handler coil).
        ModelRule(#"(?<brand>[RUWS])C[FH][YZ]?(?<cap>18|24|30|36|42|48|60)(?:14|17|21|24)[SMHU][TEP][A-Z]{3,6}"#) { p in
            info("Rheem", rheemBrands(p["brand"]), .evaporatorCoil, size: [tons(p["cap"])])
        },
    ]
}
