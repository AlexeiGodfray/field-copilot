import CoreGraphics
import Foundation

/// Database lookups on 2,000 listed models from each source, read right, cut short, or misread. A wrong
/// type is the costly outcome; no answer is safe, since the rules and Apple Intelligence still get a turn.
func measureLookups() {
    heading("Lookup: listed models read right, cut short, or misread")
    let usable = EquipmentDatabase.allListings().filter { $0.kind != nil && ListedModel(printed($0)) != nil }
    let byGroup = Dictionary(grouping: usable, by: group)
    let sample = byGroup.keys.sorted().flatMap { byGroup[$0]!.shuffled(using: &random).prefix(2000) }
    print("\(sample.count) listings: up to 2,000 from each of \(byGroup.keys.sorted().joined(separator: ", "))")

    report("Read right", sample.map { listing in (printed(listing), listing) })
    for cut in [1, 2] {
        report("Last \(cut == 1 ? "character" : "2 characters") missing", sample.compactMap { listing in
            let model = printed(listing)
            return ListedModel.characters(model).count > cut + 5 ? (String(model.dropLast(cut)), listing) : nil
        })
    }
    let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
    report("One character misread as any other", sample.map { listing in
        var model = Array(printed(listing))
        let index = model.indices.filter { model[$0].isLetter || model[$0].isNumber }.randomElement(using: &random)!
        model[index] = alphabet.filter { $0 != model[index] }.randomElement(using: &random)!
        return (String(model), listing)
    })
    measureLookalikes(sample)
}

private func report(_ title: String, _ reads: [(text: String, listing: EquipmentDatabase.Listing)]) {
    var right = 0, none = 0, wrong: [String] = []
    for (text, listing) in reads {
        guard let match = EquipmentDatabase.lookup(text) else { none += 1; continue }
        if match.listing.kind == nil || match.listing.kind == listing.kind {
            right += 1
        } else {
            wrong.append("\(text): a \(listing.kind!.displayName.lowercased()), found \(match.listing.listedAs), a \(match.listing.kind!.displayName.lowercased())")
        }
    }
    print("\n\(title) (\(reads.count)):")
    print("  right type  \(percent(right, reads.count).rightAligned(6))\n  no answer   \(percent(none, reads.count).rightAligned(6))\n"
          + "  WRONG type  \(percent(wrong.count, reads.count).rightAligned(6))")
    for example in wrong.prefix(3) { print("    e.g. \(example)") }
}

/// A look-alike misread (O for 0, S for 5) after MODEL, through the whole label check, which corrects
/// look-alikes against the lists.
private func measureLookalikes(_ sample: [EquipmentDatabase.Listing]) {
    var fixed = 0, kept = 0, shortened = 0, empty = 0, other: [String] = []
    var tried = 0
    for listing in sample {
        let model = Array(printed(listing))
        guard let index = model.indices.filter({ EquipmentDatabase.lookalikes[model[$0]] != nil }).randomElement(using: &random) else { continue }
        var misread = model
        misread[index] = EquipmentDatabase.lookalikes[model[index]]!.randomElement(using: &random)!
        tried += 1
        let line = TextLine(text: "MODEL \(String(misread))", box: CGRect(x: 0.1, y: 0.1, width: 0.6, height: 0.04))
        let got = ListedModel.characters(LabelRules.check(.empty, lines: [line]).model.value ?? "")
        if got == ListedModel.characters(String(model)) { fixed += 1 }
        else if got == ListedModel.characters(String(misread)) { kept += 1 }
        else if got.isEmpty { empty += 1 }
        else if ListedModel.characters(String(model)).starts(with: got) { shortened += 1 }
        else { other.append("\(String(model)) misread \(String(misread)), read as \(String(got))") }
    }
    print("\nOne look-alike misread, after the label check (\(tried)):")
    print("  corrected                       \(percent(fixed, tried).rightAligned(6))")
    print("  left as read                    \(percent(kept, tried).rightAligned(6))")
    print("  corrected, later words left off \(percent(shortened, tried).rightAligned(6))")
    print("  no model                        \(percent(empty, tried).rightAligned(6))")
    print("  ANOTHER model                   \(percent(other.count, tried).rightAligned(6))")
    for example in other.prefix(3) { print("    e.g. \(example)") }
}
