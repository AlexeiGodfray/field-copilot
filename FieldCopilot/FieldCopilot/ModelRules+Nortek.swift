import Foundation

// Nortek Global HVAC (Nordyne): Frigidaire, Maytag, Gibson, Intertherm, Miller, Broan, Westinghouse and other
// private labels; the letter before the S is a brand group, but each is sold under many brands.
// Sources: ENERGY STAR's and DOE's listings and California's archive (Nov 2026). Split units with SA after the
// brand letter are all air conditioners (FSA4BD018K) and with SH all heat pumps (FSH4BF5M2SX24K); the older
// FS4BD-018K line, all air conditioners; the Gree-made ductless DXH, GXH and UXH units, all heat pumps. Older
// Nortek heat pumps aren't listed, so their scheme isn't decoded.

extension ModelLookup {
    static let nortekBrands = ["Frigidaire", "Maytag", "Gibson", "Intertherm", "Miller", "Broan", "Westinghouse", "Nordyne",
                               "Nutone", "Philco", "Kelvinator", "Tappan", "Grandaire", "Medallion", "AireForce", "Airtemp"]

    static let nortekRules: [ModelRule] = [
        // Split: FSA1BE4M1SN18K (A = air conditioner), FSH4BF5M2SX24K (H = heat pump), SH4BF5M2SX36K with no brand letter.
        ModelRule(#"[A-Z]?S(?<type>[AH])\d[BMQ][A-Z0-9]{2,7}?(?<cap>18|24|30|36|42|48|60)K[A-Z]{0,2}"#) { p in
            info("Nortek", nortekBrands, p["type"] == "H" ? .heatPump : .airConditioner, size: [tons(p["cap"])])
        },
        // Split air conditioners before the SA line: FS4BD-018K, JS4BD-018KA, MS3QA-024KA, S1BA-018K.
        ModelRule(#"[A-Z]?S\d[BQ][A-Z]-?0(?<cap>18|24|30|36|42|48|60)K[A-Z]{0,2}"#) { p in
            info("Nortek", nortekBrands, .airConditioner, size: [tons(p["cap"])])
        },
        // Ductless and ducted mini-split heat pumps made by Gree: DXH12PSK3IH, GXH18(5.3)FMK4DH-1, UXH24-36MSK3IH.
        ModelRule(#"[DGU]XH(?<cap>09|12|18|24|30|36|42|48)(?:-(?<cap2>36|48|60))?[(0-9.)]*[A-Z]{3}\d[A-Z]{1,2}\d?(?:-\d)?"#) { p in
            info("Nortek", nortekBrands, .heatPump, size: [p["cap2"].flatMap { tonsRange(p["cap"]! + $0) } ?? tons(p["cap"])])
        },
    ]
}
