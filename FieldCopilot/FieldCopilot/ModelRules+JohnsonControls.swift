import Foundation

// Johnson Controls: York, Luxaire, Coleman, Fraser-Johnston, Champion, Guardian, Evcon, and York's and Hitachi's
// ductless units.
// Sources: ENERGY STAR's and DOE's listings and California's archive (Nov 2026). In every listed split model, a C
// after York's Y, Luxaire's T or Coleman's C is an air conditioner (YC2D18SB21, TCJF24S41S1, CC7B1821) and an H a
// heat pump (YH2E18SB21, THF2B18S21); in the value lines, a first A is an air conditioner (AC19B2421, AL19B2421)
// and an H a heat pump (HC19B2421, HL19B2421); Guardian's and Evcon's RAC and RAW are air conditioners and RHP heat
// pumps; the 2023 lines (YH524E, XH630E, HH824E, YD524E) and York's YZ are all heat pumps, its YX air conditioners;
// Hitachi's RAC-, RAM- and York's YRAC and YRAM ductless units are all heat pumps. York's YHJE and YHJF ductless
// units, made by Midea, are listed as air conditioners, so they aren't decoded.

extension ModelLookup {
    static let luxaireBrands = ["Luxaire", "Fraser-Johnston", "Champion Heating and Cooling", "Coleman"]
    static let colemanBrands = ["Coleman", "Evcon", "Guardian", "Fraser-Johnston"]
    static let guardianBrands = ["Guardian", "Evcon"]

    static let johnsonControlsRules: [ModelRule] = [
        // York, Luxaire and Coleman split: YC2D18SB21 = brand (Y York, T Luxaire, C Coleman), C AC / H heat pump,
        // series, capacity, and an ending the coils, air handlers and packaged units that start the same way don't
        // have (TCFY2417STAN, CH32-18CDI, YCD036A3HOA): 21, S21, SB21, S41S1. TCFA, TCFL and TCFY are coils
        // (TCFA-H4821), and a series starting with H and a digit is ICP's (CCH624GKA1).
        ModelRule(#"(?<brand>[YTC])(?<type>[CH])(?!F[ALY])(?:[0-9DEFGJ]|H[A-Z])[0-9A-Z]{0,2}?(?<cap>18|24|30|36|42|48|60)(?:2[12]|[ST]B?21|S[24][1-4][SQ]\d)[A-Z]?"#) { p in
            let brands = switch p["brand"] {
            case "Y": ["York"]
            case "T": luxaireBrands
            default: colemanBrands
            }
            return info("Johnson Controls", brands, p["type"] == "H" ? .heatPump : .airConditioner, size: [tons(p["cap"])])
        },
        // Value lines: AC19B2421 (A = AC, H = heat pump; C Coleman, L Luxaire), AL6B024F3. Not coils (AC1A042A).
        ModelRule(#"(?<type>[AH])(?<brand>[CL])\d{1,2}[AB]0?(?<cap>18|24|30|36|42|48|60)(?:21|F\d)"#) { p in
            info("Johnson Controls", p["brand"] == "C" ? ["Coleman"] : Array(luxaireBrands.prefix(3)),
                 p["type"] == "H" ? .heatPump : .airConditioner, size: [tons(p["cap"])])
        },
        // Guardian and Evcon: RAC14L18B21, RAW14L18B21, GAW14L18C21S (air conditioners), RHP14318B21 (heat pump).
        ModelRule(#"[RG](?<type>AC|AW|HP)1[3-7][0-9L](?<cap>18|24|30|36|42|48|60)[A-Z]\d{2}[A-Z]?"#) { p in
            info("Johnson Controls", guardianBrands, p["type"] == "HP" ? .heatPump : .airConditioner, size: [tons(p["cap"])])
        },
        // Heat pumps from 2023: YH524E2S11, XH630E2S11, HH824E2S11, YDC36E2S11 (D = dual fuel), RH630E2S11.
        ModelRule(#"(?<brand>[YXHR])[HD](?:[5689]|[CV])(?<cap>18|24|30|36|42|48|60)E\d[A-Z]\d{2}[A-Z0-9]{0,2}"#) { p in
            let brands = switch p["brand"] {
            case "Y": ["York"]
            case "R": guardianBrands
            default: luxaireBrands + ["York", "Kenmore"] + guardianBrands
            }
            return info("Johnson Controls", brands, .heatPump, size: [tons(p["cap"])])
        },
        // York variable speed: YZT24B21S (Z = heat pump), YXV36B21S (X = air conditioner).
        ModelRule(#"Y(?<type>[ZX])[TV](?<cap>24|36|48|60)[A-Z0-9]{2,8}"#) { p in
            info("Johnson Controls", ["York"], p["type"] == "Z" ? .heatPump : .airConditioner, size: [tons(p["cap"])])
        },
        // Ductless heat pumps by Johnson Controls-Hitachi: RAC-DJ09WHAA, RAM-G18N2HAA, YRACDJ09WHAA (York, and Hitachi).
        ModelRule(#"(?<york>Y)?RA[CM]-?[A-Z]{1,2}(?<cap>09|12|15|18|24|30|36|42|48)[A-Z0-9]{3,6}"#) { p in
            info("Johnson Controls", p["york"] == nil ? ["Hitachi"] : ["York", "Hitachi"], .heatPump, size: [tons(p["cap"])])
        },
    ]
}
