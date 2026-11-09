import Foundation

/// What a model number says about a unit, decoded with the manufacturer's published scheme.
struct ModelInfo {
    let manufacturer: String
    /// Brands this model is sold under. One brand means the model number settles it.
    let brands: [String]
    /// The equipment type, when the model number encodes it.
    let kind: EquipmentKind?
    /// Specs, e.g. "3 tons · R-410A" or "50 gal · natural gas · 40,000 BTU/h · 6-year warranty".
    let size: String?
}

/// One manufacturer model-number scheme: a strict whole-string pattern and how to read its parts.
struct ModelRule {
    let regex: Regex<AnyRegexOutput>
    let decode: @MainActor (ModelParts) -> ModelInfo?

    init(_ pattern: String, decode: @escaping @MainActor (ModelParts) -> ModelInfo?) {
        regex = try! Regex(pattern)
        self.decode = decode
    }
}

/// The named parts of a matched model number.
struct ModelParts {
    let output: AnyRegexOutput

    subscript(_ name: String) -> String? {
        output[name]?.substring.map(String.init).flatMap { $0.isEmpty ? nil : $0 }
    }
}

/// Looks up manufacturer, brand, type and size from a model number. Deterministic: each rule is a
/// manufacturer's published model-number scheme (sources in each ModelRules file), matched against
/// the whole model number so look-alikes from other makers don't match.
enum ModelLookup {
    static let rules: [ModelRule] =
        icpRules + carrierRules + lennoxRules + goodmanRules + traneRules + rheemRules + nortekRules + johnsonControlsRules
        + miniSplitRules + waterHeaterRules + teslaRules

    static func lookup(_ model: String?) -> ModelInfo? {
        guard let model else { return nil }
        for code in forms(of: model) {
            for rule in rules {
                if let info = decode(code, with: rule) { return info }
            }
        }
        return nil
    }

    /// Every rule that matches, for tests: a real model number should match exactly one.
    static func allMatches(_ model: String) -> [ModelInfo] {
        rules.compactMap { rule in forms(of: model).lazy.compactMap { decode($0, with: rule) }.first }
    }

    private static func decode(_ code: String, with rule: ModelRule) -> ModelInfo? {
        guard let match = try? rule.regex.wholeMatch(in: code), let info = rule.decode(ModelParts(output: match.output)),
              isPlausible(info)
        else { return nil }
        return info
    }

    /// Residential equipment stays within these sizes. A decode outside them comes from a misread character
    /// ("FJ5ANXA18L05" read as "FJ5ANX418L05" would be a 35-ton air handler), so it's dropped.
    static func isPlausible(_ info: ModelInfo) -> Bool {
        guard let size = info.size else { return true }
        let largest = { (pattern: Regex<(Substring, Substring)>) in
            size.matches(of: pattern).compactMap { Double($0.output.1.replacingOccurrences(of: ",", with: "")) }.max() ?? 0
        }
        return largest(#/([\d.]+) tons?\b/#) <= 25 && largest(#/(\d+) gal\b/#) <= 120
            && largest(#/([\d,]+) BTU\/h/#) <= 400_000
    }

    /// The model as printed (uppercase, no spaces) and without dashes or slashes. Water heater
    /// schemes use dashes ("GCR-50"); HVAC schemes treat them as decoration ("13HPX-048-230").
    static func forms(of model: String) -> [String] {
        let printed = String(model.uppercased().filter { !$0.isWhitespace && $0 != "*" })
        let compact = printed.filter { $0.isLetter || $0.isNumber }
        return printed == compact ? [printed] : [printed, compact]
    }

    // MARK: Building results

    static func info(_ manufacturer: String, _ brands: [String], _ kind: EquipmentKind?, size: [String?] = []) -> ModelInfo {
        let sizeText = size.compactMap { $0 }.joined(separator: " · ")
        return ModelInfo(manufacturer: manufacturer, brands: brands, kind: kind, size: sizeText.isEmpty ? nil : sizeText)
    }

    /// Cooling capacity code in thousands of BTU/h as tons. Codes from 18 up round to the nearest
    /// half ton, since makers use odd codes (19, 25, 31, 37…) for alternate sizes of the same tonnage;
    /// 13 to 17 round to the nearest quarter ton (Goodman's 17 is 1½ tons).
    static func tons(_ code: String?) -> String? {
        guard let code, let n = Int(code), n > 0 else { return nil }
        if n < 12 { return "\(n),000 BTU/h" }
        let value = n < 18 ? (Double(n) / 3).rounded() / 4 : (Double(n) / 6).rounded() / 2
        return value == 1 ? "1 ton" : "\(value.formatted()) tons"
    }

    /// A furnace's heat input from its model-number code, as "66,000 BTU/h input". Some makers' codes are
    /// nominal sizes: Lennox's and Carrier's 070 is rated 66,000. `rated` maps those codes to the rated
    /// input in thousands of BTU/h; other codes are the input in thousands.
    static func input(_ code: String?, rated: [String: Int] = [:]) -> String? {
        guard let code else { return nil }
        return btu(rated[code].map(String.init) ?? code, " input")
    }

    /// A pair of capacity codes as a range: "1824" is 1.5–2 tons.
    static func tonsRange(_ code: String?) -> String? {
        guard let code, code.count == 4, let low = tons(String(code.prefix(2))), let high = tons(String(code.suffix(2))) else { return nil }
        return low == high ? low : "\(low.replacingOccurrences(of: " tons", with: "").replacingOccurrences(of: " ton", with: ""))–\(high)"
    }

    /// A thousands-of-BTU/h code as "80,000 BTU/h".
    static func btu(_ code: String?, _ suffix: String = "") -> String? {
        guard let code, let n = Int(code), n > 0 else { return nil }
        return "\((n * 1000).formatted()) BTU/h\(suffix)"
    }

    /// An AFUE code from a model number. Two digits name the series: a "96" furnace certifies at 95–97%.
    /// A lone 9 is Goodman's 90s: SS-GMH95 says "93%+", but California's archive certifies the GKS9 at 92.1%
    /// and the GCH9, GCV9, GME9, GMH9 and GMV9 at 93–96.1%.
    static func afue(_ code: String?) -> String? {
        switch code {
        case nil: nil
        case "8", "80": "80% AFUE"
        case "9": "92%+ AFUE"
        case let value?: "about \(value)% AFUE"
        }
    }

    static func refrigerant(_ digit: String?) -> String? {
        switch digit {
        case "2": "R-22"
        case "4": "R-410A"
        case "5": "R-454B"
        default: nil
        }
    }
}
