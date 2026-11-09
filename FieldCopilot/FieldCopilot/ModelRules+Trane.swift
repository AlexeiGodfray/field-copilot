import Foundation

// Trane Technologies: Trane, American Standard, and the RunTru / Ameristar / Trane Advantage value lines.
// Sources: Trane product data 22-1832-12, 22-1814-13, 22-1847-02, 22-1845-12, ODR-PSD009B, ODR-PSD017A,
// ODR-PSD035A, ODR-PSD036B, ODR-PSD049A, FNR-PSD003A, AHR-PSD004B, COR-PSD003A; American Standard
// 23-9065, 23-9095, 23-11318, 2019 furnace catalog, air handler brochure 15-4142-11; ENERGY STAR; DOE's
// certification database.

extension ModelLookup {
    /// "Digit 7, 8 – Nominal Tonnage … 61=5.0 … 72=6.0" (ODR-PSD025B-EN p.4).
    private static let traneCapacity = "(?<cap>12|15|18|19|24|25|30|31|36|37|42|43|48|49|60|61|72)"
    private static let traneShared = ["Trane", "American Standard"]

    /// Coil sizes 001–010 are distinguisher codes for ranges; 18 and up are capacities. The R-454B 5TXC coils
    /// publish their own ranges (5TXC-AS-SUB-1B-EN p.1).
    private static func traneCoilSize(_ code: String?, refrigerant: String?) -> String? {
        guard let code, let n = Int(code) else { return nil }
        if refrigerant == "5", n <= 10 {
            return [1: "1.5–2 tons", 2: "2.5–3 tons", 3: "1.5–2.5 tons", 4: "3–3.5 tons", 5: "3–3.5 tons",
                    6: "3.5–4 tons", 7: "3.5–4 tons", 8: "3.5–5 tons", 9: "3.5–5 tons", 10: "3.5–5 tons"][n]
        }
        switch n {
        case 18...: return tons(code)
        case 1: return "1.5–2 tons"
        case 2, 3: return "1.5–3 tons"
        case 4: return "2–3.5 tons"
        case 5: return "2–4 tons"
        case 6: return "2–5 tons"
        case 7...10: return "3–5 tons"
        default: return nil
        }
    }

    /// Furnace airflow code: "36" or "V3"/"H3"/"C3" is 3 tons of cooling airflow. Codes aren't BTU/h: "45 = 4 Tons …
    /// 54 = 5 Tons … 72 = 6 Tons" (American Standard 12-1248-12 p.6).
    private static func traneAirflow(_ code: String?) -> String? {
        guard let code, let last = code.last, let n = Int(String(last)) else { return nil }
        let published = ["42": "3.5 tons", "45": "4 tons", "54": "5 tons", "72": "6 tons"]
        if let size = published[code] { return "\(size) airflow" }
        return code.first?.isNumber == true ? tons(code).map { "\($0) airflow" } : "\(n) tons airflow"
    }

