// Equipment database tests: how listed model numbers match printed ones, then lookups in the bundled
// database (FieldCopilot/Equipment.sqlite). The listed cases come from its lists, so a refresh that drops
// a model can fail them; pick another listed model when that happens.

import CoreGraphics
import Foundation

var databaseFailures = 0

func check(_ ok: Bool, _ what: String) {
    if !ok {
        databaseFailures += 1
        print("FAIL  \(what)")
    }
}

func expectListed(_ listing: String, _ printed: String, _ expected: Bool) {
    check(ListedModel(listing)?.matches(printed) == expected, "listing \(listing) vs printed \(printed): want \(expected)")
}

func expectLookup(_ model: String, _ kind: EquipmentKind?, brand: String? = nil, ratings: String? = nil) {
    let match = EquipmentDatabase.lookup(model)
    guard let kind else { return check(match == nil, "\(model) shouldn't be listed, matched \(match?.listing.model ?? "")") }
    guard let match else { return check(false, "\(model) should be listed") }
    check(match.listing.kind == kind, "\(model): type \(match.listing.kind?.rawValue ?? "none")")
    if let brand { check(match.brands.contains(brand), "\(model): brands \(match.brands)") }
    if let ratings { check(match.listing.ratings?.contains(ratings) == true, "\(model): ratings \(match.listing.ratings ?? "none")") }
}

/// Label text as OCR would return it, one line per string, stacked down the label.
func lines(_ texts: [String]) -> [TextLine] {
    texts.enumerated().map { TextLine(text: $1, box: CGRect(x: 0.1, y: 0.1 + Double($0) * 0.05, width: 0.5, height: 0.04)) }
}

