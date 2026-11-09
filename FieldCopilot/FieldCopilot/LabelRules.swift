import CoreGraphics
import Foundation

/// A label field after the rules have checked it.
struct CheckedField {
    enum Source { case llm, rule, barcode, person }

    var value: String?
    /// Where the value came from: Apple Intelligence, a rule (the label text, the model number, ENERGY STAR
    /// or the serial), a barcode, or a person who corrected it.
    var source: Source?
    /// Shown under the value when it adds something: where a derived value came from, a confirmation, or
    /// what was changed or rejected. Nil for a value read straight off the label.
    var note: String?
}

/// What was read from a label: the rules' reading, with any gaps filled by Apple Intelligence and checked.
struct CheckedLabel {
    var brand: CheckedField
    var kind: EquipmentKind
    /// Where the type came from, or why it was changed. Nil when it's unknown.
    var kindNote: String?
    var model: CheckedField
    var serial: CheckedField
    var manufactureDate: CheckedField
    /// Capacity and similar specs, e.g. "3 tons · R-410A": decoded from the model number, or from the listing.
    var size: String?
    /// Where the specs came from: "the model number", "ENERGY STAR", "DOE" or "the California Energy Commission".
    var sizeSource: String?
    /// The model number's listing in the equipment database, when it's listed.
    var listing: EquipmentDatabase.Match?
}

/// Values a person typed in to correct or fill in the reading. Each one wins over what was read, and the
/// rules work from it: a corrected model number changes the brand, type, specs, ENERGY STAR and age.
struct LabelEdits: Codable, Equatable {
    var brand: String?
    var kind: EquipmentKind?
    var model: String?
    var serial: String?
    /// "YYYY-MM", or "YYYY" when the month isn't known.
    var manufactureDate: String?
}

extension EquipmentKind: Codable {}

extension EquipmentLabel {
    /// No LLM answer: what the rules read on their own.
    static let empty = EquipmentLabel(brand: nil, kind: .unknown, model: nil, serial: nil, manufactureDate: nil)
}

extension CheckedLabel {
    /// Fields the rules couldn't fill, which the LLM is asked about.
    var hasGaps: Bool {
        kind == .unknown || brand.value == nil || model.value == nil || serial.value == nil
    }
}

/// Reads the label with deterministic rules first: the equipment database (official lists of certified
/// models), then the model-number rules for units the lists don't have. The LLM only fills fields the rules
/// leave empty, and its answers are checked against the label:
///  1. Model, serial and brand must appear in the label text.
///  2. A value can't be a keyword like SERIAL (or an OCR misspelling of one, like SERTAL).
///  3. Model and serial must differ.
///  4. Model and serial must look like codes: digits, and letters for models, sensible length.
///  5. The date must be YYYY-MM and its year must be printed on the label.
///  6. The value printed right after MODEL / SERIAL wins over a different LLM value.
///  7. Brand: a known brand printed on the label, then the database, then the model-number rules, then the LLM.
///     A model sold under several brands shows its maker and the brands it's sold as.
///  8. Type: the database, then the model-number rules, then clues printed on the label, then the LLM.
///     Specs: the model-number rules (nominal sizes), then the database (rated values).
///  9. A barcode within two characters of a model or serial confirms it, or corrects OCR's misread.
/// 10. A model the database doesn't list, but would with one look-alike character changed (O and 0,
///     S and 5…), is the listed model.
/// 11. A value a person typed in wins, and the rules work from it.
/// 12. With no MODEL keyword on the label, a code that matches a listed model is the model, and it wins
///     over a different LLM answer.
enum LabelRules {
    static func check(_ label: EquipmentLabel, lines: [TextLine], barcodes: [Barcode] = [],
                      edits: LabelEdits = LabelEdits()) -> CheckedLabel {
        let texts = lines.map(\.text)
        var model = checkCode(label.model, .model, lines: lines)
        var serial = checkCode(label.serial, .serial, lines: lines)

        // Rule 3: the same value in both fields, so neither can be trusted.
        if let m = model.value, let s = serial.value, compact(m) == compact(s) {
            model = CheckedField(note: "“\(m)” was read as both the model and the serial number, so neither is used")
            serial = CheckedField(note: "“\(s)” was read as both the model and the serial number, so neither is used")
        }

        model = applyBarcodes(barcodes, to: model)
        serial = applyBarcodes(barcodes, to: serial)
        // With no SERIAL keyword, a long number printed with its barcode is the serial: solar panels print
        // theirs that way (Qcells 204025294504600812). It beats Apple Intelligence's pick.
        if serial.source != .barcode, serial.source != .rule,
           let number = printedBarcode(barcodes, texts: texts, model: model.value), compact(number) != compact(serial.value ?? "") {
            serial = CheckedField(value: number, source: .barcode,
                                  note: ["From the barcode", serial.value.map { "Apple Intelligence read “\($0)”" }].compactMap { $0 }.joined(separator: ". "))
        }

        // Rule 11, before the lookups so they work from what the person typed.
        model = edited(model, to: edits.model)
        serial = edited(serial, to: edits.serial)

        // Rule 10. Barcodes are exact and a person's value is what they meant, so only OCR and LLM values are corrected.
        var listed = EquipmentDatabase.lookup(model.value)
        if listed == nil, model.source != .barcode, model.source != .person, let value = model.value,
           let fix = EquipmentDatabase.correction(value) {
            // The corrected code can take in words printed after it: "6DVT-50L 3" is GDVT-50L 3.
            let rest = texts.lazy.compactMap { text in text.range(of: value).map { text[$0.upperBound...] } }.first ?? ""
            let fixed = modelCode(in: fix.model + rest) ?? fix.model
            model = CheckedField(value: fixed, source: .rule,
                                 note: [model.note, "\(fix.change) to match \(fix.match.listing.source.spoken)'s list (read as “\(value)”)"]
                                     .compactMap { $0 }.joined(separator: ". "))
            listed = EquipmentDatabase.lookup(fixed) ?? fix.match
        }

        let modelInfo = ModelLookup.lookup(model.value)
        var (kind, kindNote) = checkKind(label.kind, evidence: label.typeEvidence, texts: texts, modelInfo: modelInfo, listed: listed)
        if let edit = edits.kind, edit != kind {
            kindNote = kind == .unknown ? enteredByPerson : "\(changedByPerson) from \(kind.displayName.lowercased())"
            kind = edit
        }
        let date = checkDate(label.manufactureDate, texts: texts)
        return CheckedLabel(
            brand: edited(checkBrand(label.brand, texts: texts, modelInfo: modelInfo, listed: listed), to: edits.brand),
            kind: kind,
            kindNote: kindNote,
            model: model,
            serial: serial,
            manufactureDate: edited(date, to: edits.manufactureDate, shown: { ManufactureAge.text(dateText: $0) }),
            size: modelInfo?.size ?? listed?.listing.specs,
            sizeSource: modelInfo?.size != nil ? "the model number" : listed?.listing.specs != nil ? listed?.listing.source.spoken : nil,
            listing: listed
        )
    }

