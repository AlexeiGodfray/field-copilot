import Foundation

/// How many listed models the model-number rules also decode. The lists only carry models sold today, so
/// for an older unit the rules are what's left: a maker's share here is roughly how much of its line-up,
/// old or new, the rules can read.
func measureCoverage() {
    heading("Coverage: listed models the model-number rules also decode")
    var byKind: [String: (listed: Int, decoded: Int)] = [:]
    var byMaker: [String: (listed: Int, decoded: Int, kinds: Set<String>)] = [:]
    var seen = Set<String>()
    for listing in EquipmentDatabase.allListings() {
        guard let kind = listing.kind?.displayName, !listing.model.hasPrefix("*") else { continue }
        let forms = printedForms(listing)
        // The same model on two lists counts once.
        guard seen.insert("\(kind)|\(String(ListedModel.characters(forms[0])))").inserted else { continue }
        let decoded = forms.contains { ModelLookup.allMatches($0).first != nil }
        let maker = listing.maker.isEmpty ? "(no maker: DOE's central AC list)" : listing.maker
        byKind[kind, default: (0, 0)].listed += 1
        byMaker[maker, default: (0, 0, [])].listed += 1
        byMaker[maker]!.kinds.insert(kind)
        if decoded {
            byKind[kind]!.decoded += 1
            byMaker[maker]!.decoded += 1
        }
    }
    let listed = byKind.values.reduce(0) { $0 + $1.listed }
    let decoded = byKind.values.reduce(0) { $0 + $1.decoded }
    print("Listed models: \(listed). The rules also decode \(decoded) (\(percent(decoded, listed))).\n")
    print("By type:")
    for (kind, count) in byKind.sorted(by: { ($0.value.listed, $0.key) > ($1.value.listed, $1.key) }) {
        print("  \(kind.padded(18)) \(String(count.listed).rightAligned(6)) listed  \(percent(count.decoded, count.listed).rightAligned(6)) decoded")
    }
    print("\nThe 30 makers with the most listed models:")
    for (maker, count) in byMaker.sorted(by: { ($0.value.listed, $0.key) > ($1.value.listed, $1.key) }).prefix(30) {
        print("  \(String(maker.prefix(36)).padded(36)) \(String(count.listed).rightAligned(6))  \(percent(count.decoded, count.listed).rightAligned(6))  "
              + count.kinds.sorted().joined(separator: ", ").prefix(50))
    }
    let withRules = byMaker.values.filter { $0.decoded * 10 >= $0.listed }
    print("\nMakers whose rules decode at least 10% of their listed models: \(withRules.count) of \(byMaker.count)")
}
