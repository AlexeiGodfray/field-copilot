import FoundationModels

/// What kind of equipment a label belongs to.
@Generable
enum EquipmentKind: String, CaseIterable {
    case waterHeater, airConditioner, heatPump, airConditionerOrHeatPump, furnace, boiler, airHandler, evaporatorCoil,
         packagedUnit, solarInverter, solarPanel, battery, electricalPanel, transferSwitch, unknown

    var displayName: String {
        switch self {
        case .waterHeater: "Water heater"
        case .airConditioner: "Air conditioner"
        case .heatPump: "Heat pump"
        case .airConditionerOrHeatPump: "Air conditioner or heat pump"
        case .furnace: "Furnace"
        case .boiler: "Boiler"
        case .airHandler: "Air handler"
        case .evaporatorCoil: "Evaporator coil"
        case .packagedUnit: "Packaged unit"
        case .solarInverter: "Solar inverter"
        case .solarPanel: "Solar panel"
        case .battery: "Battery"
        case .electricalPanel: "Electrical panel"
        case .transferSwitch: "Transfer switch"
        case .unknown: "Unknown"
        }
    }
}

/// The key fields on an equipment label, in a standard format. Any of them can be missing.
@Generable
struct EquipmentLabel {
    @Guide(description: "Manufacturer as a company name in normal capitalization, e.g. Lennox, Carrier, Rheem, A. O. Smith. Empty if no brand is printed")
    var brand: String?

    @Guide(description: "Kind of equipment, judged from the whole label")
    var kind: EquipmentKind

    // Checked against the label in LabelRules.checkKind: a heat pump and an air conditioner have the same nameplate.
    @Guide(description: "Only for an air conditioner or heat pump: the words printed on the label that say whether it heats as well as cools (HEAT PUMP, HEATING, HSPF, DEFROST, REVERSING VALVE) or only cools (COOLING ONLY, AIR CONDITIONER), copied exactly. Empty if none of these words are printed")
    var typeEvidence: String?

    @Guide(description: "Only the value printed after MODEL, MODEL NO or M/N: no keyword, no spaces, same characters as printed")
    var model: String?

    @Guide(description: "Only the value printed after SERIAL, SERIAL NO or S/N: no keyword, no spaces, same characters as printed")
    var serial: String?

    @Guide(description: "Manufacture date as YYYY-MM, only if a date is printed next to MFD, MFG, MANUFACTURED or DATE. Otherwise empty")
    var manufactureDate: String?
}

/// Turns the text lines read off a label into its key fields, in a standard format, with Apple's
/// on-device language model. LabelRules checks the result before anything is shown.
enum LabelReader {
    static func read(_ lines: [TextLine]) async throws -> EquipmentLabel {
        let session = LanguageModelSession(instructions: """
            You read the text of English equipment nameplates (water heaters, air conditioners, heat pumps, \
            furnaces, solar inverters, batteries, electrical panels) and return the key fields in a standard format.
            The text comes from OCR, one numbered line per row. A keyword and its value can be on the same \
            line or on the next line.
            Never invent a value. Model and serial numbers must use exactly the characters printed. \
            If a field isn't in the text, leave it empty.
            """)
        let numbered = lines.enumerated().map { "\($0.offset + 1): \($0.element.text)" }.joined(separator: "\n")
        let prompt = "Here is the text read from an equipment nameplate, in English:\n\(numbered)"
        let response = try await session.respond(
            to: prompt,
            generating: EquipmentLabel.self,
            options: GenerationOptions(samplingMode: .greedy)  // same photo, same answer
        )
        return response.content
    }

    /// Why the language model can't run on this device, or nil if it can.
    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available: nil
        case .unavailable(.deviceNotEligible): "This device doesn't support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled): "Turn on Apple Intelligence in Settings."
        case .unavailable(.modelNotReady): "Apple Intelligence is still downloading. Try again shortly."
        case .unavailable: "Apple Intelligence isn't available."
        }
    }
}
