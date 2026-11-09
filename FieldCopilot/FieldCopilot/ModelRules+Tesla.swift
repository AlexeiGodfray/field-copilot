import Foundation

// Tesla Energy: Powerwall, Tesla Solar Inverter, Backup Gateway, Backup Switch.
// Sources: Tesla Powerhub "Device Identification" (part number → device type), Powerwall Emergency Response
// Guide Rev 1.1 and Rev 1.6 (Table 3, every Powerwall part number), Powerwall 3, Powerwall 3 Expansion,
// Powerwall+ and Powerwall 2 owner and install manuals and datasheets, Tesla Solar Inverter install manual
// and datasheet, Backup Switch datasheet, Powershare Gateway specifications; California Energy Commission
// energy storage, battery and inverter lists; Intertek authorization 104514208CRT-001; TÜV conformity
// letters; SunSpec certificate CS-000017.
//
// A part number is NNNNNNN-XX-Y: the 7-digit base names the product, XX is a "style code" that Tesla says
// has "no bearing on compliance", and Y is the hardware revision. Only the base is decoded, apart from
// Gateway 3 vs Powershare Gateway, which Tesla's documents tell apart by the second digit of XX. Other
// Tesla numbers in the same format (Megapack, Wall Connector, accessories, the "LABEL PN" printed on
// Powerwall 2 nameplates) aren't decoded, so they don't match.

extension ModelLookup {
    private static func tesla(_ kind: EquipmentKind, _ specs: String?...) -> ModelInfo {
        info("Tesla", ["Tesla"], kind, size: specs)
    }

    /// The product a part number's base names.
    private static func teslaProduct(base: String, style: String) -> ModelInfo? {
        switch base {
        case "1707000": tesla(.battery, "Powerwall 3", "13.5 kWh", "built-in solar inverter")
        case "1988000": tesla(.battery, "Powerwall 3P (three-phase)", "13.5 kWh", "built-in solar inverter")
        case "1807000": tesla(.battery, "Powerwall 3 Expansion", "13.5 kWh")
        case "1850000": tesla(.battery, "Powerwall+", "13.5 kWh", "built-in 7.6 kW solar inverter")
        // 2012170 and 3012170 are also the battery section of a Powerwall+.
        case "1092170", "2012170", "3012170": tesla(.battery, "Powerwall 2 AC", "13.5 kWh", "5 kW")
        case "1112170": tesla(.battery, "Powerwall 2 DC", "13.5 kWh")
        case "1050100": tesla(.battery, "Powerwall (first generation)", "7 kWh", "2 kW")
        case "1067000": tesla(.battery, "Powerwall (first generation)", "6.4 kWh", "3.3 kW")
        case "1068000": tesla(.battery, "Powerwall (first generation)", "10 kWh")
        // Configurable from 3.8 to 7.6 kW; also the solar section of a Powerwall+.
        case "1538000": tesla(.solarInverter, "Tesla Solar Inverter", "up to 7.6 kW")
        case "1534000": tesla(.solarInverter, "Tesla Solar Inverter", "3.8 kW")
        case "1099752": tesla(.transferSwitch, "Tesla Gateway (first generation, no backup)")
        case "1118431": tesla(.transferSwitch, "Backup Gateway (first generation)")
        case "1232100": tesla(.transferSwitch, "Backup Gateway 2", "North America")
        case "1152100": tesla(.transferSwitch, "Backup Gateway 2", "outside North America")
        case "1624171": tesla(.transferSwitch, "Backup Switch", "meter-socket transfer switch")
        case "1841000":
            switch style.last {
            case "1": tesla(.transferSwitch, "Gateway 3")
            case "2": tesla(.transferSwitch, "Powershare Gateway")
            default: nil
            }
        default: nil
        }
    }

    static let teslaRules: [ModelRule] = [
        // 1707000-21-M; Tesla's documents allow letters in the style code and a digit as the revision.
        ModelRule(#"(?<base>\d{7})-?(?<style>[0-9A-Z]{2})-?(?<revision>[A-Z0-9])"#) { p in
            teslaProduct(base: p["base"] ?? "", style: p["style"] ?? "")
        },
    ]
}