    static let traneRules: [ModelRule] = [
        // Split, Trane: 4TTR4036L1000A = refrigerant (2/4/5), T, T AC / W HP / C cold-climate HP, family, SEER, coil
        // (0 brazed, 5 mechanical, X link), capacity. TCA, TCC, TCX and TCY are packaged units (5TCC4036A1000A, Choice 14
        // packaged; California's archive lists 4TCA and 4TCX as single-package).
        ModelRule("(?<refr>[245])T(?!C[ACXY])(?<type>[TWC])[A-Z][0-9][05X]\(traneCapacity)[A-Z][134](?:\\d{3})?(?:[A-Z]{1,2})?") { p in
            info("Trane", ["Trane"], p["type"] == "T" ? .airConditioner : .heatPump,
                 size: [tons(p["cap"]), refrigerant(p["refr"])])
        },
        // Split, American Standard: 4A7A6036E1 (7 = AC, 6 = heat pump, 5 = cold-climate heat pump).
        ModelRule("(?<refr>[245])A(?<type>[567])[A-Z][0-9][0X]\(traneCapacity)[A-Z][134](?:\\d{3})?(?:[A-Z]{1,2})?") { p in
            info("Trane", ["American Standard"], p["type"] == "7" ? .airConditioner : .heatPump,
                 size: [tons(p["cap"]), refrigerant(p["refr"])])
        },
        // Value lines: A5HP5036A1000A. "A = RunTru by Trane / Ameristar by American Standard" (ODR-PSD030C-EN p.4).
        // ENERGY STAR lists N models as Trane or American Standard, and E models under all four brands, though the
        // same key says "E = RunTru/Ameristar".
        ModelRule(#"(?<brand>[AEN])(?<refr>[45])(?<type>AC|HP|HL)[345](?<cap>0(?:18|19|24|25|30|31|36|37|42|43|48|49|60|61))[A-Z]1(?:000)?(?:[A-Z]{1,2})?"#) { p in
            let brands = switch p["brand"] {
            case "N": traneShared
            case "E": ["RunTru", "Ameristar"] + traneShared
            default: ["RunTru", "Ameristar"]
            }
            return info("Trane", brands, p["type"] == "AC" ? .airConditioner : .heatPump,
                        size: [tons(p["cap"]), refrigerant(p["refr"])])
        },
        // Side-discharge heat pumps: 5HPL5024A1 (HC = cold climate).
        ModelRule("(?<refr>[45])(?:HP|HC)L[03-8]0\(traneCapacity)[A-Z][134](?:\\d{3})?(?:[A-Z]{1,2})?") { p in
            info("Trane", traneShared, .heatPump, size: [tons(p["cap"]), refrigerant(p["refr"])])
        },
        // Ductless and ducted mini-split outdoor: 4TXK1609A10N0 = "X = Heat Pump Inverter, Y = Cooling Only Inverter",
        // configuration, capacity (22-1918-1D-EN p.4).
        ModelRule(#"(?<refr>[45])T(?<type>[XY])[DKMU]\d{2}(?<cap>09|12|15|18|21|24|27|30|36|42|48|60)[A-Z]\d\d[A-Z0-9]{1,4}"#) { p in
            info("Trane", traneShared, p["type"] == "Y" ? .airConditioner : .heatPump, size: [tons(p["cap"]), refrigerant(p["refr"])])
        },
        // Packaged: 4YCC3018A1040AB (T = AC, W = heat pump, Y = gas/electric, D = dual fuel). Lower confidence.
        ModelRule(#"(?<refr>[245])(?<type>[TWYD])C[A-Z][0-9](?<cap>0(?:18|19|24|25|30|31|36|37|42|43|48|49|60|61))[A-Z][134](?:\d{3})?(?:[A-Z]{1,2})?"#) { p in
            let what: String? = switch p["type"] {
            case "T": "air conditioner"
            case "W": "heat pump"
            case "Y": "gas heat / electric cooling"
            default: "dual fuel"
            }
            return info("Trane", traneShared, .packagedUnit, size: [tons(p["cap"]), what])
        },
        // Furnaces, classic: AUD2B060ACV32B (T = Trane, A = American Standard; input, then airflow).
        ModelRule(#"(?<brand>[TA])[UD][A-Z][1-3M][A-D](?<input>0[4-9][05]|1[0-4][05])[A-Z][0-9A-Z](?<air>[2-7][0-9]|[HVC][1-6])[12V](?:[A-Z]{1,2})?"#) { p in
            info("Trane", p["brand"] == "T" ? ["Trane"] : ["American Standard"], .furnace,
                 size: [btu(p["input"], " input"), traneAirflow(p["air"])])
        },
        // Furnaces, S-series (both brands): S9V2B040U3VSAB. S8 = 80%, S9 = condensing, by series as DOE certifies
        // them: S9B1 92.1%, S9X1 and S9X2 95–96%, S9V2 97%.
        ModelRule(#"S(?<afue>[89])(?<series>[A-Z])[12][A-D](?<input>026|0[4-9]0|1[0-2]0)[UDM](?<tons>[2-5])[A-Z]{2,5}"#) { p in
            let efficiency = switch (p["afue"], p["series"]) {
            case ("8", _): "80% AFUE"
            case (_, "B"): "about 92% AFUE"
            case (_, "X"): "about 96% AFUE"
            case (_, "V"): "about 97% AFUE"
            default: "90%+ AFUE"
            }
            return info("Trane", traneShared, .furnace, size: [btu(p["input"], " input"), efficiency])
        },
        // Furnaces, value lines: A951X040BU3S (RunTru or Ameristar).
        ModelRule(#"A(?<afue>9[0-9])[12][XV](?<input>0[4-9]0|1[0-2]0)[A-D][UD][2-5][A-Z]{1,4}"#) { p in
            info("Trane", ["RunTru", "Ameristar"], .furnace, size: [btu(p["input"], " input"), afue(p["afue"])])
        },
        // Air handlers: TAM7A0C36H31SA. T and G are tiers, not brands ("A,T = Better / G = Good", American Standard
        // 12-1248-12 p.6), and both brands sell both; the airflow digit is "1-5 - nom. Tonnage".
        ModelRule(#"[TG][AEM][MFT][0-9X][A-Z]0[A-D](?<cap>\d{2})[A-Z][1-6][13][A-Z]{0,3}"#) { p in
            info("Trane", traneShared, .airHandler, size: [tons(p["cap"])])
        },
        // R-454B air handlers: 5TAM5B01AC21SB. Capacity isn't encoded, so no size.
        ModelRule(#"5T[ADE][ME][0-9CX][B-D]\d{2}[A-Z][CV][2-5][13][A-Z0-9]{0,3}"#) { p in
            info("Trane", traneShared, .airHandler, size: ["R-454B"])
        },
        // Legacy air handlers: 4TEE3F36A1000AA.
        ModelRule(#"(?<refr>[24])T[EGFV][EPCB][034][0F](?<cap>\d{2})[A-Z][134][0BD](?:\d{2})?(?:[A-Z]{1,2})?"#) { p in
            info("Trane", traneShared, .airHandler, size: [tons(p["cap"]), refrigerant(p["refr"])])
        },
        // Coils: 4TXCB003DS3HCB, 2TXCB036AC3HCAA.
        ModelRule(#"(?<refr>[245])[TCPMAD]X[CAF][A-DH][0UD](?<cap>\d{2})[A-Z][CSZ][36]?[HC]?[A-Z]{0,3}"#) { p in
            info("Trane", traneShared, .evaporatorCoil, size: [traneCoilSize(p["cap"], refrigerant: p["refr"]), refrigerant(p["refr"])])
        },
    ]
}
