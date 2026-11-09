import Foundation

// Lennox and Lennox-owned Allied Air (Armstrong Air, AirEase, Ducane, Concord).
// Sources: Lennox Model Number Identification form 210965 (2025), Lennox product data 13HPX, XC16,
// ML13KC1, ML180, CBX25, CBX32, Lennox "Model Numbering Systems" data-tag guide; Allied Air spec
// sheets 4SCU16, A7AC14F, 7AC14F; ENERGY STAR heat pump, light commercial and furnace datasets.

extension ModelLookup {
    /// Lennox's old 3-digit capacity codes before the 018–060 scheme: 41x = 3 tons, 51x = 4 tons.
    private static func lennoxCapacity(_ code: String?) -> String? {
        guard let code else { return nil }
        if code.hasPrefix("0") { return tons(code) }
        let old: [String: String] = ["14": "1 ton", "21": "1.5 tons", "26": "2 tons", "31": "2.5 tons",
                                     "41": "3 tons", "46": "3.5 tons", "51": "4 tons", "65": "5 tons"]
        return old[String(code.prefix(2))]
    }

    /// "Nominal Gas Heat Input … 045 = 44,000 Btuh … 070 = 66,000 … 090 = 88,000 … 135 = 132,000" (form 210965);
    /// the other codes are the input in thousands.
    private static let lennoxRatedInput = ["045": 44, "070": 66, "090": 88, "135": 132]

    /// Coil sizes, some of them ranges: "18/24 = 1.5/2 tons … 48 = 3.5/4 tons … 50/60 = 4/5 tons" (bulletin 210879).
    private static func lennoxCoilSize(_ code: String?) -> String? {
        switch code {
        case "18/24": "1.5–2 tons"
        case "30/36": "2.5–3 tons"
        case "48": "3.5–4 tons"
        case "50/60": "4–5 tons"
        default: tons(code)
        }
    }

    private static func lennoxRefrigerant(_ letter: String?) -> String? {
        switch letter {
        case "X": "R-410A"
        case "K": "R-454B"
        default: nil
        }
    }

    static let lennoxRules: [ModelRule] = [
        // Merit: 13HPX-048-230-18 = SEER 13, HP (heat pump) or AC, X = R-410A, 4 tons, 208/230 V, revision.
        ModelRule(#"1[0-6](?<type>AC|HP)(?<refr>[A-Z])-?(?<cap>\d{3})-?\d{3}[A-Z]?(?:-?\d{1,2})?"#) { p in
            info("Lennox", ["Lennox"], p["type"] == "AC" ? .airConditioner : .heatPump,
                 size: [tons(p["cap"]), lennoxRefrigerant(p["refr"])])
        },
        // Elite/Signature: XC16-036-230-2 (XC = AC, XP = heat pump).
        ModelRule(#"X(?<type>[CP])\d{2}-?(?<cap>\d{3})-?\d{3}[A-Z]?(?:-?\d{1,2})?"#) { p in
            info("Lennox", ["Lennox"], p["type"] == "C" ? .airConditioner : .heatPump, size: [tons(p["cap"]), "R-410A"])
        },
        // Tiered: SL25KCV-036-230A-1 = Signature/Elite/Merit, SEER, X/K refrigerant, C = AC; P, L, SP, SL = heat pump.
        // ENERGY STAR also lists Merit (ML) units under Allied Commercial and GE. An S in place of the first dash
        // marks a regional model ("S = North and South Regions", bulletin 210760).
        ModelRule(#"(?<tier>[EMS])L\d{2}(?<refr>[XK])(?<type>S?[CPL])[12V](?:-|S)?(?<cap>\d{3})-?\d{3}[A-Z]?(?:-?\d{1,2})?"#) { p in
            info("Lennox", p["tier"] == "M" ? ["Lennox", "Allied Commercial", "GE"] : ["Lennox"],
                 p["type"]!.hasSuffix("C") ? .airConditioner : .heatPump, size: [tons(p["cap"]), lennoxRefrigerant(p["refr"])])
        },
        // Legacy: HS26-060-1P (HS = AC), HP19-511-1Y (heat pump, old capacity code 51 = 4 tons). A V after the
        // capacity is an expansion valve (data-tag guide p.5): HS16-411V-3.
        ModelRule(#"(?<type>HS|HP)(?:XA|XB)?\d{2}-?(?<cap>\d{3})V?(?:-?\d{3})?-?\d{1,2}[A-Z]?"#) { p in
            info("Lennox", ["Lennox"], p["type"] == "HS" ? .airConditioner : .heatPump, size: [lennoxCapacity(p["cap"])])
        },
        // Furnaces: ML180UH070XE36B = tier, stages, AFUE, upflow/downflow, input (nominal), NOx, motor, cooling, width.
        ModelRule(#"[EMS]L[12P](?<afue>\d{2})(?:UH|DF)(?<input>\d{3})[XN]?[EVP]?(?:24|36|48|60)[A-D]K?(?:-?\d{1,2})?"#) { p in
            info("Lennox", ["Lennox"], .furnace, size: [input(p["input"], rated: lennoxRatedInput), afue(p["afue"])])
        },
        // Air handlers: CBX25UH-030-230-01, CBK45UHET-036-230A-71 = configuration UH or M, blower E/P/V, T metering
        // (form 210965 p.3). X and A are R-410A ("A = Aluminum Coil/R-410A", form 211248), but K doesn't settle the
        // refrigerant: ENERGY STAR pairs CBK45 and CBK47 with R-410A and R-454B systems.
        ModelRule(#"CB(?<refr>[XKA])\d{2}(?:UH|M)[EPV]?T?-?(?<cap>\d{3})(?:/\d{3})?-?(?:\d{3}|DV)[A-Z]?(?:-?\d{1,2}){0,2}"#) { p in
            info("Lennox", ["Lennox"], .airHandler, size: [tons(p["cap"]), ["X", "A"].contains(p["refr"]) ? "R-410A" : nil])
        },
        // Coils: CK40CT-36A-71, CX35-36B.
        ModelRule(#"C(?:HX|RX|[KXHR])?\d{2}(?:CT|HT|DT|UT)?-?(?<cap>\d{2}(?:/\d{2})?)[A-D](?:-?\d{1,2}[A-Z]{0,2}){0,2}"#) { p in
            info("Lennox", ["Lennox"], .evaporatorCoil, size: [lennoxCoilSize(p["cap"])])
        },
        // Allied Air: 4SCU16LE136P-4A, A7AC14F36P; 4 = R-410A, 7 = R-454B. An A prefix is Armstrong Air or
        // AirEase; ENERGY STAR lists SHP models under all five Allied brands (SCU, the AC, is taken to match), and
        // 4HP18V and A-prefixed models under AC Pro too.
        ModelRule(#"(?<a>A)?(?<refr>[47])(?<type>SCU|SHP|SCP|AC|HP|CP)\d{2}[A-Z]{1,2}(?:\d|R)?(?<cap>\d{2})[PYG](?:-?[0-9]{1,2}[A-Z]?)?"#) { p in
            let kind: EquipmentKind = ["SCU", "AC"].contains(p["type"]) ? .airConditioner : .heatPump
            let brands = p["a"] != nil ? ["Armstrong Air", "AirEase", "AC Pro"]
                : ["SCU", "SHP"].contains(p["type"]) ? ["Armstrong Air", "AirEase", "Ducane", "Concord", "Allied"]
                : ["Ducane", "Concord", "Allied", "AC Pro"]
            return info("Allied Air", brands, kind,
                        size: [tons(p["cap"]), p["refr"] == "7" ? "R-454B" : "R-410A"])
        },
    ]
}
