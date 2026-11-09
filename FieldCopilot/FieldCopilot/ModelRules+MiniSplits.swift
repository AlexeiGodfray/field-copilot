import Foundation

// Mini-split outdoor units: Mitsubishi Electric, Fujitsu, LG and Gree. Carrier's, ICP's and Daikin's are with their
// makers' rules, Nortek's and Johnson Controls' too.
// Sources: ENERGY STAR's and DOE's listings and California's archive (Nov 2026), where one letter splits every listed
// model: Mitsubishi's MUZ, SUZ, PUZ and MXZ are all heat pumps (503) and MUY and PUY all air conditioners (56);
// Fujitsu's AOU with R after the size heat pumps (29) and with C air conditioners (4); LG's LSU, LMU and LUU with H
// after the size heat pumps (30) and with C air conditioners (7); Gree's GWH outdoor units heat pumps.

extension ModelLookup {
    static let miniSplitRules: [ModelRule] = [
        // Mitsubishi Electric: MUZ-GL15NA (Z = heat pump, Y = air conditioner), MXZ-2C20NA (multi-zone), PUY-A12NKA.
        ModelRule(#"(?:[MSP]U|MX)(?<type>[YZ])-?[0-9A-Z]{1,3}?(?<cap>\d{2})N[A-Z0-9]{0,6}"#) { p in
            info("Mitsubishi Electric", ["Mitsubishi Electric"], p["type"] == "Z" ? .heatPump : .airConditioner, size: [tons(p["cap"])])
        },
        // Fujitsu: AOU12RLFF (R = heat pump), AOU12C1 (C = air conditioner).
        ModelRule(#"AOU(?<cap>\d{2})(?<type>[RC])[A-Z0-9]{1,8}"#) { p in
            info("Fujitsu", ["Fujitsu"], p["type"] == "R" ? .heatPump : .airConditioner, size: [tons(p["cap"])])
        },
        // LG: LSU090HSV5 (size 090, H = heat pump), LMU180HHV (multi-zone), LSU092CE (C = air conditioner).
        ModelRule(#"L(?:SU|MU|UU)(?<cap>\d{2})\d(?<type>[HC])[A-Z0-9]{1,5}"#) { p in
            info("LG", ["LG"], p["type"] == "H" ? .heatPump : .airConditioner, size: [tons(p["cap"])])
        },
        // Gree outdoor units: GWH12QC-D3DNA1A/O (H = heat pump, C = air conditioner). /I is the indoor unit.
        ModelRule(#"GW(?<type>[HC])(?<cap>09|12|18|24|30|36)[A-Z]{1,4}-[A-Z0-9]{4,10}/O"#) { p in
            info("Gree", ["Gree"], p["type"] == "H" ? .heatPump : .airConditioner, size: [tons(p["cap"])])
        },
    ]
}