    static let enteredByPerson = "Entered by you"
    static let changedByPerson = "Changed by you"

    /// Rule 11: a person's value replaces what was read, noting what it was. The same code typed again
    /// isn't a change.
    static func edited(_ field: CheckedField, to edit: String?, shown: (String) -> String = { $0 }) -> CheckedField {
        guard let edit = edit?.trimmingCharacters(in: .whitespacesAndNewlines), !edit.isEmpty else { return field }
        guard let read = field.value else { return CheckedField(value: edit, source: .person, note: enteredByPerson) }
        if compact(read) == compact(edit) { return field }
        return CheckedField(value: edit, source: .person, note: "\(changedByPerson) from “\(shown(read))”")
    }

    // MARK: Model and serial

    enum Code {
        case model, serial

        var name: String { self == .model ? "model number" : "serial number" }

        /// Keyword phrases as words, longest first so "SERIAL NO" wins over "SERIAL".
        var keywords: [[String]] {
            switch self {
            case .model: [["MODEL", "NUMBER"], ["MODEL", "NO"], ["MOD", "NO"], ["MODEL"], ["MOD"], ["M/N"]]
            // TSN and (S): Tesla gateway labels and barcode stickers.
            case .serial: [["SERIAL", "NUMBER"], ["SERIAL", "NO"], ["SER", "NO"], ["SERIAL"], ["SER"], ["S/N"], ["SN"], ["TSN"], ["(S)"]]
            }
        }

        /// Used only when none of the main keywords is on the label. Battery and solar labels often print
        /// a part number instead of a model ("TESLA PART NO. 1707000-21-M"), but on an HVAC label a part
        /// number printed above the model isn't the model.
        var fallbackKeywords: [[String]] {
            switch self {
            case .model: [["PART", "NUMBER"], ["PART", "NO"], ["P/N"], ["TPN"], ["(P)"]]
            case .serial: []
            }
        }
    }

    static func checkCode(_ llmValue: String?, _ code: Code, lines: [TextLine]) -> CheckedField {
        let texts = lines.map(\.text)
        var printed = valueAfterKeyword(code, lines: lines)
        // Rule 12: no keyword, but a code on the label is a listed model.
        var foundNote: String?
        if printed == nil, code == .model, let found = listedModel(in: lines) {
            printed = found.model
            foundNote = "Found on the label: it's a model \(found.source) lists"
        }

        guard let llmValue, !llmValue.isEmpty else {
            return CheckedField(value: printed, source: printed == nil ? nil : .rule, note: foundNote)
        }

        let value = removingKeyword(cleanCode(llmValue), code)
        if let problem = problem(with: value, code, texts: texts) {
            let note = [foundNote, aiRejected(llmValue, problem)].compactMap { $0 }.joined(separator: ". ")
            return CheckedField(value: printed, source: printed == nil ? nil : .rule, note: note)
        }
        // Rules 6 and 12: what's printed after the keyword, or a listed model, beats a different LLM answer.
        if let printed, compact(printed) != compact(value) {
            let reason = foundNote == nil ? "a different value is printed after the keyword" : "a listed model is printed on the label"
            return CheckedField(value: printed, source: .rule, note: [foundNote, aiRejected(llmValue, reason)].compactMap { $0 }.joined(separator: ". "))
        }
        if let printed {
            return CheckedField(value: printed, source: .rule, note: foundNote)
        }
        return CheckedField(value: printedSpacing(of: value, in: texts), source: .llm, note: readByAI)
    }

