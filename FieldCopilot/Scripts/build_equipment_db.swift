// Builds FieldCopilot/Equipment.sqlite, the equipment database the app ships with, from official lists:
//   ENERGY STAR (data.energystar.gov): certified heat pumps and their indoor units, light commercial HVAC
//     (residential-size central ACs and packaged units), furnaces, water heaters, boilers, geothermal heat pumps.
//   DOE's Compliance Certification Database (regulations.doe.gov/certification-data): every central AC and
//     heat pump with its indoor units, multi-split heat pump, furnace, boiler and water heater certified to
//     federal standards in the past year, ENERGY STAR or not.
//   California Energy Commission (solarequipment.energy.ca.gov): solar inverters, batteries, energy storage
//     systems and PV modules.
//   California Energy Commission's archive (energy.ca.gov/files/archived-appliance-lists): home central ACs,
//     furnaces and boilers listed from 1981 to 2023 and water heaters from 2019 to 2023, no longer sold.
// All are free and need no key. Each listing keeps its source, so the app can say where a value came from.
// The other lists only carry models sold today, so listings from the previous build that have dropped off them
// are kept, with the date they were last listed: the database grows into a history of every model it has seen.
//
// DOE's lists have no API, so download them first (see the README) into one folder. Then run this from the
// repository root with that folder, and rebuild the app:
//   swift FieldCopilot/Scripts/build_equipment_db.swift ~/Downloads/doe

import Foundation
import SQLite3

// Show progress as it happens, even when the output goes to a file.
setvbuf(stdout, nil, _IOLBF, 0)

let here = URL(filePath: #filePath).deletingLastPathComponent()
let output = here.appending(path: "../FieldCopilot/Equipment.sqlite").standardizedFileURL
let today = Date.now.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())

// MARK: Sources

struct Source {
    let id: Int
    let name: String
    let list: String
    let url: String
    var retrieved = today
}

let energyStar = "ENERGY STAR"
let cec = "California Energy Commission"
let doe = "DOE"

/// DOE's CSV exports are named for the product group and when they were downloaded:
/// "Furnaces_2026-10-29_14-59-7.csv". The newest of each group in the folder, and its date.
guard let doeFolder = CommandLine.arguments.dropFirst().first.map({ URL(filePath: NSString(string: $0).expandingTildeInPath) }) else {
    fatalError("Pass the folder of DOE's CSV exports: swift FieldCopilot/Scripts/build_equipment_db.swift ~/Downloads/doe")
}

