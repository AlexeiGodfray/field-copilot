import CoreGraphics
import Foundation

/// Text on every label that isn't a model number: serial numbers in common formats and other codes. Any
/// that matches a listing could be taken as the model when a label has no MODEL keyword (rule 12).
func measureFalseMatches() {
    heading("Serials: label text mistaken for a listed model")
    func digits(_ n: Int) -> String { String((0..<n).map { _ in "0123456789".randomElement(using: &random)! }) }
    func letters(_ n: Int) -> String { String((0..<n).map { _ in "ABCDEFGHJKLMNPRSTUVWXYZ".randomElement(using: &random)! }) }
    func mixed(_ n: Int) -> String { String((0..<n).map { _ in "ABCDEFGHJKLMNPRSTUVWXYZ0123456789".randomElement(using: &random)! }) }
    // Carrier and Lennox, ICP and Rheem, Goodman, A. O. Smith, Bradford White, Trane, Tesla, Enphase,
    // SolarEdge, Qcells.
    let formats: [(name: String, make: () -> String)] = [
        ("4 digits, letter, 5 digits", { digits(4) + letters(1) + digits(5) }),
        ("letter, 9 digits", { letters(1) + digits(9) }),
        ("10 digits", { digits(10) }),
        ("4 digits, letter, 6 digits", { digits(4) + letters(1) + digits(6) }),
        ("2 letters, 8 digits", { letters(2) + digits(8) }),
        ("9 digits, letter", { digits(9) + letters(1) }),
        ("Tesla: TG1 and 11 characters", { "TG1" + digits(5) + mixed(6) }),
        ("12 digits", { digits(12) }),
        ("8 characters, dash, 2", { mixed(8) + "-" + mixed(2) }),
        ("18 digits", { digits(18) }),
    ]
    let line = { (text: String) in [TextLine(text: text, box: CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.04))] }
    var matched = 0, taken = 0, total = 0
    var examples: [String] = []
    for format in formats {
        var formatMatched = 0, formatTaken = 0
        for _ in 0..<500 {
            let serial = format.make()
            if let match = EquipmentDatabase.lookup(serial) {
                formatMatched += 1
                examples.append("\(serial) matched \(match.listing.listedAs)")
            }
            if LabelRules.listedModel(in: line(serial)) != nil { formatTaken += 1 }
        }
        print("  \(format.name.padded(30)) matched a listing \(formatMatched)/500, taken as the model \(formatTaken)/500")
        matched += formatMatched
        taken += formatTaken
        total += 500
    }
    print("\nSerials: \(matched) of \(total) matched a listing (\(percent(matched, total))), \(taken) taken as the model (\(percent(taken, total)))")
    for example in examples.prefix(3) { print("  e.g. \(example)") }

    let other = ["R-410A", "R-454B", "208/230", "208-230V", "UL 1741", "UL1741-SA", "CSA C22.2", "E123456", "5005998", "ETL 3070678",
                 "IEC 61215:2016", "IEC61730", "IP65", "NEMA 3R", "LR95329", "MCA 18.6", "MOCP 30", "60HZ", "1PH", "AHRI 210/240",
                 "ANSI Z21.10.1", "CSA 4.3", "MFD 03/2019", "2019-03", "PN 5126789-01", "LOT 21B4", "Q.ANTUM", "ISOLATED",
                 "MAX 600VDC", "NON-ISOLATED", "TYPE 3R", "CLASS I", "SEER2 15.2", "HSPF2 7.8", "EER2 12.0"]
    let otherMatched = other.filter { EquipmentDatabase.lookup($0) != nil || LabelRules.listedModel(in: line($0)) != nil }
    print("Other label text: \(otherMatched.count) of \(other.count) matched a listing\(otherMatched.isEmpty ? "" : ": " + otherMatched.joined(separator: ", "))")
}