    static let readByAI = "Read by Apple Intelligence"

    static func aiRejected(_ answer: String, _ problem: String) -> String {
        "Apple Intelligence read “\(answer)”, but \(problem)"
    }

    /// A word printed like a field name: followed by "." or ":" and then a code, as "ERA. X172563114", where
    /// OCR misread SERIAL on a blurry label.
    static func isFieldName(_ word: String, texts: [String]) -> Bool {
        guard let regex = try? Regex("(?i)(?:^|\\s)\(NSRegularExpression.escapedPattern(for: word))\\s*[.:]\\s+\\S*\\d") else { return false }
        return texts.contains { $0.contains(regex) }
    }

    /// A code with the spaces it's printed with. Apple Intelligence leaves them out: "GS640YBRT" is
    /// printed "GS6 40 YBRT".
    static func printedSpacing(of value: String, in texts: [String]) -> String {
        let target = compact(value)
        for text in texts {
            let words = codeWords(in: text)
            for start in words.indices {
                var joined = ""
                for end in start..<words.count {
                    joined += compact(words[end])
                    if joined == target { return words[start...end].joined(separator: " ") }
                    if !target.hasPrefix(joined) { break }
                }
            }
        }
        return value
    }

    /// Why a model or serial value can't be trusted, or nil if it passes rules 1, 2 and 4.
    static func problem(with value: String, _ code: Code, texts: [String]) -> String? {
        if isKeyword(value) { return "that's a keyword, not a value" }
        if !looksLike(code, value) { return "it doesn't look like a \(code.name)" }
        // Each line joined with the next, since OCR sometimes splits one code across two lines.
        let printed = texts.indices.map { compact(texts[$0] + (texts.indices.contains($0 + 1) ? texts[$0 + 1] : "")) }
        if !printed.contains(where: { $0.contains(compact(value)) }) { return "it isn't on the label" }
        return nil
    }

    static func looksLike(_ code: Code, _ value: String) -> Bool {
        let c = compact(value)
        let hasDigit = c.contains(where: \.isNumber)
        let hasLetter = c.contains(where: \.isLetter)
        switch code {
        case .model: return (4...25).contains(c.count) && hasDigit && hasLetter
        case .serial: return (6...20).contains(c.count) && hasDigit
        }
    }

    /// The value printed after a keyword like "SERIAL NO.": on the same line, or when the keyword
    /// stands alone, the text to its right on the same row (two-column labels), else the next line
    /// (stacked labels). Takes the first match from the top of the label.
    static func valueAfterKeyword(_ code: Code, lines: [TextLine]) -> String? {
        for phrases in [code.keywords, code.fallbackKeywords] where !phrases.isEmpty {
            if let value = valueAfterKeyword(code, phrases, lines: lines) { return value }
        }
        return nil
    }

