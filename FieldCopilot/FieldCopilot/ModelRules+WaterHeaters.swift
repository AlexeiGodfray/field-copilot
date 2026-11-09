import Foundation

// Residential water heaters: Rheem/Ruud, A. O. Smith, State, American Water Heater, Bradford White,
// and Rinnai / Navien tankless.
// Sources: Rheem Performance spec sheets THD-PGRH and THD-PE06, PROE and PROG spec sheets; A. O. Smith
// full-line and residential catalogs, aosmithatlowes.com product pages; State spec sheets SRGSS01206,
// SRGSS03711, SRGSS00905 and product pages; americanwaterheater.com product pages; Bradford White RG,
// RG140T6X, high-input and RE230LN6 spec sheets; Rinnai 2020 price list and product pages; Navien
// NPE-2 spec sheet; ENERGY STAR water heater dataset.
//
// The gallon digits are a nominal size (a "50" is often 48 rated gallons).

extension ModelLookup {
    private static func waterHeater(_ manufacturer: String, _ brands: [String], gallons: String?, fuel: String?,
                                    rating: String? = nil, warranty years: String? = nil) -> ModelInfo {
        let gal = gallons.flatMap { Int($0) }.map { "\($0) gal" }
        let warranty = years.flatMap { Int($0) }.map { "\($0)-year warranty" }
        return info(manufacturer, brands, .waterHeater, size: [gal, fuel, rating, warranty])
    }

    /// Electric element codes count hundreds of watts: 45 = 4,500 W.
    private static func watts(_ code: String?) -> String? {
        code.flatMap { Int($0) }.map { "\((($0 % 100) * 100).formatted()) W" }
    }

    /// A. O. Smith family codes, longest first so "GCRT" isn't read as "GCR".
    private static let aoSmithFamilies = """
        ECLB|ECLN|ECRS|ECRT|EJCS|EJCT|ENJB|ENLB|ENSB|ENTT|ESTT|FMDV|FMHR|FPTU|GCBL|GCBN|GCFL|GCNH|GCRH|GCRL|GCRT|GCRX|\
        GCVH|GCVL|GCVT|GCVX|GDHE|GDNL|GDNT|GDPT|GDVT|GPDL|GPDT|GPDX|GPHE|GPNH|GPVL|GPVT|GPVX|GURL|GURT|GVRL|HPTA|HPTU|HURL|HURT|\
        PCRT|PHPT|PXHS|PXHT|PXNS|PXNT|SHPT|XCVT|ECL|ECR|ECS|ECT|EJC|ENJ|ENL|ENS|ENT|FCG|FMD|FMV|GCB|GCF|GCG|GCN|GCR|GCV|\
        GDV|GNR|GPD|GUC|GUF|GUR|GVR|HNS|HNT|HUC|HUR|PCG|PCT|PNT|XCR|XCV|XGV
        """

    private static func aoSmithFuel(_ family: String, series: String?) -> String {
        if ["HPTU", "FPTU", "PHPT", "SHPT", "HPTA"].contains(family) { return "heat pump" }
        let gas = family.hasPrefix("G") || family.hasPrefix("X") || family.hasPrefix("HU") || family.hasPrefix("FM")
            || ["FCG", "PCG"].contains(family)
        guard gas else { return "electric" }
        let propane = ["201", "211", "301", "401"].contains(series ?? "")
        return propane ? "propane" : "gas"
    }

