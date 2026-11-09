// Checks the model-number rules against ENERGY STAR's published specs. Every certified heat pump, furnace
// and water heater model number is decoded with the app's own rules, and what the rule says is compared
// with what ENERGY STAR lists for that model: the type, AFUE, refrigerant, fuel, gallons and gas input
// must agree. Tons and brands that differ are warnings: variable-speed units are rated below their
// nominal size, and ENERGY STAR spells some brands its own way.
//
// Run from the repository root after changing a rule or refreshing the ENERGY STAR list:
//   FieldCopilot/Scripts/check_model_rules.sh
//
// Covers only what ENERGY STAR lists: no central air conditioners, coils, air handlers, furnace input,
// or models no longer certified. Those rely on the manufacturer documents cited in each ModelRules file and
// checked by RuleTests/SourcedModelTests.swift.

import Foundation

func rows(_ dataset: String, _ query: [String: String]) async throws -> [[String: String]] {
    var all: [[String: String]] = []
    while true {
        var url = URLComponents(string: "https://data.energystar.gov/resource/\(dataset).json")!
        url.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
            + [URLQueryItem(name: "$limit", value: "50000"), URLQueryItem(name: "$offset", value: String(all.count))]
        let (data, response) = try await URLSession.shared.data(from: url.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse, userInfo: [NSURLErrorFailingURLErrorKey: url.url as Any])
        }
        let page = try JSONDecoder().decode([[String: String]].self, from: data)
        all += page
        if page.count < 50000 { return all }
    }
}

// MARK: Which rule reads a model

/// Every rule, named by its file and position: "Carrier #3" is the fourth rule in ModelRules+Carrier.swift.
let named: [(name: String, rule: ModelRule)] = [
    ("ICP", ModelLookup.icpRules), ("Carrier", ModelLookup.carrierRules), ("Lennox", ModelLookup.lennoxRules),
    ("Goodman", ModelLookup.goodmanRules), ("Trane", ModelLookup.traneRules), ("Rheem", ModelLookup.rheemRules),
    ("WaterHeaters", ModelLookup.waterHeaterRules),
].flatMap { file, rules in rules.enumerated().map { ("\(file) #\($0.offset)", $0.element) } }

/// The rule ModelLookup.lookup would use, in the same order: each form of the model, then each rule.
func decode(_ model: String) -> (rule: String, info: ModelInfo)? {
    for code in ModelLookup.forms(of: model) {
        for (name, rule) in named {
            if let match = try? rule.regex.wholeMatch(in: code), let info = rule.decode(ModelParts(output: match.output)) {
                return (name, info)
            }
        }
    }
    return nil
}

// MARK: What a rule said

func parts(_ info: ModelInfo) -> [String] { info.size?.components(separatedBy: " · ") ?? [] }

