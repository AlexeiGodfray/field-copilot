import CoreGraphics
import Foundation
import FoundationModels

/// Heat pump or air conditioner, for outdoor units the database doesn't have. Takes split-system heat pumps and
/// air conditioners whose type the lists give, and runs the app's type check without their listing: the
/// model-number rules first, then Apple Intelligence reading a nameplate that doesn't print "heat pump" (the brand,
/// model, serial, electrical and refrigerant lines every outdoor unit has, the same for both types). Calling a heat
/// pump an air conditioner, or the other way around, changes a replacement quote and the rebates it qualifies for.
/// The models come from today's lists and California's 2023 archive; older units may use older numbering. Each
/// listing's wildcards are filled the ways a label might print them, and the rules get the first they decode, so the
/// rules' share is an upper bound.
func measureHeatPumps(perMaker count: Int) async throws {
    heading("Heat pumps: heat pump or air conditioner, when the database doesn't have the model")
    let ai = SystemLanguageModel.default.availability == .available
    print("Apple Intelligence on this Mac: \(ai ? "available" : "not available, so models the rules don't decode stay unknown")")

    // One listing per printed model, with a brand to print on the label.
    var seen = Set<String>()
    let pool = EquipmentDatabase.allListings().filter { listing in
        guard ["split system heat pump", "split system air conditioner"].contains(listing.product), !listing.model.hasPrefix("*"),
              !(listing.brands.first ?? listing.maker).isEmpty else { return false }
        return seen.insert(ListedModel.characters(printed(listing)).map(String.init).joined()).inserted
    }
    let byMaker = Dictionary(grouping: pool, by: \.maker)
    let makers = byMaker.keys.sorted { (byMaker[$0]!.count, $1) > (byMaker[$1]!.count, $0) }
    let named = Array(makers.prefix(10))
    let groups = named.map { ($0, byMaker[$0]!) } + [("Other", makers.dropFirst(10).flatMap { byMaker[$0]! })]

    struct Outcome {
        var rules = [0, 0, 0]  // right, wrong, no type
        var ai = [0, 0, 0]  // right, wrong, unsure, for those the rules don't decode
        var app = [0, 0, 0]
    }
    var results: [EquipmentKind: [String: Outcome]] = [:]
    var bySource: [EquipmentKind: [String: [Int]]] = [:]  // today's lists or the archive → right, total
    var wrong: [String] = []
    var asked = 0

    for kind in [EquipmentKind.heatPump, .airConditioner] {
        for (maker, listings) in groups {
            let truth = kind == .heatPump ? "split system heat pump" : "split system air conditioner"
            let sample = listings.filter { $0.product == truth }.shuffled(using: &random).prefix(count)
            var outcome = Outcome()
            for listing in sample {
                // Wildcards filled the ways a label might print them, taking the first the rules decode: 25SCA542A**30
                // is printed 25SCA542A0030, not 25SCA542AAA30.
                let forms = printedForms(listing)
                let model = forms.first { ModelLookup.lookup($0)?.kind != nil } ?? forms[0]
                let info = ModelLookup.lookup(model)
                let lines = nameplate(brand: listing.brands.first ?? listing.maker, model: model)
                var answer: EquipmentLabel?
                if info?.kind == nil, ai {
                    answer = try? await LabelReader.read(lines)
                    asked += 1
                    if asked % 50 == 0 { print("  asked Apple Intelligence about \(asked) labels…") }
                }
                let decided = LabelRules.checkKind(answer?.kind ?? .unknown, evidence: answer?.typeEvidence, texts: lines.map(\.text),
                                                   modelInfo: info, listed: nil).0
                // "Air conditioner or heat pump" is unsure, not wrong.
                let score = { (got: EquipmentKind?) in
                    got == kind ? 0 : got == nil || got == .unknown || got == .airConditionerOrHeatPump ? 2 : 1
                }
                outcome.rules[score(info?.kind)] += 1
                if info?.kind == nil { outcome.ai[score(decided)] += 1 }
                outcome.app[score(decided)] += 1
                let from = listing.source.isArchive ? "California's 2023 archive" : "today's lists"
                bySource[kind, default: [:]][from, default: [0, 0]][0] += decided == kind ? 1 : 0
                bySource[kind, default: [:]][from, default: [0, 0]][1] += 1
                if score(decided) == 1, wrong.count < 12 {
                    let by = info?.kind != nil ? "the rules" : "Apple Intelligence"
                    wrong.append("\(model) (\(listing.brands.first ?? maker)), a \(kind.displayName.lowercased()): \(by) said \(decided.displayName.lowercased())")
                }
            }
            results[kind, default: [:]][maker] = outcome
        }
    }

    for kind in [EquipmentKind.heatPump, .airConditioner] {
        print("\n\(kind == .heatPump ? "Heat pumps" : "Air conditioners") (right / wrong / unsure):")
        print("maker".padded(26) + "labels".rightAligned(7) + "rules".rightAligned(16) + "then AI".rightAligned(16) + "app".rightAligned(16) + "  app right")
        var total = Outcome()
        for (maker, _) in groups {
            guard let o = results[kind]?[maker] else { continue }
            let n = o.app.reduce(0, +)
            guard n > 0 else { continue }
            let cells = [o.rules, o.ai, o.app].map { $0.map(String.init).joined(separator: " / ").rightAligned(16) }.joined()
            print(maker.padded(26) + String(n).rightAligned(7) + cells + "  " + percent(o.app[0], n))
            for i in 0..<3 { total.rules[i] += o.rules[i]; total.ai[i] += o.ai[i]; total.app[i] += o.app[i] }
        }
        let n = total.app.reduce(0, +)
        let cells = [total.rules, total.ai, total.app].map { $0.map(String.init).joined(separator: " / ").rightAligned(16) }.joined()
        print("All".padded(26) + String(n).rightAligned(7) + cells + "  " + percent(total.app[0], n))
        let other = kind == .heatPump ? "air conditioners" : "heat pumps"
        print("  Called \(other) or another type: \(total.app[1]) (\(percent(total.app[1], n))), \(total.rules[1]) by the rules,"
              + " \(total.ai[1]) by Apple Intelligence. Unsure (\"air conditioner or heat pump\" or no type): \(total.app[2]) (\(percent(total.app[2], n))).")
        for (from, counts) in (bySource[kind] ?? [:]).sorted(by: { $0.key > $1.key }) {
            print("  From \(from): \(counts[0]) of \(counts[1]) right (\(percent(counts[0], counts[1])))")
        }
    }
    // checkKind takes the rules' type over words printed on the label.
    print("\nA label printing \"HEAT PUMP\" fixes what Apple Intelligence gets wrong or leaves unknown, but not the rules' mistakes,"
          + " since the rules come first.")
    if !wrong.isEmpty { print("e.g.") }
    for example in wrong { print("  \(example)") }
}

/// The lines every outdoor unit's nameplate has, the same for heat pumps and air conditioners.
private func nameplate(brand: String, model: String) -> [TextLine] {
    let serial = String((0..<10).map { _ in "0123456789".randomElement(using: &random)! })
    let texts = [brand.uppercased(), "MODEL NO. \(model)", "SERIAL NO. \(serial)", "VOLTS 208/230  PH 1  HZ 60",
                 "REFRIGERANT R-410A  FACTORY CHARGE 6 LBS 2 OZ", "MIN. CIRCUIT AMPACITY 18.6", "MAX. FUSE OR CKT. BKR. 30 A",
                 "COMPRESSOR RLA 13.5  LRA 77", "FAN MOTOR FLA 1.2  HP 1/6"]
    return texts.enumerated().map { index, text in
        TextLine(text: text, box: CGRect(x: 0.1, y: 0.05 + Double(index) * 0.08, width: 0.6, height: 0.05))
    }
}
