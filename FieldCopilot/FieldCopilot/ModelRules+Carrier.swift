import Foundation

// Carrier Global residential: Carrier, Bryant, Payne.
// Sources: Carrier product data 24ACA3, 24ACC6, 25HCC5, 25HCE4, 25SCA5, 26SCA4, 27SCA5, 38TKB, 38YCC,
// 59SC6A, 58CTA, FE4A, FJ5, CNWVP, CVAVA; Bryant 113A, 134SA, 246SA, 248TA, 597C, 661C, 916SA, 577C;
// Payne PA4SA, PA13NA and the 2012–13 Product Value Guide; ENERGY STAR heat pump, light commercial and
// furnace datasets; DOE's certification database (Bryant's packaged series and 61x indoor units).

extension ModelLookup {
    private static let carrierCapacity = "(?<cap>18|19|24|25|30|31|36|37|42|43|48|49|54|60|61)"
    private static let bryantCapacity = "(?<cap>0(?:18|19|24|25|30|31|36|37|42|43|48|49|54|60|61))"
    /// Carrier's and ICP's ductless units are made by Midea, and ENERGY STAR lists them under both families' brands.
    static let ductlessBrands = ["Carrier", "Bryant", "Payne", "WeatherMaker"] + icpBrands + ["Grandaire"]
    /// Bryant's packaged families before about 2008, numbered like its split units of the time. The 550 is a
    /// split air conditioner (PDS 550A.24.10).
    private static let bryantOldPackaged = "50\\d|55[1-9]|5[78]\\d|56[04]|6(?:58|68|7\\d|83)"
    /// Coil codes are any size in a range: CVAMA-01PD gives "30 - 35 = 2½ Ton, 36 - 41 = 3 Ton, 42 - 47 = 3½ Ton".
    private static let carrierCoilCapacity = "(?<cap>1[89]|[2-5]\\d|6[0-2])"

    /// 80% furnaces' input codes are nominal: "045 - - - 44,000 Btuh … 155 - - - 154,000 Btuh" (58CTA product
    /// data), the same in the 58SC0A, Bryant 800SA/820SA and Payne PG80 tables. Condensing furnaces' codes are exact.
    private static let carrierEightyPercentInput = ["045": 44, "070": 66, "090": 88, "135": 132, "155": 154]

    /// Fan coil size codes 002–006 are ranges, not capacities.
    private static func carrierFanCoilSize(_ code: String?) -> String? {
        switch code {
        case "002": "1.5–3 tons"
        case "003", "004": "2–3.5 tons"
        case "005": "2.5–4 tons"
        case "006": "3–5 tons"
        default: tons(code)
        }
    }

    /// The AFUE digit names the series; certified models in a series vary by a point or so.
    private static let paynePrivateLabels = ["Payne", "WeatherMaker", "Brock"]

