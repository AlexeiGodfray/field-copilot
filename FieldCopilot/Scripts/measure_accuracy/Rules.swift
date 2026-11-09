import Foundation

/// What each model-number rule adds to the database. The app asks the database first, so a rule matters
/// for models the lists don't carry (older units, and ones no longer sold) and for listed models whose
/// listing names no brand or type (DOE's central AC list names no brand, ENERGY STAR's indoor units no
/// type). For each rule: the listed models it decodes, how many of those get their brand or type only from
/// the rule, and the model numbers from manufacturer documents (in RuleTests) it decodes that no list
/// carries. A rule with neither adds nothing we can show.
func measureRules(root: URL) {
    heading("Rules: what each model-number rule decodes that the lists don't carry")
    let groups: [(String, [ModelRule])] = [
        ("ICP", ModelLookup.icpRules), ("Carrier", ModelLookup.carrierRules), ("Lennox", ModelLookup.lennoxRules),
        ("Goodman", ModelLookup.goodmanRules), ("Trane", ModelLookup.traneRules), ("Rheem", ModelLookup.rheemRules),
        ("Nortek", ModelLookup.nortekRules), ("Johnson Controls", ModelLookup.johnsonControlsRules),
        ("Mini-splits", ModelLookup.miniSplitRules), ("Water heaters", ModelLookup.waterHeaterRules), ("Tesla", ModelLookup.teslaRules),
    ]
    let rules = groups.flatMap { group in group.1.enumerated().map { (name: "\(group.0) \($0.offset + 1)", rule: $0.element) } }

    /// The first rule that decodes a model, as the app's lookup takes it.
    func ruleIndex(_ model: String) -> Int? {
        for form in ModelLookup.forms(of: model) {
            for (index, entry) in rules.enumerated() {
                if let match = try? entry.rule.regex.wholeMatch(in: form), let info = entry.rule.decode(ModelParts(output: match.output)),
                   ModelLookup.isPlausible(info) { return index }
            }
        }
        return nil
    }

    var listed = Array(repeating: 0, count: rules.count)
    var fromRule = Array(repeating: 0, count: rules.count)
    var listedExample = Array(repeating: "", count: rules.count)
    for listing in EquipmentDatabase.allListings() {
        for form in printedForms(listing) {
            guard let index = ruleIndex(form) else { continue }
            listed[index] += 1
            if let match = EquipmentDatabase.lookup(form), !match.brands.isEmpty, match.listing.kind != nil {} else { fromRule[index] += 1 }
            if listedExample[index].isEmpty { listedExample[index] = form }
            break
        }
    }

    // Model numbers quoted in the rule tests, from manufacturer documents and labels.
    var documented = Array(repeating: [String](), count: rules.count)
    var unlisted = Array(repeating: [String](), count: rules.count)
    var seen = Set<String>()
    for file in ["RuleTests/SourcedModelTests.swift", "RuleTests/ModelTests.swift"] {
        let text = (try? String(contentsOf: root.appending(path: file), encoding: .utf8)) ?? ""
        for match in text.matches(of: #/"([A-Za-z0-9][A-Za-z0-9 ./-]{4,30})"/#) {
            let model = String(match.output.1)
            guard model.contains(where: \.isLetter), model.contains(where: \.isNumber), seen.insert(model).inserted,
                  let index = ruleIndex(model) else { continue }
            documented[index].append(model)
            if EquipmentDatabase.lookup(model) == nil { unlisted[index].append(model) }
        }
    }

    print("rule".padded(17) + "listed".rightAligned(8) + "brand or type only from rule".rightAligned(30) + "documented, not listed".rightAligned(24)
          + "  e.g.")
    for (index, entry) in rules.enumerated() {
        let example = unlisted[index].prefix(2).joined(separator: ", ")
        print(entry.name.padded(17) + String(listed[index]).rightAligned(8) + String(fromRule[index]).rightAligned(30)
              + "\(unlisted[index].count) of \(documented[index].count)".rightAligned(24)
              + "  " + (example.isEmpty ? "(listed: \(documented[index].first ?? listedExample[index]))" : example))
    }
    let unlistedRules = rules.indices.filter { !unlisted[$0].isEmpty }
    let listingRules = rules.indices.filter { unlisted[$0].isEmpty && fromRule[$0] > 0 }
    let neither = rules.indices.filter { unlisted[$0].isEmpty && fromRule[$0] == 0 }
    print("\n\(unlistedRules.count) of \(rules.count) rules decode documented models no list carries.")
    print("\(listingRules.count) more give listed models a brand or type the list doesn't: \(listingRules.map { rules[$0].name }.joined(separator: ", "))")
    print("\(neither.count) add nothing we can show: \(neither.map { rules[$0].name }.joined(separator: ", "))")
}