    static let waterHeaterRules: [ModelRule] = [
        // Rheem retail: XG40T06EC36U1 = X, fuel (E electric, G natural gas, P propane), gallons, height, warranty
        // years, type, input (gas kBTU/h, electric kW × 10), revision. XE with an H type is a heat pump.
        ModelRule(#"C?X(?<fuel>[EGP])(?<gal>\d{2})[TSML](?<warr>\d{2})(?<type>[A-Z]{1,3})(?<input>\d{2,3})U[0-9O]"#) { p in
            let (fuel, rating): (String, String?) = switch p["fuel"] {
            case "G": ("natural gas", btu(p["input"]))
            case "P": ("propane", btu(p["input"]))
            default: p["type"]!.hasPrefix("H") ? ("heat pump", nil) : ("electric", watts(p["input"]))
            }
            return waterHeater("Rheem", ["Rheem", "Richmond"], gallons: p["gal"], fuel: fuel, rating: rating,
                               warranty: p["warr"])
        },
        // Rheem/Ruud Professional: PROE50 T2 RH95, PROG50-38N RH60, PRO H40 T2 RU310 (RH = Rheem, RU = Ruud).
        ModelRule(#"C?PROE(?<gal>\d{2})[TMS]?[012](?<brand>RH|RU)\d{0,2}[A-Z0-9\-]*"#) { p in
            waterHeater("Rheem", p["brand"] == "RU" ? ["Ruud"] : ["Rheem"], gallons: p["gal"], fuel: "electric")
        },
        ModelRule(#"C?PRO\+?G(?<gal>\d{2,3})S?-(?<kbtu>\d{2,3})(?<fuel>[NPU])(?<brand>RH|RU)[A-Z0-9\-]*"#) { p in
            waterHeater("Rheem", p["brand"] == "RU" ? ["Ruud"] : ["Rheem"], gallons: p["gal"],
                        fuel: p["fuel"] == "P" ? "propane" : "natural gas", rating: btu(p["kbtu"]))
        },
        // Heat pump: PROPH50 T2 RH375-15. ENERGY STAR lists CD models as Ruud.
        ModelRule(#"C?PRO[PU]?H(?<gal>\d{2})T[02](?<brand>RH|RU|CD)\d{3}[A-Z0-9\-]*"#) { p in
            waterHeater("Rheem", p["brand"] == "RH" ? ["Rheem"] : ["Ruud"], gallons: p["gal"], fuel: "heat pump")
        },
        // A. O. Smith: family, dash, nominal gallons, optional series (GCR-50 300). Propane series: 201/211/301.
        // Gallons are 2 digits, or 100–120: a series cut short ("GCR-50 3") mustn't read as 503 gallons.
        ModelRule("(?<fam>\(aoSmithFamilies))-(?<gal>\\d{2}|1[01]\\d|120)[A-Z]{0,2}-?(?<series>\\d{3})?") { p in
            waterHeater("A. O. Smith", ["A. O. Smith"], gallons: p["gal"], fuel: aoSmithFuel(p["fam"]!, series: p["series"]))
        },
        // A. O. Smith Signature (Lowe's): G6-PVS4040NV (gas, 40 gal, 40,000, N natural gas / P propane), also G6N-, GC9-,
        // G12-CAD and G12-FD lines; E6-50H45DV (electric, 4,500 W); HP heat pumps.
        ModelRule(#"GC?(?<warr>\d{1,2})N?-(?:PV|DV|CAD|FD|P)?[ST]?(?<gal>\d{2})(?<kbtu>\d{2})(?<fuel>[NP])[A-Z]{0,2}"#) { p in
            waterHeater("A. O. Smith", ["A. O. Smith"], gallons: p["gal"], fuel: p["fuel"] == "P" ? "propane" : "natural gas",
                        rating: btu(p["kbtu"]))
        },
        ModelRule(#"E(?<warr>\d{1,2})-(?<gal>\d{2})[HR](?<watt>\d{2})[A-Z\-]{1,6}"#) { p in
            waterHeater("A. O. Smith", ["A. O. Smith"], gallons: p["gal"], fuel: "electric", rating: watts(p["watt"]))
        },
        ModelRule(#"HP[A-Z]{0,2}(?<warr>\d{1,2})-?(?<gal>\d{2})H(?<watt>\d{2})DV[A-Z\-]*"#) { p in
            waterHeater("A. O. Smith", ["A. O. Smith"], gallons: p["gal"], fuel: "heat pump")
        },
        // State: GS6 40 YBRT (Y/X = natural gas, H/C = propane), ES6-50-DORS, HP6-50-DHPT. Smith Cast Iron's GSX
        // steam boilers end in CON or INT (GSX-88-CON in California's archive).
        ModelRule(#"(?!.*(?:CON|INT)$)G[SP][68X][\s-]?(?<gal>\d{2,3})[\s-]?(?<fuel>[YXHC])[A-Z]{2,4}?[TS]?(?:L\d?)?(?:\s?\d{3})?"#) { p in
            waterHeater("A. O. Smith", ["State"], gallons: p["gal"], fuel: ["H", "C"].contains(p["fuel"]) ? "propane" : "natural gas")
        },
        ModelRule(#"E[SNP][68X][\s-]?(?<gal>\d{2,3})[\s-]?[A-Z]{3,5}(?:\d{3})?"#) { p in
            waterHeater("A. O. Smith", ["State"], gallons: p["gal"], fuel: "electric")
        },
        ModelRule(#"HP(?:6|X|AX|SX|VX)-(?<gal>\d{2})-DHPT[A-Z]*(?:\d{3})?"#) { p in
            waterHeater("A. O. Smith", ["State"], gallons: p["gal"], fuel: "heat pump")
        },
        // American Water Heater: G61-50T40 (gas, 50 gal, 40,000), E62-40LB-045DV (electric, 4,500 W).
        // The digit after the warranty is undocumented, so gas isn't split into natural gas and propane. Armstrong's
        // PGE packaged units read like electric ones (PGE10124D050A in California's archive).
        ModelRule(#"[A-Z]{0,3}G(?:[6-9]|1[0-2])[12][\s-]?(?<gal>100|\d{2})[TSL](?<kbtu>100|\d{2})[A-Z0-9\-]*"#) { p in
            waterHeater("A. O. Smith", ["American Water Heater"], gallons: p["gal"], fuel: "gas", rating: btu(p["kbtu"]))
        },
        ModelRule(#"(?!HP|PGE)[A-Z]{0,3}E\d{1,2}[12]-?(?<gal>\d{2})[A-Z]{1,2}-?(?<watt>0\d{2})[A-Z]{1,3}(?:\d{3})?"#) { p in
            waterHeater("A. O. Smith", ["American Water Heater"], gallons: p["gal"], fuel: "electric", rating: watts(p["watt"]))
        },
        ModelRule(#"HP(?:HE|A|S|V)?\d{1,2}[12](?<gal>\d{2})H0\d{2}[A-Z\-]*(?:\d{3})?"#) { p in
            waterHeater("A. O. Smith", ["American Water Heater"], gallons: p["gal"], fuel: "heat pump")
        },
        // Bradford White: RG240T6N = residential, G gas / E electric, tier, (H/HP hybrid heat pump), vent,
        // gallons, height, warranty years, N natural gas / X propane.
        ModelRule(#"U?R(?<fuel>[GE])[123](?<hybrid>HP|H)?(?:PDV|PV|DV|D)?(?<gal>\d{2,3})(?:LN|[TSLH])(?<warr>6|8|10|12)(?<gas>[NX])?(?:-?[0-9A-Z]{1,6})*"#) { p in
            let fuel = p["hybrid"] != nil ? "heat pump"
                : p["fuel"] == "E" ? "electric"
                : p["gas"] == "X" ? "propane" : "natural gas"
            return waterHeater("Bradford White", ["Bradford White"], gallons: p["gal"], fuel: fuel,
                               warranty: p["warr"])
        },
        // Rinnai tankless: RU199iN = family, size (3 digits = max kBTU/h), i indoor / e outdoor, N natural gas / P propane.
        // Two-digit sizes depend on the family: V65iN is 150,000 but RUCS65iN is 130,000 (rinnai.us product pages).
        ModelRule(#"(?<fam>RUR|RUCS|RUC|RSC|RXP|RX|RU|RL|RE|RC|CXP|CX|V)(?<size>\d{2,3})[IE](?<fuel>[NP])"#) { p in
            let kbtu: String? = switch (p["fam"], p["size"]) {
            case ("RUCS", "65"): "130"
            case ("RUCS", "75"): "160"
            case ("RUCS", _): nil
            case (_, "65"): "150"
            case (_, "75"): "180"
            case (_, "94"): "199"
            case (_, let s?) where s.count == 3: s
            default: nil
            }
            return info("Rinnai", ["Rinnai"], .waterHeater,
                        size: ["tankless", p["fuel"] == "P" ? "propane" : "natural gas", btu(kbtu)])
        },
        // Navien tankless: NPE-240A2. The size code isn't the BTU rating: 150 = 120,000, 180 = 150,000, 210 = 180,000,
        // 240 = 199,900 (NPE-2 QuickFacts).
        ModelRule(#"NPE-?(?<size>150|180|210|240)[AS]2?(?:-?(?:NG|LP))?"#) { p in
            let rating: String? = switch p["size"] {
            case "150": "120,000 BTU/h"
            case "180": "150,000 BTU/h"
            case "210": "180,000 BTU/h"
            case "240": "199,900 BTU/h"
            default: nil
            }
            return info("Navien", ["Navien"], .waterHeater, size: ["tankless", rating])
        },
    ]
}