/// Nominal tons: one size, or the low and high of a range.
func tons(_ info: ModelInfo) -> ClosedRange<Double>? {
    for part in parts(info) {
        if let m = part.wholeMatch(of: #/([\d.]+)–([\d.]+) tons?/#), let low = Double(m.1), let high = Double(m.2) { return low...high }
        if let m = part.wholeMatch(of: #/([\d.]+) tons?/#), let value = Double(m.1) { return value...value }
    }
    return nil
}

func refrigerant(_ info: ModelInfo) -> String? { parts(info).first { $0.hasPrefix("R-") } }

func afueAgrees(_ info: ModelInfo, _ listed: Double) -> Bool? {
    for part in parts(info) {
        if let m = part.wholeMatch(of: #/about (\d+)% AFUE/#), let value = Double(m.1) { return abs(value - listed) <= 2 }
        if let m = part.wholeMatch(of: #/(\d+)%\+ AFUE/#), let value = Double(m.1) { return listed >= value }
        if let m = part.wholeMatch(of: #/(\d+)% AFUE/#), let value = Double(m.1) { return abs(value - listed) <= 1 }
    }
    return nil
}

func gallons(_ info: ModelInfo) -> Double? {
    parts(info).compactMap { $0.wholeMatch(of: #/(\d+) gal/#).flatMap { Double($0.1) } }.first
}

func gasInput(_ info: ModelInfo) -> Double? {
    parts(info).compactMap { $0.wholeMatch(of: #/([\d,]+) BTU\/h/#).flatMap { Double($0.1.replacingOccurrences(of: ",", with: "")) } }.first
}

func fuel(_ info: ModelInfo) -> String? {
    parts(info).first { ["natural gas", "propane", "electric", "heat pump", "gas"].contains($0) }
}

func letters(_ text: String) -> String { text.uppercased().filter(\.isLetter) }

// MARK: Comparing

struct Disagreement { let rule: String; let check: String; let detail: String }
var failures: [Disagreement] = []
var warnings: [Disagreement] = []
var compared: [String: Int] = [:]
var coverage: [String: (listed: Int, read: Int)] = [:]

func check(_ rule: String, _ check: String, _ agrees: Bool, warn: Bool = false, _ detail: @autoclosure () -> String) {
    compared[check, default: 0] += 1
    guard !agrees else { return }
    let disagreement = Disagreement(rule: rule, check: check, detail: detail())
    if warn { warnings.append(disagreement) } else { failures.append(disagreement) }
}

func kindName(_ info: ModelInfo) -> String { info.kind?.displayName.lowercased() ?? "no type" }

for row in try await rows("83eb-xbyy", [
    "$select": "model_number, outdoor_unit_brand_name, product_type, refrigerant_type, "
        + "min(cooling_capacity_btu_h) as cooling_low, max(cooling_capacity_btu_h) as cooling_high",
    "$group": "model_number, outdoor_unit_brand_name, product_type, refrigerant_type",
]) {
    guard let model = row["model_number"] else { continue }
    coverage["Heat pumps", default: (0, 0)].listed += 1
    guard let (rule, info) = decode(model) else { continue }
    coverage["Heat pumps", default: (0, 0)].read += 1
    check(rule, "type", info.kind == nil || [.heatPump, .packagedUnit].contains(info.kind!),
          "\(model): read as \(kindName(info)); ENERGY STAR lists a \(row["product_type"] ?? "") heat pump")
    if let nominal = tons(info), let low = Double(row["cooling_low"] ?? ""), let high = Double(row["cooling_high"] ?? "") {
        check(rule, "tons", nominal.lowerBound <= high / 12000 + 0.6 && nominal.upperBound >= low / 12000 - 0.6, warn: true,
              "\(model): read as \(info.size ?? ""); ENERGY STAR rates \(Int(low))–\(Int(high)) BTU/h cooling")
    }
    if let refrigerant = refrigerant(info), let listed = row["refrigerant_type"], !listed.isEmpty {
        check(rule, "refrigerant", letters(listed).contains(letters(refrigerant)),
              "\(model): read as \(refrigerant); ENERGY STAR lists \(listed)")
    }
    if let brand = row["outdoor_unit_brand_name"], !brand.isEmpty, (1...3).contains(info.brands.count) {
        check(rule, "brand", info.brands.contains { letters(brand).hasPrefix(letters($0)) || letters($0).hasPrefix(letters(brand)) },
              warn: true, "\(model): read as sold by \(info.brands.joined(separator: ", ")); ENERGY STAR lists \(brand)")
    }
}

for row in try await rows("i97v-e8au", ["$select": "model_number, efficiency_afue"]) {
    guard let model = row["model_number"] else { continue }
    coverage["Furnaces", default: (0, 0)].listed += 1
    guard let (rule, info) = decode(model) else { continue }
    coverage["Furnaces", default: (0, 0)].read += 1
    check(rule, "type", info.kind == .furnace, "\(model): read as \(kindName(info)); ENERGY STAR lists a furnace")
    if let listed = Double(row["efficiency_afue"] ?? ""), let agrees = afueAgrees(info, listed) {
        check(rule, "AFUE", agrees, "\(model): read as \(info.size ?? ""); ENERGY STAR lists \(listed)% AFUE")
    }
}

for row in try await rows("pbpq-swnu", [
    "$select": "model_number, type, fuel, storage_volume_gallons, input_rate_for_gas_thousand_btu_per_hour",
]) {
    guard let model = row["model_number"] else { continue }
    coverage["Water heaters", default: (0, 0)].listed += 1
    guard let (rule, info) = decode(model) else { continue }
    coverage["Water heaters", default: (0, 0)].read += 1
    let listedType = "\(row["type"] ?? "") \(row["fuel"] ?? "")".lowercased()
    check(rule, "type", info.kind == .waterHeater, "\(model): read as \(kindName(info)); ENERGY STAR lists a water heater")
    if let gallons = gallons(info), let listed = Double(row["storage_volume_gallons"] ?? ""), listed > 0 {
        // Nominal gallons: a "50" is often rated 46–48.
        check(rule, "gallons", abs(gallons - listed) <= max(4, listed * 0.12),
              "\(model): read as \(Int(gallons)) gal; ENERGY STAR lists \(listed) gal")
    }
    if let fuel = fuel(info) {
        let agrees = switch fuel {
        case "heat pump": listedType.contains("heat pump")
        case "electric": listedType.contains("electric") && !listedType.contains("heat pump")
        case "propane": listedType.contains("propane") || listedType.contains("lp")
        default: listedType.contains("gas")
        }
        check(rule, "fuel", agrees, "\(model): read as \(fuel); ENERGY STAR lists \(listedType)")
    }
    // The column is named "thousand BTU per hour" but holds BTU/h.
    if let input = gasInput(info), let listed = Double(row["input_rate_for_gas_thousand_btu_per_hour"] ?? ""), listed > 0 {
        check(rule, "gas input", abs(input - listed) <= max(2000, listed * 0.06),
              "\(model): read as \(Int(input)) BTU/h; ENERGY STAR lists \(Int(listed)) BTU/h")
    }
}

// MARK: Report

print("Models a rule read:")
for (group, count) in coverage.sorted(by: { $0.key < $1.key }) {
    print("  \(group): \(count.read) of \(count.listed) ENERGY STAR models")
}
print("\nChecks:")
for (name, total) in compared.sorted(by: { $0.key < $1.key }) {
    let disagree = (failures + warnings).filter { $0.check == name }.count
    print("  \(name): \(total - disagree) of \(total) agree")
}

func list(_ title: String, _ items: [Disagreement]) {
    guard !items.isEmpty else { return }
    print("\n\(title)")
    for group in Dictionary(grouping: items, by: { "\($0.rule), \($0.check)" }).sorted(by: { $0.key < $1.key }) {
        print("  \(group.key) (\(group.value.count)):")
        for item in group.value.prefix(5) { print("    \(item.detail)") }
    }
}
list("Warnings (rated below the nominal size, or ENERGY STAR's brand spelling):", warnings)
list("FAILURES:", failures)
print(failures.isEmpty ? "\nNo rule disagrees with ENERGY STAR." : "\n\(failures.count) disagreements with ENERGY STAR.")
exit(failures.isEmpty ? 0 : 1)