func doeExport(_ group: String) -> (file: URL, date: String) {
    let prefix = group.replacingOccurrences(of: " ", with: "_") + "_"
    let files = (try? FileManager.default.contentsOfDirectory(at: doeFolder, includingPropertiesForKeys: nil)) ?? []
    let exports = files.compactMap { file -> (file: URL, date: String)? in
        let name = file.lastPathComponent
        guard name.hasPrefix(prefix), file.pathExtension == "csv",
              let date = name.dropFirst(prefix.count).firstMatch(of: #/^(\d{4}-\d{2}-\d{2})_/#) else { return nil }
        return (file, String(date.1))
    }
    guard let newest = exports.max(by: { $0.file.lastPathComponent < $1.file.lastPathComponent }) else {
        fatalError("No export of DOE's “\(group)” list in \(doeFolder.path)")
    }
    return newest
}

let centralExport = doeExport("Air Conditioners and Heat Pumps - Central")
let multiSplitExport = doeExport("Air Conditioners and Heat Pumps - Central Multi-Split")
let furnaceExport = doeExport("Furnaces")
let waterHeaterExport = doeExport("Water Heaters")
let ccms = "https://www.regulations.doe.gov/certification-data/"
let cecArchive = "https://www.energy.ca.gov/files/archived-appliance-lists"
let sources = [
    Source(id: 1, name: energyStar, list: "certified heat pumps", url: "https://data.energystar.gov/resource/83eb-xbyy"),
    Source(id: 2, name: energyStar, list: "certified light commercial HVAC", url: "https://data.energystar.gov/resource/e4mh-a2u3"),
    Source(id: 3, name: energyStar, list: "certified furnaces", url: "https://data.energystar.gov/resource/i97v-e8au"),
    Source(id: 4, name: energyStar, list: "certified water heaters", url: "https://data.energystar.gov/resource/pbpq-swnu"),
    Source(id: 5, name: energyStar, list: "certified boilers", url: "https://data.energystar.gov/resource/6rww-hpns"),
    Source(id: 6, name: energyStar, list: "certified geothermal heat pumps", url: "https://data.energystar.gov/resource/acvd-5wvz"),
    Source(id: 7, name: cec, list: "solar inverter list",
           url: "https://solarequipment.energy.ca.gov/Home/DownloadtoExcel?filename=InvertersList"),
    Source(id: 8, name: cec, list: "battery list",
           url: "https://solarequipment.energy.ca.gov/Home/DownloadtoExcel?filename=BatteryList"),
    Source(id: 9, name: cec, list: "energy storage system list",
           url: "https://solarequipment.energy.ca.gov/Home/DownloadtoExcel?filename=EnergyStorage"),
    Source(id: 10, name: cec, list: "PV module list",
           url: "https://solarequipment.energy.ca.gov/Home/DownloadtoExcel?filename=PVModuleList"),
    Source(id: 11, name: doe, list: "certified central air conditioners and heat pumps", url: ccms, retrieved: centralExport.date),
    Source(id: 12, name: doe, list: "certified multi-split heat pumps", url: ccms, retrieved: multiSplitExport.date),
    Source(id: 13, name: doe, list: "certified furnaces and boilers", url: ccms, retrieved: furnaceExport.date),
    Source(id: 14, name: doe, list: "certified water heaters", url: ccms, retrieved: waterHeaterExport.date),
    Source(id: 15, name: cec, list: "archive of central air conditioners", url: "\(cecArchive)?fid=9217"),
    Source(id: 16, name: cec, list: "archive of central air conditioners and heat pumps, 2023", url: "\(cecArchive)?fid=9218"),
    Source(id: 17, name: cec, list: "archive of furnaces", url: "\(cecArchive)?fid=9225"),
    Source(id: 18, name: cec, list: "archive of boilers", url: "\(cecArchive)?fid=9225"),
    Source(id: 19, name: cec, list: "archive of water heaters", url: "\(cecArchive)?fid=9231"),
]

/// The archive's files: their download IDs on the archive page and names, by source.
let archiveFiles: [(source: Int, id: Int, name: String)] = [
    (15, 9235, "SmallAir-CooledAirCo._1982-2023_ada.xlsx"),
    (16, 9238, "CentralACsAndHPs(OtherThanMultiSplit)M1_2023_ada.xlsx"),
    (17, 9277, "Furnaces_1981-1990_ada.xlsx"), (17, 9279, "Furnaces_1990-1999_ada.xlsx"), (17, 9280, "Furnaces_2000-2009_ada.xlsx"),
    (17, 9281, "Furnaces_2010-2014_ada.xlsx"), (17, 9282, "Furnaces_2015-2017_ada.xlsx"), (17, 9283, "Furnaces_2018_ada.xlsx"),
    (17, 9284, "Furnaces_2019_ada.xlsx"), (17, 9285, "Furnaces_2020_ada.xlsx"), (17, 9286, "Furnaces_2021_ada.xlsx"),
    (17, 9287, "Furnaces_2022_ada.xlsx"), (17, 9288, "Furnaces_2023_ada.xlsx"),
    (18, 9278, "Boilers_Thru2023_ada_csv.xlsx"),
    (19, 9323, "ResidentialWaterHeaters_2019-2023_ada.xlsx"),
]

// MARK: Names

/// Brand names as the app shows them. The lists' spelling varies by partner.
let brandNames: [String: String] = [
    "BRYANTHEATINGANDCOOLINGSYSTEMS": "Bryant", "KEEPRITE": "KeepRite", "AIREASE": "AirEase", "DAYNIGHT": "Day & Night",
    "SMARTCOMFORT": "Smart Comfort", "WEATHERMAKER": "WeatherMaker", "MAINLINE": "Mainline", "AOSMITH": "A. O. Smith",
    "ARMSTRONGAIR": "Armstrong Air", "RHEEM": "Rheem", "RUUD": "Ruud", "GOODMAN": "Goodman", "AMANA": "Amana",
    "DAIKIN": "Daikin", "CARRIER": "Carrier", "BRYANT": "Bryant", "PAYNE": "Payne", "LENNOX": "Lennox", "TRANE": "Trane",
    "AMERICANSTANDARD": "American Standard", "HEIL": "Heil", "TEMPSTAR": "Tempstar", "COMFORTMAKER": "Comfortmaker",
    "ARCOAIRE": "Arcoaire", "AIRQUEST": "Airquest", "KENMORE": "Kenmore", "YORK": "York", "BRADFORDWHITE": "Bradford White",
    "RINNAI": "Rinnai", "NAVIEN": "Navien", "STATE": "State", "AMERICAN": "American", "RICHMOND": "Richmond",
    "RELIANCEWATERHEATERS": "Reliance", "GSWWATERHEATERS": "GSW", "DUCANE": "Ducane", "CONCORD": "Concord",
    // Brands the model-number rules name, spelled the same way.
    "RUSSELL": "Russell", "BROCK": "Brock", "ECOTEMP": "Ecotemp", "MARATHERM": "Maratherm", "GRANDAIRE": "Grandaire",
    "SURE": "Sure Comfort", "SURECOMFORT": "Sure Comfort", "ALLIED": "Allied", "ALLIEDCOMMERCIAL": "Allied Commercial",
    "FRIEDRICH": "Friedrich", "FUJITSU": "Fujitsu", "WHIRLPOOL": "Whirlpool", "THERMALZONE": "Thermal Zone",
    "RUNTRU": "RunTru", "AMERISTAR": "Ameristar", "WEATHERKING": "WeatherKing", "GE": "GE",
    // Solar and storage makers, shown by their common names.
    "TESLA": "Tesla", "ENPHASEENERGY": "Enphase", "SOLAREDGETECHNOLOGIES": "SolarEdge", "GENERAC": "Generac",
    "GENERACPOWERSYSTEMS": "Generac", "SMAAMERICA": "SMA", "FRONIUSUSA": "Fronius", "LGENERGYSOLUTION": "LG",
    "HANWHAQCELLS": "Qcells", "HANWHAQCELLSAMERICA": "Qcells", "QCELLSNORTHAMERICA": "Qcells", "REC": "REC", "RECSOLARPTE": "REC",
    "SUNPOWER": "SunPower", "MAXEONSOLARTECHNOLOGIES": "Maxeon", "CANADIANSOLAR": "Canadian Solar",
    "JINKOSOLAR": "JinkoSolar", "LONGIGREENENERGYTECHNOLOGY": "LONGi", "TRINASOLAR": "Trina Solar", "JASOLAR": "JA Solar",
    "PANASONIC": "Panasonic", "SILFABSOLAR": "Silfab", "MISSIONSOLARENERGY": "Mission Solar", "SOLARIA": "Solaria",
    "FRANKLINWH": "FranklinWH", "FRANKLINWHENERGYSTORAGE": "FranklinWH", "SONNEN": "sonnen", "ELECTRIQPOWER": "Electriq Power",
    // Company names used as brands.
    "DAIKINCOMFORTTECHNOLOGIES": "Daikin", "BRYANTHEATINGCOOLINGSYSTEMS": "Bryant", "PAYNEHEATINGANDCOOLING": "Payne",
    "PAYNEHEATINGCOOLING": "Payne", "CARRIERCORPORATION": "Carrier", "LENNOXINDUSTRIES": "Lennox",
    "ICPCOMMERCIAL": "ICP Commercial",
    // California's archive spellings.
    "BRYANTAIRCONDITIONING": "Bryant", "CARRIERAIRCONDITIONING": "Carrier", "RHEEMSALESCO": "Rheem", "SEARSROEBUCKCO": "Sears",
    "JANITROLGMC": "Janitrol", "FRASERJOHNSTON": "Fraser-Johnston", "TRANEUNITARYPRODUCTSGROUP": "Trane", "ARMSTRONG": "Armstrong Air",
    "AOSMITHWATERPRODUCTS": "A. O. Smith", "BURNHAM": "Burnham",
]

func letters(_ text: String) -> String { text.uppercased().filter { $0.isLetter || $0.isNumber } }

/// "Heat Controller LLC" is Heat Controller, "York BY Johnson Controls" is York.
func brandName(_ listed: String) -> String {
    let trimmed = listed
        .replacing(#/(?i),?\s+(LLC|L\.L\.C\.|Inc\.?|Incorporated|Corp\.?|Corporation|Ltd\.?|Limited)$/#, with: "")
        .replacing(#/(?i)\s+by\s+.*$/#, with: "")
        .trimmingCharacters(in: .whitespaces)
    return brandNames[letters(trimmed)] ?? readable(trimmed)
}

/// "CHAMPION HEATING AND COOLING" reads as "Champion Heating and Cooling". A single all-caps word stays
/// as it is, since it's often the brand's own styling (MRCOOL, ACIQ).
func readable(_ name: String) -> String {
    let words = name.split(separator: " ").map(String.init)
    guard words.count > 1, name == name.uppercased() else { return name }
    return words.enumerated().map { index, word in
        if word.count <= 2 || ["HVAC", "AUX", "USA", "PV", "LG"].contains(word) || word.contains(where: \.isNumber) { return word }
        if index > 0, ["AND", "OF", "THE", "FOR"].contains(word) { return word.lowercased() }
        return word.prefix(1) + word.dropFirst().lowercased()
    }.joined(separator: " ")
}

/// Makers named the way the model-number rules name them.
let makerNames: [String: String] = [
    "Trane and American Standard Heating and Air Conditioning": "Trane",
    "International Comfort Products (ICP)": "ICP", "Rheem-Ruud": "Rheem",
    "Mitsubishi Electric U.S. HVAC Division": "Mitsubishi Electric", "GD MIDEA AIR-CONDITIONING EQUIPMENT CO., LTD.": "Midea",
    "First Co.": "First Co.",
    // California's archive names makers as they were then, and Carrier by plant: Indianapolis is ICP's.
    "Carrier Corp. - Indianapolis": "ICP", "International Comfort Products": "ICP", "Inter-City Products": "ICP",
    "Heil Quaker": "ICP", "Heil": "ICP", "BDP": "Carrier", "Trane U.S": "Trane", "Trane Unitary Products Group": "Trane",
    "Trane Unitary Products Group (Tyler, TX)": "Trane", "American Standard": "Trane", "Unitary Products Group": "Johnson Controls",
    "Luxaire": "Johnson Controls", "Evcon": "Johnson Controls", "Coleman": "Johnson Controls", "Rheem Sales": "Rheem",
    "Nordyne": "Nortek Global HVAC", "Intertherm": "Nortek Global HVAC", "Armstrong": "Allied Air", "Ducane": "Allied Air",
    "Amana Refrigeration": "Amana", "A.O. Smith Water Products": "A. O. Smith",
]

/// "Rheem Sales Company, Inc." is Rheem, "Carrier Corporation" is Carrier.
func makerName(_ partner: String) -> String {
    let short = partner
        .replacing(#/,\s+a\s.*/#, with: "")  // "GE Appliances, a Haier Company"
        .replacing(
            #/(?i),?\s+(Sales Company|Corporation|Corp\.?|Incorporated|Inc\.?|LLC|L\.L\.C\.|L\.P\.|Co\.?,?\s?Ltd\.?|Ltd\.?|Limited|Co\b\.?|Company|Enterprises|Manufacturing|International|Industries|Pte\.?|GmbH|S\.?A\.?|AG)(?:\b|\s|$).*/#,
            with: "")
        .trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ",.")))
    let name = makerNames[partner] ?? makerNames[short] ?? brandName(short.isEmpty ? partner : short)
    return name.replacing(#/\s*\([^)]*\)$/#, with: "")  // "Hanwha Qcells (Qidong)"
}

// MARK: Numbers

func number(_ text: String?, digits: Int = 2) -> String? {
    guard let value = text.flatMap({ Double($0.trimmingCharacters(in: .whitespaces)) }), value > 0 else { return nil }
    return value.formatted(.number.precision(.fractionLength(0...digits)))
}

func range(_ name: String, _ low: String?, _ high: String?) -> String? {
    guard let low = number(low), let high = number(high ?? low) else { return nil }
    return low == high ? "\(name) \(low)" : "\(name) \(low)–\(high)"
}

/// "rated 34,200 BTU/h cooling", from ENERGY STAR's rated capacity (often below the nominal size).
func coolingCapacity(_ low: String?, _ high: String?, thousands: Bool = false) -> String? {
    let scale = thousands ? 1000.0 : 1
    guard let lo = low.flatMap(Double.init).map({ $0 * scale }), lo > 0 else { return nil }
    let hi = high.flatMap(Double.init).map { $0 * scale } ?? lo
    let format = { (value: Double) in Int(value.rounded()).formatted() }
    return lo == hi ? "rated \(format(lo)) BTU/h cooling" : "rated \(format(lo))–\(format(hi)) BTU/h cooling"
}

func joined(_ parts: String?...) -> String? {
    let text = parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    return text.isEmpty ? nil : text
}

// MARK: Listings

struct Listing {
    let source: Int
    let model: String
    /// As the list writes it, before a leading choice is split: "(C,H,T)4H5S30*K*AAA*".
    var listedAs: String
    var brands: [String]
    var maker: String
    let kind: String?
    let product: String
    var specs: String?
    var ratings: String?
    /// When it was last on its list, for a listing kept from an earlier build. Nil when it's on the list now.
    var lastListed: String? = nil
    /// When it was first listed, for the lists that say: California's archive.
    var firstListed: String? = nil
}

/// Listings keyed by source and model number, merging rows that differ only in brand.
var listings: [String: Listing] = [:]
var order: [String] = []

/// With no brand, the maker is the brand, unless `makerIsBrand` is false: then the list names no brand.
func add(source: Int, model rawModel: String?, brand: String?, maker partner: String?, kind: String?, product: String,
         specs: String? = nil, ratings: String? = nil, makerIsBrand: Bool = true, firstListed: String? = nil) {
    // A part in curly brackets isn't part of the model number ("PVI-3.0-OUTD-S-US-A {208V}").
    guard let model = rawModel?.replacing(#/\s*\{[^}]*\}\s*$/#, with: "").trimmingCharacters(in: .whitespacesAndNewlines),
          letters(model).count >= 5 else { return }
    for model in expandingLeadingChoice(model) {
        let key = "\(source)|\(model.uppercased())"
        let brand = brand.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : brandName($0) }
        if var listing = listings[key] {
            if let brand, !listing.brands.contains(where: { letters($0) == letters(brand) }) { listing.brands.append(brand) }
            // A choice listing's brands are for the whole group, so keep that it came from one.
            if model != rawModelText(rawModel) { listing.listedAs = rawModelText(rawModel) }
            if listing.specs == nil { listing.specs = specs }
            if listing.ratings == nil { listing.ratings = ratings }
            if let firstListed { listing.firstListed = min(listing.firstListed ?? firstListed, firstListed) }
            listings[key] = listing
        } else {
            let maker = makerName(partner ?? brand ?? "")
            listings[key] = Listing(source: source, model: model, listedAs: rawModelText(rawModel),
                                    brands: brand.map { [$0] } ?? (makerIsBrand ? [maker] : []), maker: maker,
                                    kind: kind, product: product, specs: specs, ratings: ratings, firstListed: firstListed)
            order.append(key)
        }
    }
}

func rawModelText(_ model: String?) -> String {
    (model ?? "").replacing(#/\s*\{[^}]*\}\s*$/#, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
}

/// "(C,H,T)4H5S30*K*AAA*" is three listings, so each can be found by its first characters.
func expandingLeadingChoice(_ model: String) -> [String] {
    guard let open = model.first, "([".contains(open), let close = model.firstIndex(of: open == "(" ? ")" : "]") else { return [model] }
    let choices = model[model.index(after: model.startIndex)..<close].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    let rest = model[model.index(after: close)...]
    return choices.count > 1 ? choices.map { $0 + rest } : [model]
}

/// The first three letters and digits, the index the app looks listings up by. Empty when a wildcard,
/// choice or placeholder comes first, so the listing is always a candidate. Same rules as the app's ListedModel.
func indexKey(_ model: String) -> String {
    var key = ""
    let marked = model.replacing(#/([-\s])([XxYy]{1,3})(?=[-\s]|$)/#) { $0.output.1 + String(repeating: "*", count: $0.output.2.count) }
    for character in marked.uppercased().prefix(while: { $0 != "+" }) {
        if character.isLetter || character.isNumber {
            key.append(character)
            if key.count == 3 { return key }
        } else if "*#([".contains(character) {
            return ""
        }
    }
    return ""
}

// MARK: ENERGY STAR

/// Every row of a query, 50,000 at a time.
func energyStarRows(_ dataset: String, _ query: [String: String]) async throws -> [[String: String]] {
    var all: [[String: String]] = []
    while true {
        var url = URLComponents(string: "https://data.energystar.gov/resource/\(dataset).json")!
        url.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
            + [URLQueryItem(name: "$limit", value: "50000"), URLQueryItem(name: "$offset", value: String(all.count))]
        let (data, response) = try await URLSession.shared.data(from: url.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse, userInfo: [NSURLErrorFailingURLStringErrorKey: url.string ?? dataset])
        }
        let page = try JSONDecoder().decode([[String: String]].self, from: data)
        all += page
        if page.count < 50000 { return all }
    }
}

func refrigerant(_ text: String?) -> String? {
    guard let text, text.hasPrefix("R-") else { return nil }
    return text
}

print("ENERGY STAR heat pumps…")
// One row per outdoor and indoor pairing, so ratings and capacity are ranges over pairings.
for row in try await energyStarRows("83eb-xbyy", [
    "$select": "model_number, outdoor_unit_brand_name, energy_star_partner, product_type, refrigerant_type, "
        + "min(seer2_btu_wh) as seer2_lo, max(seer2_btu_wh) as seer2_hi, min(eer2_btu_wh) as eer2_lo, max(eer2_btu_wh) as eer2_hi, "
        + "min(hspf2_btu_wh) as hspf2_lo, max(hspf2_btu_wh) as hspf2_hi, "
        + "min(cooling_capacity_btu_h) as cap_lo, max(cooling_capacity_btu_h) as cap_hi",
    "$group": "model_number, outdoor_unit_brand_name, energy_star_partner, product_type, refrigerant_type",
    "$order": "model_number, outdoor_unit_brand_name",
]) {
    let (kind, product) = switch row["product_type"] {
    case "HP - Single Package": ("packagedUnit", "packaged heat pump")
    case "HP - Mini or Multi Split": ("heatPump", "mini-split heat pump")
    default: ("heatPump", "split system heat pump")
    }
    add(source: 1, model: row["model_number"], brand: row["outdoor_unit_brand_name"], maker: row["energy_star_partner"],
        kind: kind, product: product,
        specs: joined(coolingCapacity(row["cap_lo"], row["cap_hi"]), refrigerant(row["refrigerant_type"])),
        ratings: joined(range("SEER2", row["seer2_lo"], row["seer2_hi"]), range("EER2", row["eer2_lo"], row["eer2_hi"]),
                        range("HSPF2", row["hspf2_lo"], row["hspf2_hi"])))
}
// Indoor units: the listing says which outdoor units they pair with, not whether each is a coil or an air handler.
// Its brand is often blank, and the maker (Rheem) isn't the brand (Sure Comfort), so then no brand is kept.
for row in try await energyStarRows("83eb-xbyy", [
    "$select": "indoor_unit_model_number, indoor_unit_brand_name, energy_star_partner, product_type",
    "$group": "indoor_unit_model_number, indoor_unit_brand_name, energy_star_partner, product_type",
    "$where": "indoor_unit_model_number IS NOT NULL",
]) {
    let mini = row["product_type"] == "HP - Mini or Multi Split"
    add(source: 1, model: row["indoor_unit_model_number"], brand: row["indoor_unit_brand_name"], maker: row["energy_star_partner"],
        kind: nil, product: mini ? "mini-split indoor unit" : "indoor unit (coil or air handler) for a heat pump", makerIsBrand: false)
}

print("ENERGY STAR light commercial HVAC…")
for row in try await energyStarRows("e4mh-a2u3", [
    "$select": "model_number, brand_name, energy_star_partner, type, split_system_or_single_package, refrigerant_type, "
        + "min(seer2_rating_btu_wh) as seer2_lo, max(seer2_rating_btu_wh) as seer2_hi, "
        + "min(eer2_rating_btu_wh) as eer2_lo, max(eer2_rating_btu_wh) as eer2_hi, "
        + "min(hspf2_rating_btu_wh) as hspf2_lo, max(hspf2_rating_btu_wh) as hspf2_hi, "
        + "min(cooling_capacity_kbtu_h) as cap_lo, max(cooling_capacity_kbtu_h) as cap_hi",
    "$group": "model_number, brand_name, energy_star_partner, type, split_system_or_single_package, refrigerant_type",
    "$order": "model_number, brand_name",
]) {
    let heatPump = (row["type"] ?? "").hasSuffix("HP")
    let packaged = row["split_system_or_single_package"] == "Packaged"
    let kind = packaged ? "packagedUnit" : heatPump ? "heatPump" : "airConditioner"
    let product = (packaged ? "packaged " : "split system ") + (heatPump ? "heat pump" : "air conditioner")
    add(source: 2, model: row["model_number"], brand: row["brand_name"], maker: row["energy_star_partner"],
        kind: kind, product: product,
        specs: joined(coolingCapacity(row["cap_lo"], row["cap_hi"], thousands: true), refrigerant(row["refrigerant_type"])),
        ratings: joined(range("SEER2", row["seer2_lo"], row["seer2_hi"]), range("EER2", row["eer2_lo"], row["eer2_hi"]),
                        range("HSPF2", row["hspf2_lo"], row["hspf2_hi"])))
}
for row in try await energyStarRows("e4mh-a2u3", [
    "$select": "indoor_unit_model_number, brand_name, energy_star_partner",
    "$group": "indoor_unit_model_number, brand_name, energy_star_partner",
    "$where": "indoor_unit_model_number IS NOT NULL",
]) {
    add(source: 2, model: row["indoor_unit_model_number"], brand: nil, maker: row["energy_star_partner"],
        kind: nil, product: "indoor unit (coil or air handler) for an air conditioner", makerIsBrand: false)
}

print("ENERGY STAR furnaces…")
for row in try await energyStarRows("i97v-e8au", [
    "$select": "model_number, brand_name, energy_star_partner, efficiency_afue, fuel_type",
    "$order": "model_number, brand_name",
]) {
    let fuel = (row["fuel_type"] ?? "").contains("Oil") ? "oil" : "gas"
    add(source: 3, model: row["model_number"], brand: row["brand_name"], maker: row["energy_star_partner"], kind: "furnace",
        product: "\(fuel) furnace", ratings: number(row["efficiency_afue"], digits: 1).map { "\($0)% AFUE" })
}

print("ENERGY STAR water heaters…")
for row in try await energyStarRows("pbpq-swnu", [
    "$select": "model_number, brand_name, energy_star_partner, type, uniform_energy_factor_uef, storage_volume_gallons",
    "$order": "model_number, brand_name",
]) {
    let product = switch row["type"] {
    case "Hybrid/Electric Heat Pump": "heat pump water heater"
    case "Gas Tankless": "tankless gas water heater"
    case "Gas Storage": "gas water heater"
    case "Gas-fired Storage Residential-duty Commercial": "commercial-duty gas water heater"
    case "Solar with Electric Backup": "solar water heater with electric backup"
    case "Solar with Gas Backup": "solar water heater with gas backup"
    case let other?: other.lowercased()
    case nil: "water heater"
    }
    add(source: 4, model: row["model_number"], brand: row["brand_name"], maker: row["energy_star_partner"], kind: "waterHeater",
        product: product, specs: number(row["storage_volume_gallons"], digits: 0).map { "\($0) gal" },
        ratings: number(row["uniform_energy_factor_uef"]).map { "UEF \($0)" })
}

print("ENERGY STAR boilers…")
for row in try await energyStarRows("6rww-hpns", [
    "$select": "model_number, brand_name, energy_star_partner, efficiency_afue, fuel_type",
    "$order": "model_number, brand_name",
]) {
    let fuel = (row["fuel_type"] ?? "").contains("Oil") ? "oil" : "gas"
    add(source: 5, model: row["model_number"], brand: row["brand_name"], maker: row["energy_star_partner"], kind: "boiler",
        product: "\(fuel) boiler", ratings: number(row["efficiency_afue"], digits: 1).map { "\($0)% AFUE" })
}

print("ENERGY STAR geothermal heat pumps…")
for row in try await energyStarRows("acvd-5wvz", [
    "$select": "model_number, brand_name, energy_star_partner, product_type, cop_rating, eer_rating, refrigerant_type",
    "$order": "model_number, brand_name",
]) {
    add(source: 6, model: row["model_number"], brand: row["brand_name"], maker: row["energy_star_partner"], kind: "heatPump",
        product: "geothermal heat pump (\((row["product_type"] ?? "").lowercased()))",
        specs: refrigerant(row["refrigerant_type"]),
        ratings: joined(number(row["cop_rating"]).map { "COP \($0)" }, number(row["eer_rating"]).map { "EER \($0)" }))
}

// MARK: California Energy Commission

/// The rows of an Excel file's first sheet, as column letter → text, after the header row that starts
/// with "Manufacturer" and the units row under it.
func excelRows(_ url: String) async throws -> [[String: String]] {
    let (data, response) = try await URLSession.shared.data(from: URL(string: url)!)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
    let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".xlsx")
    try data.write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    let shared = SheetParser.strings(try unzip(file, "xl/sharedStrings.xml"))
    let rows = SheetParser.rows(try unzip(file, "xl/worksheets/sheet1.xml"), shared: shared)
    guard let header = rows.firstIndex(where: { ($0["A"] ?? "").hasPrefix("Manufacturer") }) else { return [] }
    return Array(rows[(header + 2)...]).filter { !($0["A"] ?? "").isEmpty }
}

func unzip(_ file: URL, _ member: String) throws -> Data {
    try output(of: "/usr/bin/unzip", ["-p", file.path, member])
}

/// The names of the files in a zip file.
func zipMembers(_ file: URL) throws -> [String] {
    String(decoding: try output(of: "/usr/bin/zipinfo", ["-1", file.path]), as: UTF8.self).split(separator: "\n").map(String.init)
}

func output(of tool: String, _ arguments: [String]) throws -> Data {
    let process = Process()
    process.executableURL = URL(filePath: tool)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return data
}

/// Reads shared strings and sheet rows from the XML inside an .xlsx file, as column letter → text. Cells
/// that don't give their column are numbered in order.
final class SheetParser: NSObject, XMLParserDelegate {
    private var shared: [String] = []
    private var strings: [String] = []
    private var each: ([String: String]) -> Void = { _ in }
    private var row: [String: String] = [:]
    private var position = 0
    private var column = ""
    private var cellType = ""
    private var text = ""
    private var inText = false

    static func strings(_ data: Data) -> [String] {
        let parser = SheetParser()
        let xml = XMLParser(data: data)
        xml.delegate = parser
        xml.parse()
        return parser.strings
    }

    static func rows(_ data: Data, shared: [String]) -> [[String: String]] {
        var rows: [[String: String]] = []
        forEachRow(data, shared: shared) { rows.append($0) }
        return rows
    }

    /// Each row in turn, for sheets too big to hold as dictionaries.
    static func forEachRow(_ data: Data, shared: [String], _ each: @escaping ([String: String]) -> Void) {
        let parser = SheetParser()
        parser.shared = shared
        parser.each = each
        let xml = XMLParser(data: data)
        xml.delegate = parser
        xml.parse()
    }

    /// 0 is A, 26 is AA.
    static func columnName(_ index: Int) -> String {
        index < 26 ? String(UnicodeScalar(65 + index)!) : columnName(index / 26 - 1) + columnName(index % 26)
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        switch name {
        case "si": text = ""
        case "t", "v": inText = true
        case "row":
            row = [:]
            position = 0
        case "c":
            column = attributes["r"].map { String($0.prefix { $0.isLetter }) } ?? Self.columnName(position)
            position += 1
            cellType = attributes["t"] ?? ""
            text = ""
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText { text += string }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        switch name {
        case "t", "v": inText = false
        case "si": strings.append(text)
        case "c": row[column] = cellType == "s" ? Int(text).flatMap { shared.indices.contains($0) ? shared[$0] : nil } ?? "" : text
        case "row": each(row)
        default: break
        }
    }
}

print("CEC solar inverters…")
// One row per voltage; merged by model, with every voltage and the highest power and efficiency.
var inverters: [String: (maker: String, product: String, kilowatts: Double, volts: Set<Int>, efficiency: Double)] = [:]
let inverterRows = try await excelRows(sources[6].url)
let inverterMakers = inverterRows.compactMap { $0["A"] }
for row in inverterRows {
    guard let model = row["B"]?.replacing(#/\s*\{[^}]*\}\s*$/#, with: ""), let maker = row["A"] else { continue }
    let product = row["AB"] == "Y" ? "microinverter" : row["C"] == "Y" ? "hybrid inverter (solar and battery)" : "solar inverter"
    var entry = inverters[model] ?? (maker, product, 0, [], 0)
    entry.kilowatts = max(entry.kilowatts, Double(row["L"] ?? "") ?? 0)
    if let volts = Double(row["M"] ?? ""), volts > 0 { entry.volts.insert(Int(volts.rounded())) }
    entry.efficiency = max(entry.efficiency, Double(row["N"] ?? "") ?? 0)
    inverters[model] = entry
}
for (model, entry) in inverters.sorted(by: { $0.key < $1.key }) {
    let power = entry.kilowatts > 0
        ? entry.kilowatts < 1 ? "\(Int((entry.kilowatts * 1000).rounded())) W" : "\(number(String(entry.kilowatts))!) kW" : nil
    let volts = entry.volts.isEmpty ? nil : entry.volts.sorted().map(String.init).joined(separator: "/") + " V"
    add(source: 7, model: model, brand: nil, maker: entry.maker, kind: "solarInverter", product: entry.product,
        specs: joined(power, volts), ratings: number(String(entry.efficiency), digits: 1).map { "\($0)% CEC efficiency" })
}

/// The CEC lists' Brand column holds a real brand ("Fortress Power") or a product line ("Powerwall 3",
/// "IQ Battery 5P"). It's a brand when it's the maker's own short name or a company on the lists.
let cecBatteryRows = try await excelRows(sources[7].url)
let cecStorageRows = try await excelRows(sources[8].url)
let cecCompanies = Set((inverterMakers + cecBatteryRows.compactMap { $0["A"] } + cecStorageRows.compactMap { $0["A"] })
    .map { letters(makerName($0)) })

func brandOrLine(_ column: String?, maker: String?) -> (brand: String?, line: String?) {
    guard let column = column?.trimmingCharacters(in: .whitespaces), !column.isEmpty else { return (nil, nil) }
    let key = letters(column)
    if cecCompanies.contains(key) || letters(maker ?? "").hasPrefix(key) || brandNames[key] != nil { return (column, nil) }
    return (nil, column)
}

print("CEC batteries…")
for row in cecBatteryRows {
    let technology = (row["D"] ?? "").lowercased()
    let (brand, line) = brandOrLine(row["B"], maker: row["A"])
    add(source: 8, model: row["C"], brand: brand, maker: row["A"], kind: "battery",
        product: [line, technology.isEmpty ? "battery" : "\(technology) battery"].compactMap { $0 }.joined(separator: " "),
        specs: joined(number(row["I"]).map { "\($0) kWh" }, number(row["J"]).map { "\($0) kW" }),
        ratings: number(row["K"], digits: 1).map { "\($0)% round trip" })
}

print("CEC energy storage systems…")
for row in cecStorageRows {
    let (brand, line) = brandOrLine(row["B"], maker: row["A"])
    add(source: 9, model: row["C"], brand: brand, maker: row["A"], kind: "battery",
        product: [line, row["E"] == "Y" ? "battery system with built-in solar inverter" : "battery system"]
            .compactMap { $0 }.joined(separator: " "),
        specs: joined(number(row["Q"]).map { "\($0) kWh" }, number(row["R"]).map { "\($0) kW" }),
        ratings: number(row["AE"], digits: 1).map { "\($0)% round trip" })
}

print("CEC PV modules…")
for row in try await excelRows(sources[9].url) {
    let technology = (row["J"] ?? "").lowercased()
    add(source: 10, model: row["B"], brand: nil, maker: row["A"], kind: "solarPanel",
        product: technology.isEmpty ? "solar panel" : "\(technology) solar panel",
        specs: number(row["E"], digits: 0).map { "\($0) W" })
}

// ICP is part of Carrier, and ENERGY STAR files its units under Carrier. Name ICP when no Carrier brand
// sells the model, so the app reads its serial with ICP's format.
let carrierBrands: Set = ["CARRIER", "BRYANT", "PAYNE", "WEATHERMAKER", "BROCK"]
func nameICP() {
    for key in order where listings[key]!.maker == "Carrier" && !listings[key]!.brands.contains(where: { carrierBrands.contains(letters($0)) }) {
        listings[key]!.maker = "ICP"
    }
}
nameICP()

// MARK: DOE

// DOE lists no maker, only brands. A model ENERGY STAR also lists has ENERGY STAR's maker; otherwise a brand's
// maker is the one ENERGY STAR files most of that brand's models under, or the brand itself.
var energyStarMakers: [String: String] = [:]
var brandMakerCounts: [String: [String: Int]] = [:]
for key in order {
    let listing = listings[key]!
    guard (1...6).contains(listing.source), listing.kind != nil else { continue }
    energyStarMakers[listing.model.uppercased()] = energyStarMakers[listing.model.uppercased()] ?? listing.maker
    for brand in listing.brands { brandMakerCounts[letters(brand), default: [:]][listing.maker, default: 0] += 1 }
}
let brandMakers = brandMakerCounts.mapValues { $0.max { $0.value < $1.value }!.key }

func makerOfBrand(_ brand: String) -> String {
    brandMakers[letters(brandName(brand))] ?? brandName(brand)
}

/// DOE writes some choices its own way: "EA(C;U)1P49C" is EA(C,U)1P49C, and "H,GE35*48" and
/// "0,5,7,10MCE4-14-361*P" are a choice of first characters, (H,G)E35*48 and (0,5,7,10)MCE4-14-361*P.
/// Nil when another comma is left outside brackets, since then it can't be read as a model number.
func doeModel(_ text: String?) -> String? {
    guard var model = text?.replacingOccurrences(of: ";", with: ","), !model.isEmpty else { return nil }
    if let match = model.wholeMatch(of: #/((?:[A-Za-z0-9]{1,2},)+)([^,]+)/#) {
        let choices = match.1.split(separator: ",").map(String.init)
        let rest = String(match.2)
        let last = choices.allSatisfy { $0.allSatisfy(\.isNumber) } ? String(rest.prefix(while: \.isNumber)) : String(rest.prefix(1))
        guard !last.isEmpty else { return nil }
        model = "(\((choices + [last]).joined(separator: ",")))\(rest.dropFirst(last.count))"
    }
    return model.replacing(#/[\(\[][^\)\]]*[\)\]]/#, with: "").contains(",") ? nil : model
}

// The exports are loaded into a scratch database with the sqlite3 tool (the central AC export is a
// gigabyte), and read through views that give their long column names short ones.
let scratch = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".sqlite")
for (export, table) in [(centralExport, "central_csv"), (multiSplitExport, "multisplit_csv"), (furnaceExport, "furnaces_csv"),
                        (waterHeaterExport, "water_heaters_csv")] {
    print("Loading \(export.file.lastPathComponent)…")
    let process = Process()
    process.executableURL = URL(filePath: "/usr/bin/sqlite3")
    process.arguments = [scratch.path, ".import --csv \"\(export.file.path)\" \(table)"]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { fatalError("Couldn't load \(export.file.path)") }
}
var scratchDB: OpaquePointer?
guard sqlite3_open(scratch.path, &scratchDB) == SQLITE_OK else { fatalError("Can't open \(scratch.path)") }

/// A number column: empty is null.
func real(_ column: String) -> String { "CAST(NULLIF(\"\(column)\", '') AS REAL)" }

func scratchRows(_ sql: String) -> [[String: String]] { rows(of: scratchDB, sql) }

/// A query's rows as column name → text, leaving out empty values.
func rows(of database: OpaquePointer?, _ sql: String) -> [[String: String]] {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { fatalError(String(cString: sqlite3_errmsg(database))) }
    defer { sqlite3_finalize(statement) }
    var rows: [[String: String]] = []
    while sqlite3_step(statement) == SQLITE_ROW {
        var row: [String: String] = [:]
        for column in 0..<sqlite3_column_count(statement) {
            if let text = sqlite3_column_text(statement, column), text.pointee != 0 {
                row[String(cString: sqlite3_column_name(statement, column))] = String(cString: text)
            }
        }
        rows.append(row)
    }
    return rows
}

_ = scratchRows("""
    CREATE VIEW central AS SELECT
        "Brand_Name_s__s" AS brand, "Product_Group_Code_Description_s" AS type,
        "Individual_Model_Number_Covered_by_Basic_Model__Outdoor_Unit_or_Package_Unit__m" AS outdoor,
        "Individual_Model_Number__Indoor_Unit___If_Applicable_m" AS indoor,
        "Individual_Model_Number__Air_Mover_or_Indoor_Unit_if_Fan_is_part_of_Indoor_Unit___If_Applicable_m" AS mover,
        "Is_the_Efficiency_Based_on_a_System_Tested_without_an_Air_Mover__i_e___Coil_Only_System__or_a_System_Tested_with_an_Air_Mover__such_as_a_Furnace__i_e___a_Blower_Coil_System___s" AS system,
        \(real("Cooling_Capacity__Btu_h__d")) AS cooling, \(real("Seasonal_Energy_Efficiency_Ratio_2__SEER2__in_Btu_W_h_d")) AS seer2,
        \(real("Energy_Efficiency_Ratio_2__EER2__in_Btu_W_h_d")) AS eer2,
        \(real("Heating_Seasonal_Performance_Factor_2__HSPF2__in_Btu_W_h_d")) AS hspf2
    FROM central_csv
    """)
_ = scratchRows("""
    CREATE VIEW multisplit AS SELECT
        "Brand_Name__Outdoor_Unit__s" AS brand, "Individual_Model_Number_Covered_by_Basic_Model__Outdoor_Unit__m" AS outdoor,
        "All_Refrigerant_Types_Acceptable_for_Use_with_this_Rated_Combination__Optional__s" AS refrigerant,
        \(real("Cooling_Capacity__Btu_h__d")) AS cooling, \(real("Seasonal_Energy_Efficiency_Ratio_2__SEER2__in_Btu_W_h_d")) AS seer2,
        \(real("Energy_Efficiency_Ratio_2__EER2__in_Btu_W_h__If_Applicable_d")) AS eer2,
        \(real("For_Heat_Pumps_Only__Heating_Seasonal_Performance_Factor_2__HSPF2__in_Btu_W_h_d")) AS hspf2
    FROM multisplit_csv
    """)
// Up to five indoor units per pairing, each with its brand and type.
_ = scratchRows("CREATE VIEW multisplit_indoor AS " + (1...5).map { unit in
    let prefix = unit == 1 ? "Indoor_Unit_1___" : "Indoor_Unit_\(unit)__If_Applicable___"
    return "SELECT \"\(prefix)Individual_Model_Number_m\" AS model, \"\(prefix)Brand_s__s\" AS brand, \"\(prefix)Type_s\" AS type FROM multisplit_csv"
}.joined(separator: " UNION "))
_ = scratchRows("""
    CREATE VIEW furnaces AS SELECT
        "Brand_Name_s__s" AS brand, "Product_Group_Code_Description_s" AS type, "Individual_Model_Number_Covered_by_Basic_Model_m" AS model,
        \(real("Input_Capacity__BTU_Hour__d")) AS input, \(real("Annual_Fuel_Utilization_Efficiency_____d")) AS afue
    FROM furnaces_csv
    """)
_ = scratchRows("""
    CREATE VIEW water_heaters AS SELECT
        "Brand_Name_s__s" AS brand, "Type_of_Heater_s" AS type, "Individual_Model_Number_Covered_by_Basic_Model_m" AS model,
        \(real("Rated_Storage_Volume__gallons__d")) AS gallons, \(real("Uniform_Energy_Factor__UEF__d")) AS uef,
        \(real("Maximum_Gallons_Per_Minute_d")) AS gpm
    FROM water_heaters_csv
    """)

/// "Single-split-system heat pumps", "Single-package air conditioners (other than space-constrained)".
func centralProduct(_ type: String?) -> (kind: String, product: String) {
    let text = (type ?? "").lowercased()
    let what = text.contains("heat pump") ? "heat pump" : "air conditioner"
    let kind = what == "heat pump" ? "heatPump" : "airConditioner"
    let constrained = text.contains("space-constrained") && !text.contains("other than space-constrained")
    if text.hasPrefix("single-package") { return ("packagedUnit", constrained ? "space-constrained packaged \(what)" : "packaged \(what)") }
    if text.contains("small-duct") { return (kind, "small-duct high-velocity \(what)") }
    return (kind, constrained ? "space-constrained split system \(what)" : "split system \(what)")
}

func ratings(_ row: [String: String]) -> String? {
    joined(range("SEER2", row["seer2_lo"], row["seer2_hi"]), range("EER2", row["eer2_lo"], row["eer2_hi"]),
           range("HSPF2", row["hspf2_lo"], row["hspf2_hi"]))
}

print("DOE central air conditioners and heat pumps…")
// One row per outdoor, indoor and air mover pairing, so ratings and capacity are ranges over pairings. The
// brand is whoever certified the pairing, often a coil maker (ADP, Aspen, Mortex) pairing its coil with
// another maker's outdoor unit, so outdoor units keep no brand from DOE.
let ranges = """
    min(cooling) AS cap_lo, max(cooling) AS cap_hi, min(seer2) AS seer2_lo, max(seer2) AS seer2_hi,
    min(eer2) AS eer2_lo, max(eer2) AS eer2_hi, min(hspf2) AS hspf2_lo, max(hspf2) AS hspf2_hi
    """
// Its type is the one most of its pairings have: Unico certifies GSXH5 air conditioners with its small-duct air
// handlers as small-duct high-velocity systems. (SQLite takes a bare column from the row with the max.)
for row in scratchRows("""
    SELECT * FROM (SELECT outdoor, \(ranges) FROM central WHERE outdoor != '' GROUP BY outdoor)
    JOIN (SELECT outdoor, type, max(n) FROM (SELECT outdoor, type, count(*) AS n FROM central WHERE outdoor != '' GROUP BY outdoor, type)
          GROUP BY outdoor) USING (outdoor)
    ORDER BY outdoor
    """) {
    guard let outdoor = row["outdoor"], let model = doeModel(outdoor) else { continue }
    let (kind, product) = centralProduct(row["type"])
    add(source: 11, model: model, brand: nil, maker: energyStarMakers[outdoor.uppercased()] ?? "", kind: kind, product: product,
        specs: coolingCapacity(row["cap_lo"], row["cap_hi"]), ratings: ratings(row), makerIsBrand: false)
}

// Indoor units, without add-on kits (+TXV): a coil when tested without an air mover or with a separate one (a
// furnace), an air handler when tested with its own fan. A kit can be the fan (CAPEA3022*3A*+MBVK12BP1X00A*
// is a coil with a blower module), so only a pairing without one shows an air handler. Whoever certified the
// pairing may have made the outdoor unit instead, so no brand or maker is kept.
let indoorRows = scratchRows("""
    SELECT indoor,
        sum(system = 'Coil-Only' OR (mover != '' AND mover != indoor)) AS coil,
        sum(system = 'Blower-Coil' AND (mover = '' OR mover = indoor)) AS fan
    FROM central WHERE indoor != '' GROUP BY indoor
    """)
let indoorUnits = Dictionary(grouping: indoorRows) { $0["indoor"]!.prefix { $0 != "+" }.trimmingCharacters(in: .whitespaces) }
for (indoor, rows) in indoorUnits.sorted(by: { $0.key < $1.key }) {
    guard let model = doeModel(indoor) else { continue }
    let coil = rows.reduce(0) { $0 + (Int($1["coil"] ?? "") ?? 0) }
    let handler = rows.filter { !$0["indoor"]!.contains("+") }.reduce(0) { $0 + (Int($1["fan"] ?? "") ?? 0) }
    // Nine in ten pairings must agree.
    let (kind, product): (String?, String) =
        coil > 0 && coil * 10 >= (coil + handler) * 9 ? ("evaporatorCoil", "evaporator coil")
        : handler > 0 && handler * 10 >= (coil + handler) * 9 ? ("airHandler", "air handler")
        : (nil, "indoor unit (coil or air handler)")
    add(source: 11, model: model, brand: nil, maker: "", kind: kind, product: product, makerIsBrand: false)
}

print("DOE multi-split heat pumps…")
for row in scratchRows("""
    SELECT outdoor, brand, max(refrigerant) AS refrigerant, \(ranges) FROM multisplit WHERE outdoor != '' GROUP BY outdoor, brand
    """) {
    guard let model = doeModel(row["outdoor"]), let brand = row["brand"] else { continue }
    add(source: 12, model: model, brand: brand, maker: energyStarMakers[model.uppercased()] ?? makerOfBrand(brand),
        kind: "heatPump", product: "multi-split heat pump",
        specs: joined(coolingCapacity(row["cap_lo"], row["cap_hi"]), refrigerant(row["refrigerant"])), ratings: ratings(row))
}
// Indoor types: N is non-ducted; Low, Mid and Con are low-static, mid-static and conventional ducted.
for row in scratchRows("SELECT model, brand, min(type) AS type FROM multisplit_indoor WHERE model != '' GROUP BY model, brand") {
    guard let model = doeModel(row["model"]), let brand = row["brand"] else { continue }
    add(source: 12, model: model, brand: brand, maker: makerOfBrand(brand), kind: nil,
        product: row["type"]?.uppercased() == "N" ? "ductless mini-split indoor unit" : "ducted mini-split indoor unit")
}

print("DOE furnaces and boilers…")
// Furnaces also approved for mobile homes are in both classes; max() picks "Non-weatherized" over "Mobile home".
for row in scratchRows("SELECT model, brand, max(type) AS type, max(input) AS input, max(afue) AS afue FROM furnaces GROUP BY model, brand") {
    guard let model = doeModel(row["model"]), let brand = row["brand"] else { continue }
    let type = (row["type"] ?? "").lowercased()
    let fuel = type.contains("oil-fired") ? "oil" : type.contains("electric") ? "electric" : "gas"
    // Weatherized gas furnaces are the gas heat in packaged units: 48NL, 675ENW.
    let (kind, product) =
        type.contains("boiler") ? ("boiler", fuel == "electric" ? "electric boiler" : "\(fuel) \(type.contains("steam") ? "steam" : "hot water") boiler")
        : type.hasPrefix("weatherized") ? ("packagedUnit", "packaged unit with gas heat")
        : type.hasPrefix("mobile home") ? ("furnace", "mobile home \(fuel) furnace")
        : ("furnace", "\(fuel) furnace")
    add(source: 13, model: model, brand: brand, maker: energyStarMakers[model.uppercased()] ?? makerOfBrand(brand),
        kind: kind, product: product, specs: number(row["input"], digits: 0).map { "\($0) BTU/h input" },
        ratings: number(row["afue"], digits: 1).map { "\($0)% AFUE" })
}

print("DOE water heaters…")
for row in scratchRows("SELECT model, brand, min(type) AS type, max(gallons) AS gallons, max(uef) AS uef, max(gpm) AS gpm FROM water_heaters GROUP BY model, brand") {
    guard let model = doeModel(row["model"]), let brand = row["brand"] else { continue }
    let uef = Double(row["uef"] ?? "") ?? 0
    // DOE files heat pump water heaters as electric storage. Electric resistance can't reach a UEF of 1.
    let product = switch row["type"] {
    case "Gas-fired Storage Water Heater": "gas water heater"
    case "Electric Storage Water Heater": uef >= 1.5 ? "heat pump water heater" : "electric water heater"
    case "Instantaneous Gas-fired Water Heater": "tankless gas water heater"
    case "Instantaneous Electric Water Heater": "tankless electric water heater"
    case "Grid-Enabled Water Heater": "grid-enabled electric water heater"
    case "Oil-fired Storage Water Heater": "oil water heater"
    case let other?: other.lowercased()
    case nil: "water heater"
    }
    let tankless = product.hasPrefix("tankless")
    add(source: 14, model: model, brand: brand, maker: energyStarMakers[model.uppercased()] ?? makerOfBrand(brand),
        kind: "waterHeater", product: product,
        specs: tankless ? number(row["gpm"], digits: 1).map { "\($0) gal/min" } : number(row["gallons"], digits: 0).map { "rated \($0) gal" },
        ratings: number(row["uef"]).map { "UEF \($0)" })
}
sqlite3_close(scratchDB)
try? FileManager.default.removeItem(at: scratch)
nameICP()

// MARK: California Energy Commission archive

// California moves models no longer sold from its appliance database to an archive, which it publishes as Excel
// files that don't change, so each is downloaded once into a cache folder. A file has a row per brand a model is
// sold as, and per coil an air conditioner is rated with, so rows are merged by model before they're added.
let archiveCache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "FieldCopilot/cec-archive")

/// An archive file, downloaded from the archive page the first time.
func archiveFile(_ id: Int, _ name: String) async throws -> URL {
    let file = archiveCache.appending(path: name)
    guard !FileManager.default.fileExists(atPath: file.path) else { return file }
    print("Downloading \(name)…")
    let (data, response) = try await URLSession.shared.data(from: URL(string: "https://www.energy.ca.gov/filebrowser/download/\(id)?fid=\(id)")!)
    // An .xlsx file is a zip file, which starts with PK.
    guard (response as? HTTPURLResponse)?.statusCode == 200, data.starts(with: [0x50, 0x4B]) else {
        throw URLError(.badServerResponse, userInfo: [NSURLErrorFailingURLStringErrorKey: name])
    }
    try FileManager.default.createDirectory(at: archiveCache, withIntermediateDirectories: true)
    try data.write(to: file)
    return file
}

/// A row of an archive file, read by the column names in its header row. Empty cells are nil.
typealias ArchiveRow = (String) -> String?

/// Some files name their sheet sheet.xml rather than sheet1.xml, and keep their text in the cells instead of
/// in shared strings.
func forEachArchiveRow(_ file: URL, _ each: @escaping (ArchiveRow) -> Void) throws {
    let members = try zipMembers(file)
    guard let sheet = members.filter({ $0.hasPrefix("xl/worksheets/") && $0.hasSuffix(".xml") }).min() else {
        fatalError("No sheet in \(file.path)")
    }
    let shared = members.contains("xl/sharedStrings.xml") ? SheetParser.strings(try unzip(file, "xl/sharedStrings.xml")) : []
    var columns: [String: String]?
    SheetParser.forEachRow(try unzip(file, sheet), shared: shared) { row in
        guard let columns else {
            columns = Dictionary(row.map { ($0.value, $0.key) }, uniquingKeysWith: { first, _ in first })
            return
        }
        each { name in columns[name].flatMap { row[$0] }.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 } }
    }
}

/// California writes choices and placeholders its own ways: "DGUC-(T/W)036N050" is DGUC-(T,W)036N050, and ?, ^,
/// ~, _, $ and = stand for a character (WBR^^055). Text after an @ is a note (OWB-3-T-S2 @ .95GPH), and a number
/// with decimals is a value Excel changed, not a model. The rest is written as in DOE's lists.
func archiveModel(_ text: String?) -> String? {
    guard let text else { return nil }
    let model = text.components(separatedBy: " @")[0].trimmingCharacters(in: .whitespaces)
    guard !(Double(model) != nil && model.contains(".")) else { return nil }
    let choices = model.replacing(#/[\(\[][^\)\]]*[\)\]]/#) { $0.output.replacingOccurrences(of: "/", with: ",") }
    return doeModel(String(choices.map { "?^~_$=".contains($0) ? "*" : $0 }))
}

/// "05/09/1998", or an Excel day number (35924), as 1998-05-09.
func archiveDate(_ text: String?) -> String? {
    guard let text else { return nil }
    if let day = Double(text) {
        return Date(timeIntervalSince1970: (day - 25569) * 86400).formatted(Date.ISO8601FormatStyle().year().month().day())
    }
    guard let date = text.wholeMatch(of: #/(\d{1,2})/(\d{1,2})/(\d{4})/#), let month = Int(date.1), let day = Int(date.2) else { return nil }
    return "\(date.3)-" + String(format: "%02d-%02d", month, day)
}

func archiveText(_ value: Double?) -> String? { value.map { String($0) } }

/// What an archive row says about one model. Only items with a kind count toward the model's type.
struct ArchiveItem {
    let model: String?
    var brand: String? = nil
    var maker: String? = nil
    var kind: String?
    var product: String
    /// The product when fewer than nine in ten of the rows that give a type agree; nil to take the most common type.
    var whenUnsure: String? = nil
    var numbers: [String: String?] = [:]
}

/// A model, merged over its rows.
struct ArchiveEntry {
    let model: String
    let whenUnsure: String?
    var brands: [String] = []
    var makers: [String: Int] = [:]
    var firstListed: String?
    /// How many rows give each kind and product, as "furnace|gas furnace".
    var types: [String: Int] = [:]
    var low: [String: Double] = [:]
    var high: [String: Double] = [:]
}

/// Adds an archive source's models. `items` reads what a row says, nothing for a row to leave out. `format`
/// turns a model's lowest and highest numbers into its specs and ratings.
func addArchive(source: Int, items: @escaping (ArchiveRow) -> [ArchiveItem],
                format: (_ low: [String: Double], _ high: [String: Double], _ product: String) -> (specs: String?, ratings: String?)) async throws {
    var entries: [String: ArchiveEntry] = [:]
    var keys: [String] = []
    for file in archiveFiles where file.source == source {
        print("  \(file.name)…")
        try forEachArchiveRow(try await archiveFile(file.id, file.name)) { row in
            let added = archiveDate(row("Add Date"))
            for item in items(row) {
                guard let model = item.model else { continue }
                let key = model.uppercased()
                if entries[key] == nil {
                    keys.append(key)
                    entries[key] = ArchiveEntry(model: model, whenUnsure: item.whenUnsure)
                }
                var entry = entries[key]!
                if let brand = item.brand, !entry.brands.contains(brand) { entry.brands.append(brand) }
                if let maker = item.maker { entry.makers[maker, default: 0] += 1 }
                if let added { entry.firstListed = min(entry.firstListed ?? added, added) }
                if let kind = item.kind { entry.types["\(kind)|\(item.product)", default: 0] += 1 }
                for case let (name, text?) in item.numbers {
                    guard let value = Double(text), value > 0 else { continue }
                    entry.low[name] = min(entry.low[name] ?? value, value)
                    entry.high[name] = max(entry.high[name] ?? value, value)
                }
                entries[key] = entry
            }
        }
    }
    for key in keys {
        let entry = entries[key]!
        // Ties go to the name that sorts last, so every build picks the same.
        let top = entry.types.max { ($0.value, $0.key) < ($1.value, $1.key) }
        let agreed = top.map { entry.whenUnsure == nil || $0.value * 10 >= entry.types.values.reduce(0, +) * 9 } ?? false
        let type = agreed ? top!.key.split(separator: "|", omittingEmptySubsequences: false).map(String.init) : ["", entry.whenUnsure ?? ""]
        let maker = entry.makers.max { ($0.value, $0.key) < ($1.value, $1.key) }?.key ?? ""
        let (specs, ratings) = format(entry.low, entry.high, type[1])
        let brands: [String?] = entry.brands.isEmpty ? [nil] : entry.brands
        for brand in brands {
            add(source: source, model: entry.model, brand: brand, maker: maker, kind: type[0].isEmpty ? nil : type[0], product: type[1],
                specs: specs, ratings: ratings, makerIsBrand: !maker.isEmpty, firstListed: entry.firstListed)
        }
    }
}

print("CEC archive of central air conditioners…")
// A coil is rated alone (RCU-A-C) or with a blower (RCU-A-CB) that may be an air handler's or a furnace's, so
// it's only called a coil from the first. The file has no split heat pumps, though a few air conditioners give a
// heat pump as their heat. It does have packaged heat pumps under the packaged air conditioners' code (Trane
// 4TCY), so a packaged unit without gas or electric heat is only called a packaged unit.
try await addArchive(source: 15, items: { row in
    guard let cooling = row("Cooling Capacity at 95 deg. F (BTUH)").flatMap(Double.init), cooling < 65_000, row("Phase") != "3",
          let model = archiveModel(row("Model Number")) else { return [] }
    let type = row("Central AC Type") ?? ""
    let packaged = type.hasPrefix("SP")
    let product = !packaged ? "split system air conditioner"
        : row("Heat Energy Source") == "Natural Gas" ? "packaged unit with gas heat"
        : row("Heat Energy Source") == "Electricity" ? "packaged unit with electric heat" : "packaged unit"
    var items = [ArchiveItem(model: model, brand: row("Brand"), maker: energyStarMakers[model.uppercased()] ?? row("Manufacturer"),
                             kind: packaged ? "packagedUnit" : "airConditioner", product: product,
                             numbers: ["cooling": row("Cooling Capacity at 95 deg. F (BTUH)"),
                                       "seer": row("Seasonal Energy Efficiency Ratio (SEER)"), "eer": row("Energy Efficiency Ratio (EER)")])]
    if type.hasPrefix("RCU"), let coil = archiveModel(row("Coil Model Number")) {
        items.append(ArchiveItem(model: coil, kind: type.hasPrefix("RCU-A-C,") ? "evaporatorCoil" : nil, product: "evaporator coil",
                                 whenUnsure: "indoor unit (coil or air handler)"))
    }
    return items
}, format: { low, high, _ in
    (coolingCapacity(archiveText(low["cooling"]), archiveText(high["cooling"])),
     joined(range("SEER", archiveText(low["seer"]), archiveText(high["seer"])), range("EER", archiveText(low["eer"]), archiveText(high["eer"]))))
})

print("CEC archive of central air conditioners and heat pumps, 2023…")
// Indoor units as in DOE's list: a coil when rated without an air mover or with a separate one, an air handler
// when rated with its own fan and no add-on kit.
try await addArchive(source: 16, items: { row in
    guard let cooling = row("Cooling Capacity (Btu/H)").flatMap(Double.init), cooling < 65_000,
          let model = archiveModel(row("Individual Model Number Covered By Basic Model (Outdoor Unit Or Package Unit)") ?? row("Model Number"))
    else { return [] }
    let (kind, product) = centralProduct(row("Product Group Code (Other Than Multi Splits)"))
    var items = [ArchiveItem(model: model, brand: row("Brand"), maker: energyStarMakers[model.uppercased()] ?? row("Manufacturer"),
                             kind: kind, product: product,
                             numbers: ["cooling": row("Cooling Capacity (Btu/H)"), "seer2": row("Seasonal Energy Efficiency Ratio 2 (SEER2) (Btu/W-H)"),
                                       "eer2": row("Energy Efficiency Ratio 2 (EER2) In Btu/W-H (If Applicable)"),
                                       "hspf2": row("Heating Seasonal Performance Factor 2 (HSPF2) (Btu/W-H) (Heat Pumps Only)")])]
    if let indoor = row("Individual Model Number (Indoor Unit) (If Applicable)"),
       let base = archiveModel(indoor.prefix { $0 != "+" }.trimmingCharacters(in: .whitespaces)) {
        let mover = row("Individual Model Number (Air Mover Or Indoor Unit If Fan Is Part Of Indoor Unit) (If Applicable)")
        let system = row("Coil System Type")
        let coil = system == "Coil-Only System" || (mover != nil && mover != indoor)
        let handler = system == "Blower Coil System" && (mover == nil || mover == indoor) && !indoor.contains("+")
        items.append(ArchiveItem(model: base, kind: coil ? "evaporatorCoil" : handler ? "airHandler" : nil,
                                 product: coil ? "evaporator coil" : "air handler", whenUnsure: "indoor unit (coil or air handler)"))
    }
    return items
}, format: { low, high, _ in
    (coolingCapacity(archiveText(low["cooling"]), archiveText(high["cooling"])),
     joined(range("SEER2", archiveText(low["seer2"]), archiveText(high["seer2"])), range("EER2", archiveText(low["eer2"]), archiveText(high["eer2"])),
            range("HSPF2", archiveText(low["hspf2"]), archiveText(high["hspf2"]))))
})

/// Input and AFUE, as for DOE's furnaces and boilers.
func heatingFormat(_ low: [String: Double], _ high: [String: Double], _ product: String) -> (specs: String?, ratings: String?) {
    (number(archiveText(high["input"]), digits: 0).map { "\($0) BTU/h input" }, number(archiveText(high["afue"]), digits: 1).map { "\($0)% AFUE" })
}

print("CEC archive of furnaces…")
// Outdoor furnaces are the gas heat in packaged units, as in DOE's list. The file marks regular furnaces as
// mobile home furnaces too (59SC), so that isn't kept.
try await addArchive(source: 17, items: { row in
    guard (row("Nameplate Input BTUH").flatMap(Double.init) ?? 0) < 225_000, let model = archiveModel(row("Model Number")) else { return [] }
    let energy = row("Energy Source") ?? ""
    let fuel = energy == "Oil" ? "oil" : energy.hasPrefix("Electric") ? "electric" : "gas"
    let outdoor = row("Outdoor Install") == "True"
    return [ArchiveItem(model: model, brand: row("Brand"), maker: energyStarMakers[model.uppercased()] ?? row("Manufacturer"),
                        kind: outdoor ? "packagedUnit" : "furnace", product: outdoor ? "packaged unit with \(fuel) heat" : "\(fuel) furnace",
                        numbers: ["input": row("Nameplate Input BTUH"), "afue": row("Annual Fuel Utilization Efficiency (AFUE)")])]
}, format: heatingFormat)

print("CEC archive of boilers…")
try await addArchive(source: 18, items: { row in
    guard (row("Nameplate Input BTUH").flatMap(Double.init) ?? 0) < 300_000, let model = archiveModel(row("Model Number")) else { return [] }
    let energy = row("Energy Source") ?? ""
    let fuel = energy == "Oil" ? "oil" : energy.hasPrefix("Combo") ? "gas or oil" : "gas"
    let water = switch row("Boiler Type") {
    case "Steam": "steam"
    case "Both Steam & Water": "steam or hot water"
    default: "hot water"
    }
    return [ArchiveItem(model: model, brand: row("Brand"), maker: energyStarMakers[model.uppercased()] ?? row("Manufacturer"),
                        kind: "boiler", product: energy.hasPrefix("Electric") ? "electric boiler" : "\(fuel) \(water) boiler",
                        numbers: ["input": row("Nameplate Input BTUH"), "afue": row("Annual Fuel Utilization Efficiency (AFUE)")])]
}, format: heatingFormat)

print("CEC archive of water heaters…")
try await addArchive(source: 19, items: { row in
    guard let model = archiveModel(row("Model Number")) else { return [] }
    let product = switch row("Water Heater Type") {
    case "Gas-fired storage": "gas water heater"
    case "Instantaneous gas-fired": "tankless gas water heater"
    case "Electric storage": row("Energy Source") == "Heat pump" ? "heat pump water heater" : "electric water heater"
    case "Instantaneous electric": "tankless electric water heater"
    case "Grid-enabled": "grid-enabled electric water heater"
    case let other?: other.lowercased()
    case nil: "water heater"
    }
    return [ArchiveItem(model: model, brand: row("Brand"), maker: energyStarMakers[model.uppercased()] ?? row("Manufacturer"),
                        kind: "waterHeater", product: product,
                        numbers: ["gallons": row("Rated Volume"), "gpm": row("Maximum Gallons Per Minute"), "uef": row("Uniform Energy Factor")])]
}, format: { _, high, product in
    (product.hasPrefix("tankless") ? number(archiveText(high["gpm"]), digits: 1).map { "\($0) gal/min" }
        : number(archiveText(high["gallons"]), digits: 0).map { "rated \($0) gal" },
     number(archiveText(high["uef"])).map { "UEF \($0)" })
})
nameICP()

// MARK: Listings no longer listed

// A maker stops selling a model and it drops off the lists, though its units stay installed for years. So
// listings in the previous build that this download doesn't have are kept, with the date they were last
// listed, and each source keeps the date it was first downloaded.
var firstRetrieved: [Int: String] = [:]
var kept: [Int: Int] = [:]
var previous: OpaquePointer?
if FileManager.default.fileExists(atPath: output.path), sqlite3_open_v2(output.path, &previous, SQLITE_OPEN_READONLY, nil) == SQLITE_OK {
    let has = { (table: String, column: String) in rows(of: previous, "PRAGMA table_info(\(table))").contains { $0["name"] == column } }
    for row in rows(of: previous, "SELECT id, \(has("sources", "since") ? "since" : "retrieved") AS since FROM sources") {
        if let id = row["id"].flatMap({ Int($0) }) { firstRetrieved[id] = row["since"] }
    }
    let current = Set(sources.map(\.id))
    for row in rows(of: previous, """
        SELECT l.source, l.model, l.listed_as, l.maker, l.brands, l.kind, l.product, l.specs, l.ratings,
            \(has("listings", "last_listed") ? "COALESCE(l.last_listed, s.retrieved)" : "s.retrieved") AS last_listed,
            \(has("listings", "first_listed") ? "l.first_listed" : "NULL") AS first_listed
        FROM listings l JOIN sources s ON s.id = l.source
        """) {
        guard let source = row["source"].flatMap({ Int($0) }), current.contains(source), let model = row["model"] else { continue }
        let key = "\(source)|\(model.uppercased())"
        guard listings[key] == nil else { continue }
        listings[key] = Listing(source: source, model: model, listedAs: row["listed_as"] ?? model,
                                brands: (row["brands"] ?? "").split(separator: "|").map { brandName(String($0)) }, maker: row["maker"] ?? "",
                                kind: row["kind"], product: row["product"] ?? "", specs: row["specs"], ratings: row["ratings"],
                                lastListed: row["last_listed"], firstListed: row["first_listed"])
        order.append(key)
        kept[source, default: 0] += 1
    }
    sqlite3_close(previous)
}

// MARK: Writing

try? FileManager.default.removeItem(at: output)
var db: OpaquePointer?
guard sqlite3_open(output.path, &db) == SQLITE_OK else { fatalError("Can't create \(output.path)") }
let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

func exec(_ sql: String) {
    guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { fatalError(String(cString: sqlite3_errmsg(db))) }
}

func insert(_ sql: String, _ rows: [[String?]]) {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { fatalError(String(cString: sqlite3_errmsg(db))) }
    defer { sqlite3_finalize(statement) }
    for row in rows {
        sqlite3_reset(statement)
        for (index, value) in row.enumerated() {
            if let value { sqlite3_bind_text(statement, Int32(index + 1), value, -1, transient) }
            else { sqlite3_bind_null(statement, Int32(index + 1)) }
        }
        guard sqlite3_step(statement) == SQLITE_DONE else { fatalError(String(cString: sqlite3_errmsg(db))) }
    }
}

exec("""
    CREATE TABLE sources (
        id INTEGER PRIMARY KEY, name TEXT NOT NULL, list TEXT NOT NULL, url TEXT NOT NULL,
        retrieved TEXT NOT NULL,  -- when this build downloaded the list
        since TEXT NOT NULL       -- when a build first downloaded it, so how far back kept listings go
    );
    CREATE TABLE listings (
        id INTEGER PRIMARY KEY,
        source INTEGER NOT NULL REFERENCES sources(id),
        model TEXT NOT NULL,      -- as listed, with the list's wildcards: * one character or none, (A,B) a choice
        listed_as TEXT,           -- the list's own text, before a leading choice is split into one row per choice; empty when it's the model
        key TEXT NOT NULL,        -- first three letters and digits; empty when the model starts with a wildcard
        maker TEXT NOT NULL,
        brands TEXT NOT NULL,     -- separated by |
        kind TEXT,                -- the app's equipment type; empty when the list doesn't say
        product TEXT NOT NULL,    -- in plain words, e.g. "split system heat pump"
        specs TEXT,
        ratings TEXT,
        last_listed TEXT,         -- when it was last on its list, once it has dropped off; empty while it's on it
        first_listed TEXT         -- when it was first listed, for the lists that say: California's archive
    );
    """)
exec("BEGIN")
insert("INSERT INTO sources VALUES (?, ?, ?, ?, ?, ?)", sources.map { source in
    [String(source.id), source.name, source.list, source.url, source.retrieved, min(firstRetrieved[source.id] ?? source.retrieved, source.retrieved)]
})
insert("INSERT INTO listings (source, model, listed_as, key, maker, brands, kind, product, specs, ratings, last_listed, first_listed) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
       order.map { key in
           let l = listings[key]!
           return [String(l.source), l.model, l.listedAs == l.model ? nil : l.listedAs, indexKey(l.model), l.maker, l.brands.joined(separator: "|"), l.kind,
                   l.product, l.specs, l.ratings, l.lastListed, l.firstListed]
       })
exec("COMMIT")
exec("CREATE INDEX listings_key ON listings(key)")
exec("ANALYZE")
exec("VACUUM")
sqlite3_close(db)

let counts = Dictionary(grouping: order, by: { listings[$0]!.source }).mapValues(\.count)
for source in sources {
    let old = kept[source.id].map { ", \($0) no longer listed" } ?? ""
    print("  \(counts[source.id] ?? 0) \(source.name) \(source.list)\(old)")
}
let size = (try? FileManager.default.attributesOfItem(atPath: output.path)[.size] as? Int) ?? 0
print("Wrote \(order.count) listings, \(size.formatted(.byteCount(style: .file))), to \(output.path)")