    private static func valueAfterKeyword(_ code: Code, _ phrases: [[String]], lines: [TextLine]) -> String? {
        for (index, line) in lines.enumerated() {
            // A keyword stuck to its value is two words: "SERIAL NO.4271U49305".
            let text = line.text.uppercased().replacing(#/\b(NO|MODEL|SERIAL|M\/N|S\/N|SN|MOD|SER)([.:#]+)(?=[A-Z0-9])/#) { "\($0.output.1)\($0.output.2) " }
            let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
            guard let (start, length) = keywordLength(words, phrases).map({ (0, $0) }) ?? keywordLater(in: words, phrases) else { continue }
            let rest = words.dropFirst(start + length).joined(separator: " ")
            let next = (lineRight(of: line, in: lines) ?? (lines.indices.contains(index + 1) ? lines[index + 1] : nil))?.text ?? ""
            let restWords = codeWords(in: rest)
            let candidate: String
            if restWords.isEmpty {
                candidate = next
            } else if restWords.count == 1, restWords[0].count <= 3, firstCode(in: next) != nil, !startsWithKeyword(next) {
                candidate = restWords[0] + next  // OCR split a big first character onto its own line: "SERIAL 1" + "107E27968"
            } else {
                candidate = rest
            }
            if let value = code == .model ? modelCode(in: candidate, correcting: true) : firstCode(in: candidate), looksLike(code, value) {
                return value
            }
        }
        return nil
    }

    /// Rule 12: the first code on the label, from the top, that the equipment database lists. Only a word with
    /// letters and digits, six or more of them, so a voltage or a certification number can't be taken.
    static func listedModel(in lines: [TextLine]) -> (model: String, source: String)? {
        for line in lines {
            let words = codeWords(in: line.text)
            for start in words.indices {
                let word = words[start]
                let characters = ListedModel.characters(word)
                guard characters.count >= 6, characters.contains(where: \.isLetter), characters.contains(where: \.isNumber),
                      !isKeyword(word), !isMeasurement(word),
                      let model = modelCode(in: words[start...].joined(separator: " ")),
                      let match = EquipmentDatabase.lookup(model)
                else { continue }
                return (model, match.listing.source.spoken)
            }
        }
        return nil
    }

    /// The model number at the start of some text. Some are printed with spaces ("PROPH50 T2 RH375-15",
    /// "GS6 40 YBRT"), so a later word joins it when a model-number rule or a listing accounts for it.
    /// After a MODEL keyword, `correcting` also lets it join when one look-alike change makes it listed
    /// ("5FC 125" is SFC 125). Stops at the next keyword, a measurement like 240V, or a long code like a serial.
    static func modelCode(in text: String, correcting: Bool = false) -> String? {
        let words = codeWords(in: text).prefix { !isKeyword($0) && !isMeasurement($0) }
        guard let first = words.first else { return nil }
        let accounts = { (model: String, before: String) in
            (EquipmentDatabase.matchedLength(model) ?? 0) > ListedModel.characters(before).count
        }
        var best = first
        var joined = first
        for word in words.dropFirst().prefix(5) {
            guard word.count <= 8 else { break }
            let before = joined
            joined += " " + word
            if ModelLookup.lookup(joined) != nil || accounts(joined, before)
                || (correcting && EquipmentDatabase.correction(joined).map { accounts($0.model, before) } == true) {
                best = joined
            }
        }
        return best
    }

    /// A reading like 240V, 4500W or 60HZ: printed next to codes on labels, never part of one.
    static func isMeasurement(_ word: String) -> Bool {
        word.uppercased().wholeMatch(of: #/\d+(?:[.,]\d+)?(?:V|VAC|W|KW|A|AMPS?|HZ|GALS?|PSIG?|LBS?|BTUH?)/#) != nil
    }

    /// True when a line starts with a model or serial keyword, so it holds another field.
    static func startsWithKeyword(_ text: String) -> Bool {
        let words = text.uppercased().split(whereSeparator: \.isWhitespace).map(String.init)
        let phrases = Code.model.keywords + Code.model.fallbackKeywords + Code.serial.keywords
        return keywordLength(words, phrases) != nil || words.first.map { isKeyword($0) } == true
    }

    /// The nearest line to the right of `keyword` on the same row. OCR can read a two-column label
    /// column by column, so the next line in reading order isn't always the keyword's value.
    static func lineRight(of keyword: TextLine, in lines: [TextLine]) -> TextLine? {
        lines
            .filter { $0.box.minX > keyword.box.midX && abs($0.box.midY - keyword.box.midY) < keyword.box.height * 0.6 }
            .min { $0.box.minX < $1.box.minX }
    }

    /// A keyword partway along a line that starts with the other field's keyword: "M/N: X  S/N: Y". Only
    /// then, so a sentence like "USE WITH MODEL …" isn't read as the model.
    static func keywordLater(in words: [String], _ phrases: [[String]]) -> (start: Int, length: Int)? {
        let any = Code.model.keywords + Code.model.fallbackKeywords + Code.serial.keywords
        guard keywordLength(words, any) != nil else { return nil }
        for start in words.indices.dropFirst() {
            if let length = keywordLength(Array(words[start...]), phrases) { return (start, length) }
        }
        return nil
    }

    /// How many leading words of a line form a keyword, allowing one OCR typo in long words, a label
    /// border read as a stray character in front ("IM/N" is "M/N"), and a brand first ("TESLA PART NO.").
    static func keywordLength(_ words: [String], _ phrases: [[String]]) -> Int? {
        let trimmed = words.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".:#")) }
        guard let first = trimmed.first else { return nil }
        let startsWithBrand = knownBrands.contains { $0.key == first.filter(\.isLetter) }
        for skip in startsWithBrand ? [0, 1] : [0] {
            var rest = Array(trimmed.dropFirst(skip))
            guard let head = rest.first else { continue }
            for candidateFirst in [head, droppingBorder(head)] {
                rest[0] = candidateFirst
                for phrase in phrases where rest.count >= phrase.count {
                    if zip(rest, phrase).allSatisfy({ nearlyEqual($0, $1) }) {
                        return skip + phrase.count
                    }
                }
            }
        }
        return nil
    }

    /// Removes one leading character that is usually a label's printed border read as text.
    static func droppingBorder(_ word: String) -> String {
        guard word.count > 1, let first = word.first, "I|l1[(".contains(first) else { return word }
        return String(word.dropFirst())
    }

    // MARK: Barcodes

    /// Rule 9. Barcodes decode exactly or not at all, so a barcode within two characters of a
    /// model or serial is the same code: it confirms the value, or replaces OCR's misread.
    /// A barcode value that's also printed on the label, mostly digits and not a model number: a serial.
    static func printedBarcode(_ barcodes: [Barcode], texts: [String], model: String?) -> String? {
        let printed = texts.map(compact)
        return barcodes.flatMap { barcodeValues($0.payload) }.first { value in
            let code = compact(value)
            return code.count >= 8 && code.count { $0.isNumber } * 5 >= code.count * 4 && printed.contains { $0.contains(code) }
                && code != compact(model ?? "") && EquipmentDatabase.lookup(value) == nil && ModelLookup.lookup(value) == nil
        }
    }

    static func applyBarcodes(_ barcodes: [Barcode], to field: CheckedField) -> CheckedField {
        guard let value = field.value else { return field }
        let target = compact(value)
        let candidates = barcodes.flatMap { barcodeValues($0.payload) }
        guard let match = candidates.first(where: { compact($0) == target })
                ?? candidates.first(where: { isSameCode(compact($0), target) })
        else { return field }

        var result = field
        if compact(match) == target {
            result.note = [field.note, "Matches the barcode"].compactMap { $0 }.joined(separator: ". ")
        } else {
            result.value = match
            result.source = .barcode
            result.note = "Corrected from “\(value)” to match the barcode"
        }
        return result
    }

    /// The values a barcode carries. One payload can hold several fields on separate lines, or joined by
    /// colons as on Tesla labels ("P1707000-21-M:STG126172000YTT"), each often led by a data identifier
    /// that isn't part of the value: "S1913H18804" is serial 1913H18804. Values without the identifier
    /// come first so they win near-matches.
    static func barcodeValues(_ payload: String) -> [String] {
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{1D}\u{1E}\u{04}:"))
        return payload.components(separatedBy: separators).filter { !$0.isEmpty }.flatMap { part in
            if let match = part.wholeMatch(of: #/(?:1S|S|1P|P)(.{6,})/#) {
                return [String(match.1), part]
            }
            return [part]
        }
    }

    /// Close enough to be one code with a couple of characters misread.
    static func isSameCode(_ a: String, _ b: String) -> Bool {
        min(a.count, b.count) >= 6 && abs(a.count - b.count) <= 1 && editDistance(a, b) <= 2
    }

    // MARK: Brand and date

    /// Common brands, as printed (letters only) and as shown. Used when the LLM's brand fails.
    static let knownBrands: [(key: String, name: String)] = [
        ("RHEEM", "Rheem"), ("RUUD", "Ruud"), ("AOSMITH", "A. O. Smith"), ("BRADFORDWHITE", "Bradford White"),
        ("RINNAI", "Rinnai"), ("NAVIEN", "Navien"), ("CARRIER", "Carrier"), ("BRYANT", "Bryant"),
        ("LENNOX", "Lennox"), ("TRANE", "Trane"), ("AMERICANSTANDARD", "American Standard"),
        ("GOODMAN", "Goodman"), ("AMANA", "Amana"), ("DAIKIN", "Daikin"), ("YORK", "York"),
        ("MITSUBISHI", "Mitsubishi"), ("FUJITSU", "Fujitsu"), ("ENPHASE", "Enphase"),
        ("SOLAREDGE", "SolarEdge"), ("TESLA", "Tesla"), ("GENERAC", "Generac"), ("FRONIUS", "Fronius"),
        ("SQUARED", "Square D"), ("EATON", "Eaton"), ("SIEMENS", "Siemens"), ("PAYNE", "Payne"),
        ("HEIL", "Heil"), ("TEMPSTAR", "Tempstar"), ("COMFORTMAKER", "Comfortmaker"), ("ARCOAIRE", "Arcoaire"),
        ("KEEPRITE", "KeepRite"), ("AIRQUEST", "Airquest"), ("DAYNIGHT", "Day & Night"),
        // Parent company last, so a brand printed on the same label wins.
        ("INTERNATIONALCOMFORTPRODUCTS", "ICP"),
    ]

    /// Certification bodies and standards whose logos sit on most nameplates. Never the brand.
    static let certificationMarks: Set<String> = [
        "AHRI", "ARI", "UL", "ULLISTED", "ETL", "ETLLISTED", "CSA", "INTERTEK", "ENERGYSTAR", "ASME", "NSF",
        "CEC", "DOE", "IAPMO", "CE", "TUV", "FCC",
    ]

    /// Rule 7: a known brand printed on the label, then the database, then the model-number rules, then the LLM.
    static func checkBrand(_ llmBrand: String?, texts: [String], modelInfo: ModelInfo? = nil,
                           listed: EquipmentDatabase.Match? = nil) -> CheckedField {
        let printed = knownBrands.first { brand in texts.contains { wordRuns($0, keeping: \.isLetter).contains(brand.key) } }
        // California's archive lists a model under whichever brands filed it there (R4A442 only as Smart Comfort,
        // though ICP sells it under ten), so the model-number rules' brands win over it.
        let listed = listed?.listing.source.isArchive == true && modelInfo != nil ? nil : listed

        // Printed on the label: no note, unless the database or the model number names other brands.
        if let printed, printed.name != "ICP" {
            let isPrinted = { (brand: String) in brand.uppercased().filter(\.isLetter) == printed.key }
            var note: String?
            if let listed, !listed.brands.isEmpty, !listed.brands.contains(where: isPrinted) {
                note = "\(listed.listing.source.spoken.prefix(1).uppercased() + listed.listing.source.spoken.dropFirst()) lists this model as \(listed.brands.formatted(.list(type: .or)))"
            } else if listed == nil, let modelInfo, !modelInfo.brands.contains(where: isPrinted) {
                note = "The model number is a \(modelInfo.brands.formatted(.list(type: .or))) model"
            }
            return CheckedField(value: printed.name, source: .rule, note: note)
        }
        // A listing with no brand (an indoor unit) leaves the brand to the model-number rules.
        if let listed, !listed.brands.isEmpty {
            return lookedUpBrand(listed.brands, maker: listed.listing.maker, from: listed.listing.source.spoken)
        }
        if let modelInfo {
            return lookedUpBrand(modelInfo.brands, maker: modelInfo.manufacturer, from: "the model number")
        }
        if let printed {
            return CheckedField(value: printed.name, source: .rule,
                                note: "The label names the maker, International Comfort Products, not the brand")
        }

        guard let llmBrand, !llmBrand.isEmpty else { return CheckedField() }
        let key = llmBrand.uppercased().filter(\.isLetter)
        let problem: String? =
            isKeyword(llmBrand) ? "that's a keyword, not a brand"
            : certificationMarks.contains(key) ? "that's a certification mark, not a brand"
            : isFieldName(llmBrand, texts: texts) ? "it's printed like a field name, before a value"
            : texts.contains(where: { $0.uppercased().filter(\.isLetter).contains(key) }) ? nil
            : "it isn't on the label"
        guard let problem else { return CheckedField(value: llmBrand, source: .llm, note: readByAI) }
        return CheckedField(note: aiRejected(llmBrand, problem))
    }

    /// A brand from a lookup: the brand itself, or for a model sold under several brands, the maker
    /// and the brands it's sold as.
    static func lookedUpBrand(_ brands: [String], maker: String, from source: String) -> CheckedField {
        guard brands.count > 1 else {
            return CheckedField(value: brands.first ?? maker, source: .rule, note: "From \(source)")
        }
        return CheckedField(value: maker, source: .rule,
                            note: "Sold as \(brands.formatted(.list(type: .or))). The label doesn't say which")
    }

    static func checkDate(_ llmDate: String?, texts: [String]) -> CheckedField {
        let printed = printedDate(texts: texts)
        let fromRule = printed.map { date in
            CheckedField(value: date.text, source: .rule, note: date.month == nil ? "The month is hard to read" : nil)
        }

        guard let llmDate, !llmDate.isEmpty else { return fromRule ?? CheckedField() }
        guard let match = llmDate.wholeMatch(of: #/(\d{4})(?:-(\d{2}))?/#) else {
            return fromRule ?? CheckedField(note: aiRejected(llmDate, "that isn't a date"))
        }
        let year = String(match.1)
        let month = match.2.map(String.init)
        guard let y = Int(year), y <= Calendar.current.component(.year, from: .now) else {
            return CheckedField(value: fromRule?.value, source: fromRule?.source, note: aiRejected(llmDate, "that's in the future"))
        }
        // The year as a number of its own: 2027 inside a certificate number like 1111220277 doesn't count.
        let standsAlone = (try? Regex("(?:^|\\D)\(year)(?:\\D|$)")).map { regex in { (text: String) in text.contains(regex) } } ?? { _ in false }
        let shortForms = month.map { ["\($0)/\(year.suffix(2))", "\($0)-\(year.suffix(2))"] } ?? []
        guard texts.contains(where: { text in standsAlone(text) || shortForms.contains(where: text.contains) }) else {
            let note = aiRejected(llmDate, "that date isn't printed on the label")
            return CheckedField(value: fromRule?.value, source: fromRule?.source, note: note)
        }
        // The date after the keyword wins when it clearly disagrees.
        if let printed, Int(year) != printed.year || (printed.month != nil && month.flatMap { Int($0) } != printed.month) {
            return CheckedField(value: printed.text, source: .rule,
                                note: aiRejected(llmDate, "a different date is printed after MANUFACTURE DATE / MFD"))
        }
        if let printed, printed.month == nil, month != nil {
            return CheckedField(value: llmDate, source: .llm, note: "\(readByAI). The month is hard to read on the label")
        }
        return fromRule ?? CheckedField(value: llmDate, source: .llm, note: readByAI)
    }

    /// The date printed after a keyword like MANUFACTURE DATE, MFD or MFG, as year and month.
    /// The month is nil when it isn't printed or is too garbled to tell ("JUA" could be Jun or Jul).
    static func printedDate(texts: [String]) -> (year: Int, month: Int?, text: String)? {
        let keyword = #/(?:DATE OF MANUFACTURE|MANUFACTURED|MANUFACTURE DATE|MFG\.? DATE|MFR\.? DATE|MFD|MFG)\.?\s*:?\s*(.*)/#
        for (index, text) in texts.enumerated() {
            guard let match = text.uppercased().firstMatch(of: keyword) else { continue }
            let rest = String(match.1)
            let next = texts.indices.contains(index + 1) ? texts[index + 1].uppercased() : ""
            if let date = parseDate(rest) ?? (rest.isEmpty ? parseDate(next) : nil) {
                let text = date.month.map { String(format: "%04d-%02d", date.year, $0) } ?? String(date.year)
                return (date.year, date.month, text)
            }
        }
        return nil
    }

    static let monthAbbreviations = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]

    static func parseDate(_ text: String) -> (year: Int, month: Int?)? {
        func valid(_ year: Int) -> Bool { (1970...Calendar.current.component(.year, from: .now)).contains(year) }
        if let m = text.firstMatch(of: #/(\d{4})[\/\-.](\d{1,2})\b/#), let y = Int(m.1), valid(y), let mo = Int(m.2), (1...12).contains(mo) {
            return (y, mo)
        }
        if let m = text.firstMatch(of: #/\b(\d{1,2})[\/\-.](\d{4})/#), let y = Int(m.2), valid(y), let mo = Int(m.1), (1...12).contains(mo) {
            return (y, mo)
        }
        if let m = text.firstMatch(of: #/\b([A-Z]{3})[A-Z]*[\s\-\/.,]*(\d{4})/#), let y = Int(m.2), valid(y) {
            let word = String(m.1)
            let exact = monthAbbreviations.firstIndex(of: word)
            let close = monthAbbreviations.indices.filter { editDistance(monthAbbreviations[$0], word) <= 1 }
            return (y, (exact ?? (close.count == 1 ? close[0] : nil)).map { $0 + 1 })
        }
        if let m = text.firstMatch(of: #/\b(\d{4})\b/#), let y = Int(m.1), valid(y) {
            return (y, nil)
        }
        return nil
    }

    // MARK: Equipment type

    /// Words printed on a label that settle what kind of equipment it is, strongest first.
    static let kindClues: [(clue: String, words: Set<String>, allowed: [EquipmentKind])] = [
        ("“HEAT PUMP” is printed on the label", ["HEATPUMP"], [.heatPump]),
        ("A heating rating, defrost or a reversing valve is printed on the label", ["HSPF", "HSPF2", "DEFROST", "REVERSINGVALVE"],
         [.heatPump]),
        ("“COOLING ONLY” is printed on the label", ["COOLINGONLY"], [.airConditioner]),
        ("“WATER HEATER” is printed on the label", ["WATERHEATER"], [.waterHeater]),
        ("A tank size in gallons is printed on the label", ["GAL", "GALLON", "GALLONS"], [.waterHeater]),
        // Air conditioner or heat pump, unless Apple Intelligence found printed words that say which.
        ("A compressor or refrigerant is listed on the label", ["COMPRESSOR", "R410A", "HFC410A", "R454B", "R32", "R22"],
         [.airConditionerOrHeatPump, .airConditioner, .heatPump]),
        // Before the inverter clue: a battery with a built-in inverter (Powerwall 3) is a battery.
        ("“POWERWALL” or “BATTERY ENERGY STORAGE” is printed on the label",
         ["POWERWALL", "BATTERYENERGYSTORAGE", "ENERGYSTORAGESYSTEM"], [.battery]),
        ("“INVERTER” is printed on the label", ["INVERTER", "MICROINVERTER"], [.solarInverter]),
        ("“LOAD CENTER” or “PANELBOARD” is printed on the label", ["LOADCENTER", "PANELBOARD"], [.electricalPanel]),
    ]

    /// Rule 8: the database, then the model-number rules, then clues printed on the label, then the LLM. Apple
    /// Intelligence can't tell a heat pump from an air conditioner by the model number (it called nearly every heat
    /// pump the rules don't decode an air conditioner: measure_accuracy.sh heatpumps), so its choice between them
    /// counts only with `evidence`, words it found printed on the label that say which.
    static func checkKind(_ answer: EquipmentKind, evidence: String? = nil, texts: [String], modelInfo: ModelInfo? = nil,
                          listed: EquipmentDatabase.Match? = nil) -> (EquipmentKind, String?) {
        let saidOtherwise = { (kind: EquipmentKind) in
            answer == .unknown || answer == kind ? "" : ". Apple Intelligence said \(answer.displayName.lowercased())"
        }
        let letters = { (text: String) in text.uppercased().filter { $0.isLetter || $0.isNumber } }
        let key = letters(evidence ?? "")
        // Not "SUB COOLING", printed on air conditioners and heat pumps alike.
        let typeWords = answer == .heatPump ? ["HEATPUMP", "HEATING", "HSPF", "DEFROST", "REVERSING"] : ["COOLINGONLY", "AIRCONDITIONER"]
        let evidenced = key.count >= 4 && texts.contains { letters($0).contains(key) } && typeWords.contains { key.contains($0) }
        let llmKind = [.airConditioner, .heatPump].contains(answer) && !evidenced ? .airConditionerOrHeatPump : answer
        let readByAI = evidenced ? "\(Self.readByAI) from “\(evidence!)” on the label" : Self.readByAI
        let unsure = "Nothing printed says whether it also heats, and the model number doesn't. Look for HEAT PUMP on the label or a reversing valve"
        // The rules have been checked against California's archive and fixed where it was right (Bryant's old
        // packaged units). Where they still disagree it's mostly the archive (Ruud's UGRC furnaces filed as outdoor
        // units), so a decoded type wins over it.
        let listed = listed?.listing.source.isArchive == true && modelInfo?.kind != nil ? nil : listed
        if let decoded = listed.flatMap({ match in match.listing.kind.map { ($0, match.listing.source.spoken) } })
            ?? modelInfo?.kind.map({ ($0, "the model number") }) {
            let (kind, source) = decoded
            return (kind, "From \(source)\(saidOtherwise(kind))")
        }
        let printed = texts.reduce(into: Set<String>()) { $0.formUnion(wordRuns($1, keeping: { $0.isLetter || $0.isNumber })) }
        guard let match = kindClues.first(where: { !$0.words.isDisjoint(with: printed) }) else {
            return (llmKind, llmKind == .unknown ? nil : llmKind == .airConditionerOrHeatPump ? unsure : readByAI)
        }
        // A clue that allows several types (a compressor: air conditioner or heat pump) leaves the choice to Apple
        // Intelligence.
        if match.allowed.contains(llmKind) {
            if llmKind == .airConditionerOrHeatPump { return (llmKind, "\(match.clue). \(unsure)") }
            return (llmKind, match.allowed.count == 1 ? match.clue : readByAI)
        }
        let kind = match.allowed[0]
        return (kind, kind == .airConditionerOrHeatPump ? "\(match.clue). \(unsure)\(saidOtherwise(kind))" : "\(match.clue)\(saidOtherwise(kind))")
    }

    // MARK: Text helpers

    static let keywordWords = ["SERIAL", "MODEL", "NUMBER", "SERIALNO", "MODELNO", "S/N", "M/N", "PROD", "MFD", "MFG"]

    /// True when the whole value is a keyword, allowing one OCR typo (SERTAL is SERIAL).
    static func isKeyword(_ value: String) -> Bool {
        let c = compact(value).trimmingCharacters(in: CharacterSet(charactersIn: ".:#"))
        return keywordWords.contains { nearlyEqual(c, $0) }
    }

    /// Drops a keyword the LLM left on the front of a value, e.g. "M/N13HPX" or "IM/N13HPX" becomes "13HPX".
    /// Not "SN", "TSN" or "TPN": a code can start with those letters.
    static func removingKeyword(_ value: String, _ code: Code) -> String {
        for candidate in [value, droppingBorder(value)] {
            let upper = candidate.uppercased()
            for phrase in code.keywords + code.fallbackKeywords where !["SN", "TSN", "TPN"].contains(phrase.joined()) {
                let prefix = phrase.joined()
                if upper.hasPrefix(prefix), upper.count > prefix.count {
                    return String(candidate.dropFirst(prefix.count)).trimmingCharacters(in: CharacterSet(charactersIn: ".:#"))
                }
            }
        }
        return value
    }

    /// Uppercase, one kind of dash, no whitespace: how values are compared.
    static func compact(_ text: String) -> String {
        unifyDashes(text).uppercased().filter { !$0.isWhitespace }
    }

    /// The standard way to show a code: one kind of dash, no whitespace, no stray punctuation at the ends.
    static func cleanCode(_ text: String) -> String {
        unifyDashes(text).filter { !$0.isWhitespace }.trimmingCharacters(in: CharacterSet(charactersIn: ".:#,;"))
    }

    /// The first code in some text.
    static func firstCode(in text: String) -> String? {
        codeWords(in: text).first
    }

    /// The words of some text as codes, with OCR's spaces around dashes removed ("13HPX -048 - 18" is
    /// "13HPX-048-18") and stray punctuation trimmed.
    static func codeWords(in text: String) -> [String] {
        unifyDashes(text).replacing(#/\s*-\s*/#, with: "-").split(whereSeparator: \.isWhitespace)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".:#,;")) }
            .filter { !$0.isEmpty }
    }

    static func unifyDashes(_ text: String) -> String {
        String(text.map { "‐‑‒–—−".contains($0) ? "-" : $0 })
    }

    /// A line's words, uppercased and keeping only some characters, plus each run of two and three
    /// words joined, so "A. O. SMITH" matches as "AOSMITH" and "HFC-410A" as "HFC410A".
    static func wordRuns(_ text: String, keeping keep: (Character) -> Bool) -> Set<String> {
        let words = text.uppercased().split(whereSeparator: \.isWhitespace).map { $0.filter(keep) }.filter { !$0.isEmpty }
        var result = Set(words)
        for length in 2...3 where words.count >= length {
            for start in 0...(words.count - length) {
                result.insert(words[start..<(start + length)].joined())
            }
        }
        return result
    }

    /// Equal, or one edit apart for words of five letters or more.
    static func nearlyEqual(_ a: String, _ b: String) -> Bool {
        a == b || (min(a.count, b.count) >= 5 && editDistance(a, b) <= 1)
    }

    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var row = Array(0...b.count)
        for i in 1...max(a.count, 1) where !a.isEmpty {
            var previous = row[0]
            row[0] = i
            for j in 1...max(b.count, 1) where !b.isEmpty {
                let current = row[j]
                row[j] = min(row[j] + 1, row[j - 1] + 1, previous + (a[i - 1] == b[j - 1] ? 0 : 1))
                previous = current
            }
        }
        return row[b.count]
    }
}
