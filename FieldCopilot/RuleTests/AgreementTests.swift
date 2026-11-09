// Checks the model-number rules against the equipment database's listings (ENERGY STAR, DOE and the California
// Energy Commission). For every listed model a rule matches: the type must agree, a single brand must be the
// only brand listed, a brand list must include every brand of ours the list names, and AFUE must be within 2 points.

import Foundation

var agreementFailures = 0

/// A listing as a model number the rules can read: no add-on kit, no trailing wildcards, the first
/// of each choice group, and inner wildcards (one character or none) left out or filled.
func printedForms(of listing: String) -> [String] {
    var text = String(listing.uppercased().prefix { $0 != "+" }).trimmingCharacters(in: .whitespaces)
    while let last = text.last, "*- ".contains(last) { text.removeLast() }
    text = text.replacing(#/[\(\[]([^,\)\]]*)[^\)\]]*[\)\]]/#) { String($0.output.1) }
    guard let first = text.range(of: "*") else { return [text] }
    var firstOnly = text
    firstOnly.replaceSubrange(first, with: "A")
    return [text.replacingOccurrences(of: "*", with: ""), firstOnly.replacingOccurrences(of: "*", with: "")]
        + ["A", "0", "1", "N", "S"].map { text.replacingOccurrences(of: "*", with: $0) }
}

/// DOE listings filed under a brand that isn't on the unit, checked against the other lists. Their brands aren't compared.
let filedUnderAnotherBrand: [String: String] = [
    "577CNWK24040A*": "filed under Carrier; DOE lists the other 577C models under Bryant",
    "PROE47 S2 RU95": "filed under Rheem; DOE lists 192 other RU water heaters under Ruud",
    "PROG29-32N RU63 *": "filed under Rheem; DOE lists 192 other RU water heaters under Ruud",
    "PROE50 M2 RH CG": "also filed under Friedrich, a Rheem company; 204 other RH water heaters are Rheem only",
    "N95MSU0401712A": "also filed under WeatherMaker; ENERGY STAR lists it without",
    "RC68iN": "a Camplux model named like Rinnai's RC series",
]

/// Families where California's archive gets the type or AFUE wrong, by how their model numbers start. The app
/// takes the rules' type over the archive's.
let archiveDisagreements: [(starts: [String], reason: String)] = [
    (["RGVA", "RGYA", "UGAA", "UGRC", "UGTC", "UGUA", "UGVA", "UGYA"],
     "Rheem and Ruud indoor furnaces marked as outdoor units on some rows (UGVA's 1986 rows say indoor, its 1983 rows outdoor)"),
    (["C10-", "C104", "C105", "C114", "C120", "CK30", "CK49"], "Lennox coils filed as the air conditioner or furnace they're rated with"),
    (["FK4A"], "a Carrier fan coil filed as the coil it's rated with"),
    (["R92TA"], "a Rheem 92% furnace certified at 95% on one row"),
]

func isArchiveDisagreement(_ listing: EquipmentDatabase.Listing) -> Bool {
    listing.source.isArchive && archiveDisagreements.contains { $0.starts.contains { listing.model.uppercased().hasPrefix($0) } }
}

/// Brand names compared by letters, with the lists' short forms of a few, and Mitsubishi's units co-branded
/// with Trane and American Standard as Mitsubishi Electric.
func brandKey(_ name: String) -> String {
    let key = name.uppercased().filter { $0.isLetter }
    return ["SURE": "SURECOMFORT", "AMERICAN": "AMERICANWATERHEATER", "SMARTCOMFORT": "SMARTCOMFORT",
            "TRANEMITSUBISHIELECTRIC": "MITSUBISHIELECTRIC", "AMERICANSTANDARDMITSUBISHIELECTRIC": "MITSUBISHIELECTRIC"][key] ?? key
}

func runAgreementTests() {
    EquipmentDatabase.fileURL = URL(filePath: "FieldCopilot/Equipment.sqlite")
    var matched: [(listing: EquipmentDatabase.Listing, info: ModelInfo)] = []
    for listing in EquipmentDatabase.allListings() where !listing.model.hasPrefix("*") {
        for form in printedForms(of: listing.model) {
            if let info = ModelLookup.allMatches(form).first {
                matched.append((listing, info))
                break
            }
        }
    }
    let ourBrands = Set(matched.flatMap { $0.info.brands.map(brandKey) })

    var problems: [String: [String]] = [:]
    var unsettled = 0
    for (listing, info) in matched {
        if isArchiveDisagreement(listing) {
            unsettled += 1
            continue
        }
        let tag = "\(listing.model) → \(info.brands.joined(separator: "/"))"
        // A hybrid inverter with a battery (Powerwall 3) is also on the inverter list.
        if let kind = info.kind, let listed = listing.kind, kind != listed, !listing.product.hasPrefix("hybrid") {
            problems["type", default: []].append("\(tag) \(kind.rawValue); \(listing.source.name) \(listed.rawValue)")
        }
        let ruleKeys = Set(info.brands.map(brandKey))
        let listed = Set(listing.brands.map(brandKey))
        // A listing with choices, like (C,H,T)4H5S30*K*AAA*, gives brands for all its variants together. California's
        // archive names whichever brands filed a model, dealers' and stores' own among them (Xenon, Merit, Sears), and
        // the app takes the rules' brands over it.
        let hasChoices = listing.listedAs.contains("(") || listing.listedAs.contains("[")
        if hasChoices || listed.isEmpty || listing.source.isArchive || filedUnderAnotherBrand[listing.listedAs] != nil {
        } else if ruleKeys.count == 1, !listed.isSubset(of: ruleKeys) {
            problems["single brand", default: []].append("\(tag); \(listing.source.name) \(listing.brands)")
        } else if ruleKeys.count > 1, !listed.intersection(ourBrands).isSubset(of: ruleKeys) {
            problems["brand list", default: []].append("\(tag); \(listing.source.name) \(listing.brands)")
        }
        // "90%+" means at least 90. "About 97%" is a series code, and a series' models certify up to
        // 2 points lower (PG97 furnaces certify at 95–97%).
        if let match = info.size?.firstMatch(of: #/(\d+)%(\+?) AFUE/#), let stated = Double(match.1),
           let certified = listing.ratings?.firstMatch(of: #/([\d.]+)% AFUE/#).flatMap({ Double($0.1) }),
           match.2.isEmpty ? abs(stated - certified) > 2 : certified < stated - 0.5 {
            problems["AFUE", default: []].append("\(tag): \(info.size ?? ""); certified \(certified)%")
        }
    }

    print("\(matched.count) listed models matched a rule, \(unsettled) of them in families California's archive disagrees on")
    for (kind, items) in problems.sorted(by: { $0.key < $1.key }) {
        agreementFailures += items.count
        print("FAIL  \(kind): \(items.count), e.g.")
        for item in items.prefix(6) { print("        \(item)") }
    }
    print(agreementFailures == 0 ? "All agreement checks passed" : "\(agreementFailures) agreement check(s) FAILED")
}