func runDatabaseTests() {
    EquipmentDatabase.fileURL = URL(filePath: "FieldCopilot/Equipment.sqlite")
    check(EquipmentDatabase.allListings().count > 40000, "bundled database should load")

    // How listings are written.
    expectListed("SL22KLV-024-230A**", "SL22KLV-024-230A-01", true)
    expectListed("SL22KLV-024-230A**", "SL22KLV-024-230A", true)
    expectListed("SL22KLV-024-230A**", "SL22KLV-036-230A-01", false)
    expectListed("4TWV0048A1", "4TWV0048A1000AA", true)  // the listing leaves off the end
    expectListed("4TWV0048A1", "4TWV0036A1000AA", false)
    expectListed("(C,H,T)5H8T36*K*AAA*", "H5H8T36AKAAAA", true)
    expectListed("(C,H,T)5H8T36*K*AAA*", "N5H8T36AKAAAA", false)
    expectListed("PROPH50 T2 RH375-15", "PROPH50", true)  // the label's first part
    expectListed("PROPH50 T2 RH375-15", "PROPH50 T2 RH375-15", true)
    expectListed("PROPH50 T2 RH375-15", "PROPH50T2RH400", false)
    expectListed("CPRO H65 T2 RH310BM", "CPRO", false)  // too short to mean anything
    expectListed("37MURAQ48AA3+KSAIC0701230", "37MURAQ48AA3", true)  // add-on kit
    expectListed("MDV-V24WMN10T(B)", "MDV-V24WMN10T", true)
    expectListed("MDV-V24WMN10T(B)", "MDV-V24WMN10TB", true)
    expectListed("LD(V,H)036A", "LDV036A", true)
    expectListed("LD(V,H)036A", "LDX036A", false)
    expectListed("GXH18(5.3)FMK4DH-1", "GXH18FMK4DH-1", true)

    // Listed models, as printed on labels.
    let hp = EquipmentKind.heatPump
    expectLookup("RP14AZ36AJ2NA", hp, brand: "Ruud", ratings: "SEER2 15.2")
    expectLookup("SL22KLV-036-230A-01", hp, brand: "Lennox", ratings: "HSPF2")
    expectLookup("4TWV0048A1000AA", hp, brand: "Trane", ratings: "SEER2 19.5")
    expectLookup("H4H5S30AKAAA", hp, brand: "Heil")
    expectLookup("N5H5S24AKAAA", hp, brand: "Tempstar")  // listed as N5H5S24*K*AAA*: a * can be no character
    check(EquipmentDatabase.lookup("N5H5S24AKAAA")?.listing.maker == "ICP", "ICP units are listed under ICP, not Carrier")
    expectLookup("A97UH2E045B12SA", .furnace, brand: "AirEase", ratings: "97% AFUE")
    expectLookup("XE50T10HS45U0", .waterHeater, brand: "Rheem", ratings: "UEF 3.88")

    // Not listed: your labels (a Carrier air conditioner California only lists as 24ACA336A31, a 2013 heat pump,
    // a test model).
    for model in ["24ACA336A300", "13HPX-048-230-18", "XE50T10HD50U1"] {
        expectLookup(model, nil)
    }

    // Look-alike characters.
    let fix = EquipmentDatabase.correction("XE5OT10HS45U0")
    check(fix?.model == "XE50T10HS45U0" && fix?.change == "Changed O to 0", "XE5OT10HS45U0 → \(fix?.model ?? "nil")")
    check(EquipmentDatabase.correction("RP14AZ36AJZNA")?.model == "RP14AZ36AJ2NA", "RP14AZ36AJZNA should become RP14AZ36AJ2NA")
    check(EquipmentDatabase.correction("24ACA336P300") == nil, "P isn't a look-alike, and air conditioners aren't listed")
    check(EquipmentDatabase.correction("13HPX-048-230-18") == nil, "a correctly read unlisted model stays as is")

    // The whole rules pass on label text.
    var label = LabelRules.check(.empty, lines: lines(["RHEEM", "MODEL XE5OT10HS45U0", "SERIAL Q121912345"]))
    check(label.model.value == "XE50T10HS45U0", "label model \(label.model.value ?? "nil")")
    check(label.kind == .waterHeater, "label type \(label.kind)")
    check(EquipmentDatabase.describe(label)?.field.value == "UEF 3.88", "label ENERGY STAR row \(EquipmentDatabase.describe(label)?.field.value ?? "nil")")

    label = LabelRules.check(.empty, lines: lines(["MODEL 13HPX-048-230-18", "SERIAL 1913H18804"]))
    check(EquipmentDatabase.describe(label)?.field.value == "Not listed", "an unlisted heat pump says Not listed")

    label = LabelRules.check(.empty, lines: lines(["MODEL 24ACA336A300", "SERIAL 1107E27968"]))
    check(EquipmentDatabase.describe(label)?.title == "DOE", "an unlisted air conditioner says DOE doesn't list it")

    // DOE: every model certified to federal standards, ENERGY STAR or not.
    expectLookup("GSXH503610AA", .airConditioner, ratings: "SEER2")  // listed as GSXH503610A*
    check(EquipmentDatabase.lookup("GSXH503610AA")?.listing.product == "split system air conditioner",
          "GSXH5 is a split system AC, though Unico also certifies it with small-duct air handlers")
    expectLookup("CAPTA3626A4BA", .evaporatorCoil)  // a coil: DOE pairs it with furnaces
    expectLookup("AMST42CU1300BA", .airHandler)  // an air handler: DOE pairs it with no air mover
    expectLookup("MXZ-2C20NA4", .heatPump, brand: "Mitsubishi Electric", ratings: "HSPF2")
    expectLookup("10-40-DHPTA 2", .waterHeater, brand: "Reliance")
    check(EquipmentDatabase.lookup("10-40-DHPTA 2")?.listing.product == "heat pump water heater",
          "DOE files heat pump water heaters as electric storage; a UEF of 3.6 says heat pump")
    expectLookup("15B-095K", .boiler, brand: "Pennco Boilers", ratings: "84% AFUE")
    check(EquipmentDatabase.lookup("15B-095K")?.listing.product == "gas hot water boiler", "a gas boiler isn't read as oil")
    label = LabelRules.check(.empty, lines: lines(["MODEL S9B1B040D3PS", "SERIAL 21123ABCDE"]))
    check(label.kind == .furnace && EquipmentDatabase.describe(label)?.title == "DOE", "S9B1 furnace listed by DOE")
    check(EquipmentDatabase.describe(label)?.field.value == "92.1% AFUE", "S9B1 AFUE \(EquipmentDatabase.describe(label)?.field.value ?? "nil")")
    check(EquipmentDatabase.describe(label)?.field.note?.hasSuffix("Not on ENERGY STAR's list") == true,
          "a DOE furnace says it isn't on ENERGY STAR's list: \(EquipmentDatabase.describe(label)?.field.note ?? "nil")")

    // California's archive: models no longer sold, with when they were first listed.
    label = LabelRules.check(.empty, lines: lines(["MODEL R4A442GKB100", "SERIAL X172563114"]))  // your ICP label
    check(label.kind == .airConditioner && EquipmentDatabase.describe(label)?.title == "CEC archive", "R4A442 in California's archive")
    check(EquipmentDatabase.describe(label)?.field.note?.hasSuffix("No longer sold: first listed 2018") == true,
          "an archived model says when it was first listed: \(EquipmentDatabase.describe(label)?.field.note ?? "nil")")
    check(label.brand.value == "ICP", "the rules' brands win over the archive's Smart Comfort: \(label.brand.value ?? "nil")")
    expectLookup("589ANW042100", .packagedUnit, brand: "Payne")  // Bryant, Payne and Day & Night, 1994
    expectLookup("GKS90704CX", .furnace, ratings: "92.1% AFUE")
    expectLookup("4TCA4060A1", .packagedUnit)

    // California Energy Commission solar lists. Listings as printed on the lists, read as on labels.
    expectLookup("IQ8A-72-2-US", .solarInverter, brand: "Enphase", ratings: "97% CEC efficiency")
    expectLookup("NX11500T-US", .solarInverter, brand: "SolarEdge")
    expectLookup("1707000-21-M", .battery, brand: "Tesla")  // listed as 1707000-XX-Y: XX and Y are placeholders
    check(EquipmentDatabase.lookup("1707000-21-M")?.listing.product == "Powerwall 3 battery system with built-in solar inverter",
          "Powerwall 3 is a battery, though it's also on the inverter list")
    expectLookup("1538000-25-F", .solarInverter, brand: "Tesla")  // listed as 1538000-xx-y
    expectLookup("1807000-20-B", .battery, brand: "Tesla")
    // On the California lists a + is part of the name, so each wattage is its own listing.
    check(EquipmentDatabase.lookup("Q.TRON BLK M-G2.H+ 430")?.listing.specs == "430 W",
          "Qcells 430 W panel: \(EquipmentDatabase.lookup("Q.TRON BLK M-G2.H+ 430")?.listing.specs ?? "nil")")
    // Rheem's PRO+ is part of the name, not an add-on kit.
    expectLookup("PRO+G50-38U RU62", .waterHeater, brand: "Ruud")

    // Rule 12: no MODEL keyword, but a code on the label is a listed model.
    label = LabelRules.check(.empty, lines: lines(["ENPHASE ENERGY", "IQ8A-72-2-US", "240 V 60 HZ", "SN 482212345678"]))
    check(label.model.value == "IQ8A-72-2-US", "listed model found without a keyword: \(label.model.value ?? "nil")")
    check(label.kind == .solarInverter && label.brand.value == "Enphase", "found model's type and brand")
    label = LabelRules.check(EquipmentLabel(brand: nil, kind: .unknown, model: "482212345678", serial: nil, manufactureDate: nil),
                             lines: lines(["IQ8A-72-2-US", "482212345678"]))
    check(label.model.value == "IQ8A-72-2-US", "a listed model beats Apple Intelligence's pick: \(label.model.value ?? "nil")")
    label = LabelRules.check(.empty, lines: lines(["RATED 240 VAC", "CSA 5005998", "UL 1741"]))
    check(label.model.value == nil, "no listed model on the label: \(label.model.value ?? "nil")")

    // An ICP unit only ENERGY STAR knows (ductless) gets brand ICP, so its serial reads with ICP's format.
    label = LabelRules.check(.empty, lines: lines(["MODEL NO. D5CLHAH36AAK", "SERIAL NO. X172563114"]))
    check(label.brand.value == "ICP", "ICP ductless brand \(label.brand.value ?? "nil")")
    check(ManufactureAge.describe(label).value?.hasPrefix("Jun 2017") == true,
          "ICP ductless age \(ManufactureAge.describe(label).value ?? "nil")")

    print(databaseFailures == 0 ? "All database checks passed" : "\(databaseFailures) database check(s) FAILED")
}