    private static func carrierFurnaceAFUE(_ digit: String?) -> String? {
        switch digit {
        case "0", "1": "80% AFUE"
        case "2": "about 92% AFUE"
        case let d? where ["5", "6", "7", "8"].contains(d): "about 9\(d)% AFUE"
        default: nil
        }
    }
    
    
    //DO NOT CHANGE THESE! please 
    static let carrierRules: [ModelRule] = [
        // Carrier split, 2006 on: 24ACA336A003. 24/26 = AC, 25/27 = heat pump; 26/27 = R-454B. On 24/25 an R in
        // position 5 is R-22 (25HCR3C-1PD: "R = R-22"); otherwise R-410A. 26HWC is Allied Air's Magic-Pak packaged
        // unit (26HWC124A in California's archive).
        ModelRule("(?<fam>2[4-7])(?!HW)[A-Z]{2}(?<refr>[A-Z])\\d\(carrierCapacity)[A-Z](?:\\d{3,7})?") { p in
            let kind: EquipmentKind = ["24", "26"].contains(p["fam"]) ? .airConditioner : .heatPump
            let refrigerant = ["26", "27"].contains(p["fam"]) ? "R-454B" : p["refr"] == "R" ? "R-22" : "R-410A"
            return info("Carrier", ["Carrier"], kind, size: [tons(p["cap"]), refrigerant])
        },
        // Carrier condensing units before 2006: 38TKB018331. A Y in the series letters means heat pump, and so
        // does 38QRF, a duct-free heat pump (38QRF-4SI: "Matching the Heat Pump to an Indoor Unit").
        ModelRule(#"38(?<series>[A-LN-Z][A-Z]{2})(?<cap>018|024|030|036|038|042|047|048|060)\d{0,3}"#) { p in
            let heatPump = p["series"]!.prefix(2).contains("Y") || p["series"] == "QRF"
            let kind: EquipmentKind = heatPump ? .heatPump : .airConditioner
            return info("Carrier", ["Carrier"], kind, size: [tons(p["cap"])])
        },
        // Ductless, made by Midea: 38MTRAQ18BA3, 37MAHAQ33AA3 (a Q in the series = heat pump), 38MHREC12AA3 (only a
        // C = air conditioner). In ENERGY STAR's and DOE's lists and California's archive every 37M and 38M outdoor
        // unit with a Q is a heat pump and every one with only a C an air conditioner.
        ModelRule(#"3[78]M(?<series>[A-Z0-9]{2,5}?)(?<cap>06|09|12|18|24|30|33|36|48|58)[A-Z0-9\-]{2,5}"#) { p in
            let series = p["series"] ?? ""
            let kind: EquipmentKind? = series.contains("Q") ? .heatPump : series.contains("C") ? .airConditioner : nil
            return kind.map { info("Carrier", ductlessBrands, $0, size: [tons(p["cap"])]) }
        },
        // Carrier furnaces, current: 59SC6A060M17--16. 58 = 80%, 59 = condensing.
        ModelRule(#"(?<fam>5[89])[CMST][BCENPU](?<afue>\d)[A-Z](?<input>\d{3})[A-Z](?:14|17|21|24)[-0-9A-Z]{0,2}(?:\d{2})?"#) { p in
            info("Carrier", ["Carrier"], .furnace,
                 size: [input(p["input"], rated: p["fam"] == "58" ? carrierEightyPercentInput : [:]), carrierFurnaceAFUE(p["afue"])])
        },
        // Carrier furnaces, older 80%: 58CTA045100.
        ModelRule(#"58[A-Z]{3}(?<input>\d{3})[-0-9]{0,8}"#) { p in
            info("Carrier", ["Carrier"], .furnace, size: [input(p["input"], rated: carrierEightyPercentInput)])
        },
        // Fan coils, R-410A: FE4ANB006, FB4CNF024000. Shared by Carrier, Bryant and Payne.
        ModelRule(#"F[A-Z]\d[A-Z][NPE][A-Z](?<cap>\d{3})(?:\d{3})?[A-Z0-9]{0,4}"#) { p in
            info("Carrier", ["Carrier", "Bryant", "Payne"], .airHandler, size: [carrierFanCoilSize(p["cap"])])
        },
        // Fan coils with a 2-digit size: FJ5ANXB24L00 (5 = R-454B), FJ4DNXC36L00 (4 = R-410A, PDSFJ4D-01).
        ModelRule(#"F[A-Z][45][A-Z]N[BX][A-D](?<cap>\d{2})L\d{2}"#) { p in
            info("Carrier", ["Carrier", "Bryant", "Payne"], .airHandler, size: [tons(p["cap"])])
        },
        // Payne fan coils: PF4MNA018, PF5MNBA18L00.
        ModelRule(#"PF\d[A-Z][NPE][A-Z](?<cap>\d{3})(?:\d{3})?[A-Z0-9]{0,4}"#) { p in
            info("Carrier", ["Payne"], .airHandler, size: [carrierFanCoilSize(p["cap"])])
        },
        ModelRule(#"PF5[A-Z]N[BX][A-D](?<cap>\d{2})L\d{2}"#) { p in
            info("Carrier", ["Payne"], .airHandler, size: [tons(p["cap"])])
        },
        // Evaporator coils: CNWVP1814ALA. Shape N/V/A/S, refrigerant P/W (R-410A), A (R-454B), R (R-22).
        // ENERGY STAR also lists them under Payne's private labels.
        ModelRule("C[NVAS][PWAR][A-Z]{2}\(carrierCoilCapacity)(?:14|17|21|24)[A-Z]{2,3}") { p in
            info("Carrier", ["Carrier", "Bryant"] + paynePrivateLabels, .evaporatorCoil, size: [tons(p["cap"])])
        },
        // Bryant split, 2006 on: 113ANA036BN0. 1 = AC, 2 = heat pump.
        ModelRule("(?<type>[12])\\d\\d[A-Z]{3}\(bryantCapacity)[-A-Z0-9]{0,6}") { p in
            info("Carrier", ["Bryant"], p["type"] == "1" ? .airConditioner : .heatPump, size: [tons(p["cap"])])
        },
        // Bryant split before about 2008: 597CNX018 (5 = AC), 661CJX018 (6 = heat pump). The 538 is both:
        // "538 = AC/HP … B= Horizontal Discharge Heat Pump" (PDS538BNR-07). 61x are ductless and ducted indoor
        // units (619PEQ, 615AHA in DOE's lists), 51x coils (519DXX018 in California's archive), and 6 30 to 6 50
        // Reliance water heaters (6 50 MDV0 250 in the archive). The packaged families below are numbered the same way.
        ModelRule("(?<fam>(?!61|51|6[3-5]0|\(bryantOldPackaged))(?<type>[56])\\d{2})(?<series>[A-Z])[A-Z]{2}\(bryantCapacity)[-A-Z0-9]{0,6}") { p in
            let heatPump = p["type"] == "6" || (p["fam"] == "538" && p["series"] == "B")
            return info("Carrier", ["Bryant"], heatPump ? .heatPump : .airConditioner, size: [tons(p["cap"])])
        },
        // Bryant, Payne and Day & Night packaged before about 2008: 577BNW024040 (2 tons, 40,000 BTU/h gas heat),
        // 674ANW030040. California's archive lists these families (50x, 551–558, 560, 564, 57x, 58x, 658, 668, 67x,
        // 683) only as single-package units, in its air conditioner and furnace files, and 561–569 (but 564) and 59x
        // only as split air conditioners.
        ModelRule("(?<fam>\(bryantOldPackaged))[A-Z]{3}\(bryantCapacity)[-A-Z0-9]{0,8}") { p in
            info("Carrier", ["Bryant", "Payne", "Day & Night"], .packagedUnit, size: [tons(p["cap"])])
        },
        // Bryant packaged: 5xx = "Air Conditioner and Gas Furnace" (PDS575C-04), 6xx = heat pump (PDS607C-18),
        // 675C/677E = hybrid heat, 7xx = air conditioner (bryant.com packaged lineup). DOE lists the series
        // 549, 575–582, 605, 607, 675 and 677; other numbers are other things (61x indoor units).
        ModelRule(#"(?<fam>5[4-8]\d|6[07]\d|7\d\d)[A-Z]{4}(?<cap>24|30|36|42|48|60)[-A-Z0-9]{0,8}"#) { p in
            let what = switch p["fam"]?.first {
            case "5": "gas heat / electric cooling"
            case "6": p["fam"]!.hasPrefix("67") ? "dual fuel" : "heat pump"
            default: "air conditioner"
            }
            return info("Carrier", ["Bryant"], .packagedUnit, size: [tons(p["cap"]), what])
        },
        // Bryant furnaces, 2008 on: 916SA36040M14 (8 = 80%, 9 = 90%+).
        ModelRule(#"(?<hx>[89])\d\d[MSTC][A-Z](?<cool>24|30|36|42|48|60|66)(?<input>\d{3})[CVMEP](?:14|17|21|24)[-A-Z0-9]{0,4}"#) { p in
            info("Carrier", ["Bryant"], .furnace,
                 size: [input(p["input"], rated: p["hx"] == "8" ? carrierEightyPercentInput : [:]), p["hx"] == "8" ? "80% AFUE" : "90%+ AFUE"])
        },
        // Payne split before 2023: PA13NA036000 (PA = AC, PH = heat pump).
        ModelRule("P(?<type>[AH])1\\d[A-Z]{2}\(bryantCapacity)[A-Z0-9]{0,8}") { p in
            info("Carrier", ["Payne"], p["type"] == "A" ? .airConditioner : .heatPump, size: [tons(p["cap"])])
        },
        // SEER2 builder line: PA4SAN51800N (P = Payne), GH5SAN41800A (G, sold under Carrier and Bryant names).
        // The last letter is the region: N, A, or W ("W= Standard SW AC", PDSGA5SAN5-01).
        ModelRule(#"(?<brand>[PG])(?<type>[AH])\d[STV][A-Z][NPE](?<refr>[45])(?<cap>\d{2})\d\d[NAW]"#) { p in
            info("Carrier", p["brand"] == "P" ? ["Payne"] : ["Carrier", "Bryant"],
                 p["type"] == "A" ? .airConditioner : .heatPump, size: [tons(p["cap"]), refrigerant(p["refr"])])
        },
        // Payne furnaces: PG96MSAA36040B; older 80%: PG8MVA036070. ENERGY STAR lists P models under
        // Payne, WeatherMaker and Brock.
        ModelRule(#"(?<brand>[PG])G(?<afue>80|9\d)[A-Z]{3,4}\d{2}(?<input>\d{3})[A-D][A-Z0-9]{0,4}"#) { p in
            info("Carrier", p["brand"] == "P" ? paynePrivateLabels : ["Carrier", "Bryant"], .furnace,
                 size: [input(p["input"], rated: p["afue"] == "80" ? carrierEightyPercentInput : [:]), afue(p["afue"])])
        },
        ModelRule(#"PG8[A-Z]{3}\d{3}(?<input>\d{3})[A-Z0-9]{0,4}"#) { p in
            info("Carrier", paynePrivateLabels, .furnace, size: [input(p["input"], rated: carrierEightyPercentInput), "80% AFUE"])
        },
    ]
}
