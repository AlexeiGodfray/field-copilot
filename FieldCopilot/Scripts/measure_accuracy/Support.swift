import Foundation

/// The same random numbers on every run (SplitMix64), so results only change when the code or data does.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

var random = SeededGenerator(seed: 2026)

func percent(_ part: Int, _ whole: Int) -> String {
    whole == 0 ? "–" : String(format: "%.1f%%", Double(part) * 100 / Double(whole))
}

func heading(_ title: String) {
    print("\n== \(title)\n")
}

extension String {
    func padded(_ width: Int) -> String { padding(toLength: max(width, count), withPad: " ", startingAt: 0) }
    func rightAligned(_ width: Int) -> String { count >= width ? self : String(repeating: " ", count: width - count) + self }
}

/// A listing as its source writes it, made ready to print: no add-on kit (where the source writes kits
/// after a +), no trailing wildcards, the first of each choice, and placeholders like XX filled.
private func ready(_ listing: EquipmentDatabase.Listing) -> String {
    let kits = listing.source.hasKits
    let beforeKit = listing.model.prefix { $0 != "+" }
    var text = String(kits && beforeKit.count { $0.isLetter || $0.isNumber } >= 5 ? beforeKit : Substring(listing.model))
        .uppercased().trimmingCharacters(in: .whitespaces)
    while let last = text.last, "*#- ".contains(last) { text.removeLast() }
    text = text.replacing(#/[\(\[]([^,\)\]]*)[^\)\]]*[\)\]]/#) { String($0.output.1) }
    text = text.replacing(#/([-\s])([XY]{1,3})(?=[-\s]|$)/#) { $0.output.1 + String(repeating: "1", count: $0.output.2.count) }
    return text.replacingOccurrences(of: "#", with: "*")
}

/// A listing as a label prints it, each wildcard filled with `fill`.
func printed(_ listing: EquipmentDatabase.Listing, fill: Character = "A") -> String {
    ready(listing).replacingOccurrences(of: "*", with: String(fill))
}

/// The ways a label might print a listing: each wildcard (one character or none) left out, only the first
/// filled, or all filled with a common letter or digit.
func printedForms(_ listing: EquipmentDatabase.Listing) -> [String] {
    let text = ready(listing)
    guard let first = text.range(of: "*") else { return [text] }
    var firstOnly = text
    firstOnly.replaceSubrange(first, with: "A")
    return [text.replacingOccurrences(of: "*", with: ""), firstOnly.replacingOccurrences(of: "*", with: "")]
        + ["A", "0", "1", "N", "S"].map { text.replacingOccurrences(of: "*", with: $0) }
}

/// Where a listing comes from, for grouping results.
func group(_ listing: EquipmentDatabase.Listing) -> String {
    listing.source.isEnergyStar ? "ENERGY STAR" : listing.source.isDOE ? "DOE" : listing.source.isArchive ? "CEC archive" : "CEC"
}

/// Brand names compared by letters only.
func brandKey(_ name: String) -> String { name.uppercased().filter(\.isLetter) }

/// Model and serial numbers compared by letters and digits only.
func sameCode(_ a: String?, _ b: String) -> Bool { ListedModel.characters(a ?? "") == ListedModel.characters(b) }
