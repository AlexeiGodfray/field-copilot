// Tests for what the app shows under each value: a note only when it adds something (where a derived
// value came from, a confirmation, or what was changed), and nothing for a value read off the label.

import Foundation

var displayFailures = 0

func expectShown(_ got: String?, _ want: String?, _ what: String) {
    if got != want {
        displayFailures += 1
        print("FAIL  \(what): “\(got ?? "nil")” (want “\(want ?? "nil")”)")
    }
}

func runDisplayTests() {
    EquipmentDatabase.fileURL = URL(filePath: "FieldCopilot/Equipment.sqlite")

    // A clean read: no notes on what's printed, short notes on what's derived.
    var label = LabelRules.check(.empty, lines: lines(["MODEL 24ACA336A300", "SERIAL 1107E27968"]))
    expectShown(label.model.note, nil, "model read after its keyword")
    expectShown(label.serial.note, nil, "serial read after its keyword")
    expectShown(label.brand.note, "From the model number", "brand from the model number")
    expectShown(label.kindNote, "From the model number", "type from the model number")
    expectShown(ManufactureAge.describe(label).note, "From the serial: week 11, year 07 (Carrier format)", "age from the serial")

    // A model sold under several brands: the maker, and the brands it's sold as.
    label = LabelRules.check(.empty, lines: lines(["MODEL R4A442GKB100", "SERIAL X172563114"]))
    expectShown(label.brand.value, "ICP", "multi-brand value")
    expectShown(label.brand.note, "Sold as Heil, Tempstar, Comfortmaker, Arcoaire, KeepRite, Day & Night, Airquest, Kenmore, "
                + "Smart Comfort, or Maratherm. The label doesn't say which", "multi-brand note")

    // Apple Intelligence's values say so, keep the label's spacing, and its rejected answers are named.
    label = LabelRules.check(EquipmentLabel(brand: nil, kind: .unknown, model: "GS640YBRT", serial: nil, manufactureDate: nil),
                             lines: lines(["GS6 40 YBRT", "Q123456789"]))
    expectShown(label.model.value, "GS6 40 YBRT", "AI model keeps the printed spaces")
    expectShown(label.model.note, "Read by Apple Intelligence", "AI model note")
    label = LabelRules.check(EquipmentLabel(brand: nil, kind: .unknown, model: "SERTAL", serial: nil, manufactureDate: nil),
                             lines: lines(["MODEL 13HPX-048-230-18"]))
    expectShown(label.model.value, "13HPX-048-230-18", "printed model wins over a rejected AI answer")
    expectShown(label.model.note, "Apple Intelligence read “SERTAL”, but that's a keyword, not a value", "rejected AI answer")

    // Printed date checked against the serial; a type clue on the label.
    label = LabelRules.check(.empty, lines: lines(["RHEEM", "MODEL NO. XE50T10HS45U0", "SERIAL NO. Q121912345", "MFD 03/2019"]))
    expectShown(label.brand.note, nil, "brand printed on the label")
    expectShown(ManufactureAge.describe(label).note, "The serial agrees", "printed date the serial agrees with")
    expectShown(EquipmentDatabase.describe(label)?.field.note, "Certified heat pump water heater", "listing that reads like the model")
    expectShown(label.size, "50 gal · heat pump · 10-year warranty", "warranty in the specs")
    label = LabelRules.check(.empty, lines: lines(["HEAT PUMP", "MODEL ABC12345"]))
    expectShown(label.kindNote, "“HEAT PUMP” is printed on the label", "type from a clue")

    // Heat pump or air conditioner: Apple Intelligence's choice counts only with printed words that say which.
    let outdoor = ["MODEL ABC12345", "REFRIGERANT R-410A", "COMPRESSOR RLA 13.5"]
    var (kind, note) = LabelRules.checkKind(.airConditioner, evidence: nil, texts: outdoor)
    expectShown(kind.displayName, "Air conditioner or heat pump", "AI air conditioner without evidence")
    expectShown(note, "A compressor or refrigerant is listed on the label. Nothing printed says whether it also heats, and the model "
                + "number doesn't. Look for HEAT PUMP on the label or a reversing valve", "unsure type note")
    (kind, _) = LabelRules.checkKind(.airConditioner, evidence: "COMPRESSOR RLA 13.5", texts: outdoor)
    expectShown(kind.displayName, "Air conditioner or heat pump", "evidence that isn't a type word")
    (kind, _) = LabelRules.checkKind(.airConditioner, evidence: "SUB COOLING", texts: ["INDOOR TXV SUB COOLING"] + outdoor)
    expectShown(kind.displayName, "Air conditioner or heat pump", "sub cooling isn't cooling only")
    (kind, _) = LabelRules.checkKind(.heatPump, evidence: "HEATING CAPACITY", texts: outdoor)
    expectShown(kind.displayName, "Air conditioner or heat pump", "evidence that isn't printed")
    (kind, note) = LabelRules.checkKind(.heatPump, evidence: "HEATING CAPACITY", texts: ["HEATING CAPACITY 34000 BTUH"] + outdoor)
    expectShown(kind.displayName, "Heat pump", "AI heat pump with printed evidence")
    expectShown(note, "Read by Apple Intelligence from “HEATING CAPACITY” on the label", "evidence note")
    (kind, note) = LabelRules.checkKind(.airConditioner, texts: ["HSPF2 7.5"] + outdoor)
    expectShown(kind.displayName, "Heat pump", "heating rating clue")
    (kind, _) = LabelRules.checkKind(.unknown, texts: ["COOLING ONLY"] + outdoor)
    expectShown(kind.displayName, "Air conditioner", "cooling only clue")

    // ENERGY STAR: the listing when it reads differently, and brand spelling.
    label = LabelRules.check(.empty, lines: lines(["MODEL 4TWV0048A1000AA"]))
    expectShown(EquipmentDatabase.describe(label)?.field.note, "Certified split system heat pump, listed as 4TWV0048A1", "listing shorter than the model")
    let brands = EquipmentDatabase.lookup("SP15AZ48AJ2N")?.brands ?? []
    expectShown(brands.sorted().joined(separator: ", "), "Russell, Sure Comfort", "ENERGY STAR brands in our spelling")

    // A person's corrections win, and the rules work from them.
    let carrier = lines(["MODEL 24ACA336P300", "SERIAL 1107E27968"])  // OCR misread A as P
    label = LabelRules.check(.empty, lines: carrier, edits: LabelEdits(model: "24ACA336A300"))
    expectShown(label.model.value, "24ACA336A300", "corrected model")
    expectShown(label.model.note, "Changed by you from “24ACA336P300”", "corrected model note")
    expectShown(label.brand.value, "Carrier", "brand still from the corrected model")
    label = LabelRules.check(.empty, lines: carrier, edits: LabelEdits(model: "24aca336p300"))
    expectShown(label.model.note, nil, "the same code typed again isn't a change")

    let icp = lines(["MODEL R4A442GKB100", "SERIAL X172563114"])
    label = LabelRules.check(.empty, lines: icp, edits: LabelEdits(brand: "Arcoaire", kind: .heatPump))
    expectShown(label.brand.value, "Arcoaire", "brand picked by a person")
    expectShown(label.brand.note, "Changed by you from “ICP”", "picked brand note")
    expectShown(label.kindNote, "Changed by you from air conditioner", "changed type note")
    expectShown(ManufactureAge.describe(label, now: now).value, "Jun 2017 · 9 years old", "age still decodes with the picked brand")

    label = LabelRules.check(.empty, lines: icp, edits: LabelEdits(manufactureDate: "2016"))
    let made = ManufactureAge.describe(label, now: now)
    expectShown(made.value, "2016 · 10 years old", "date entered by a person, without the serial's month")
    expectShown(made.note, "Entered by you. The serial suggests Jun 2017 instead", "entered date note")

    label = LabelRules.check(.empty, lines: [], edits: LabelEdits(model: "XE5OT10HS45U0", serial: "Q121912345"))
    expectShown(label.model.value, "XE5OT10HS45U0", "a typed model isn't auto-corrected")
    expectShown(label.serial.note, "Entered by you", "entered serial note")

    let edits = LabelEdits(brand: "Heil", kind: .furnace, model: "N9MP1", serial: nil, manufactureDate: "2020-04")
    let roundTrip = try? JSONDecoder().decode(LabelEdits.self, from: JSONEncoder().encode(edits))
    expectShown(roundTrip == edits ? "same" : "different", "same", "edits save and load")

    print(displayFailures == 0 ? "All display checks passed" : "\(displayFailures) display check(s) FAILED")
}
