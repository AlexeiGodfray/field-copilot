import Foundation
import SQLite3

/// Official lists of certified and listed equipment, bundled with the app as Equipment.sqlite so model numbers
/// are looked up offline: ENERGY STAR's certified heat pumps, central ACs, furnaces, water heaters, boilers and
/// geothermal heat pumps; DOE's certified central ACs and heat pumps with their coils and air handlers,
/// multi-split heat pumps, furnaces, boilers and water heaters; the California Energy Commission's solar
/// inverters, batteries, storage systems and panels; and its archive of central ACs, furnaces and boilers listed
/// from 1981 to 2023 and water heaters from 2019, no longer sold. Build it with Scripts/build_equipment_db.swift.
/// DOE and ENERGY STAR list only models sold today; each build keeps the listings that have since dropped off,
/// but units older than the first build aren't in it unless California archived them, so the model-number rules
/// cover those.
enum EquipmentDatabase {
    struct Source {
        let name: String
        /// Which of the source's lists, e.g. "certified heat pumps".
        let list: String
        /// When it was downloaded, YYYY-MM-DD.
        let retrieved: String
        /// When it was first downloaded: how far back listings that have dropped off it go.
        let since: String

        var isEnergyStar: Bool { name == "ENERGY STAR" }
        var isDOE: Bool { name == "DOE" }
        /// California's archive of models no longer sold.
        var isArchive: Bool { list.hasPrefix("archive") }
        /// Writes add-on kits after a `+`, as ENERGY STAR, DOE and California's archive do.
        var hasKits: Bool { isEnergyStar || isDOE || isArchive }
        /// The listing row's title: "ENERGY STAR", "DOE", "CEC listing" or "CEC archive".
        var title: String { isEnergyStar || isDOE ? name : isArchive ? "CEC archive" : "CEC listing" }
        /// As a sentence names it: "ENERGY STAR", "DOE", "the California Energy Commission".
        var spoken: String { isEnergyStar || isDOE ? name : "the \(name)" }
    }

    struct Listing {
        /// As listed, with the list's wildcards.
        let model: String
        /// The list's own text, before a leading choice is split: "(C,H,T)4H5S30*K*AAA*". Its brands are for
        /// the whole group.
        let listedAs: String
        let maker: String
        let brands: [String]
        /// Nil when the list doesn't say, as for ENERGY STAR's indoor units.
        let kind: EquipmentKind?
        /// What it is in plain words, e.g. "split system heat pump".
        let product: String
        /// E.g. "rated 34,200 BTU/h cooling · R-454B", "7.6 kW · 240 V", "13.5 kWh · 5 kW".
        let specs: String?
        /// E.g. "SEER2 15.2 · EER2 12 · HSPF2 7.8", "96% AFUE", "97.5% CEC efficiency".
        let ratings: String?
        let source: Source
        /// When it was last on its list, YYYY-MM-DD.
        let lastListed: String
        /// When it was first listed, YYYY-MM-DD, for the lists that say: California's archive.
        let firstListed: String?

        /// Still on the list as last downloaded, rather than kept after it dropped off.
        var isListed: Bool { lastListed >= source.retrieved }
        /// On a list of models sold today.
        var isSold: Bool { isListed && !source.isArchive }
    }

    /// A model number found in the lists: its best listing, the brands of every listing it matches, and its
    /// ENERGY STAR listing if it has one.
    struct Match {
        let listing: Listing
        let brands: [String]
        /// More than one when the label shows only the start of a longer listed model number.
        let count: Int
        let energyStar: Listing?
        /// A listing it matches is on a list of models sold today, though the best may be in California's archive.
        let isSold: Bool
    }

    /// Where the bundled database is. The Mac tests point this at the source file.
    static var fileURL = Bundle.main.url(forResource: "Equipment", withExtension: "sqlite")

    static func lookup(_ model: String?) -> Match? {
        guard let model else { return nil }
        let printed = ListedModel.characters(model)
        let matches = candidates(for: printed).compactMap { candidate in
            candidate.pattern.matchedLength(printed).map { (candidate: candidate, length: $0) }
        }
        let ranked = { (match: (candidate: Candidate, length: Int)) in rank(match.candidate, length: match.length) }
        guard let best = matches.max(by: { ranked($0) < ranked($1) })?.candidate else { return nil }
        var brands = best.listing.brands
        for match in matches where match.candidate.listing.maker == best.listing.maker {
            brands += match.candidate.listing.brands.filter { !brands.contains($0) }
        }
        let energyStar = matches.filter { $0.candidate.listing.source.isEnergyStar }.max { ranked($0) < ranked($1) }?.candidate.listing
        return Match(listing: best.listing, brands: brands, count: matches.count, energyStar: energyStar,
                     isSold: matches.contains { $0.candidate.listing.isSold })
    }

    /// The listing that accounts for most of the printed model wins (WAH24-2I is WAH24-2(I), the indoor unit,
    /// not WAH24-2(O)), then the most specific, then one that says what the equipment is, then the whole unit
    /// over a part listed on its own (Powerwall 3 is on the inverter list too, as are panels with built-in
    /// microinverters, and a packaged unit's gas heat is on the furnace list), then one sold today, then
    /// ENERGY STAR's over DOE's.
    private static func rank(_ candidate: Candidate, length: Int) -> (Int, Int, Int, Int, Int, Int) {
        let kind = candidate.listing.kind
        let wholeUnit = [.battery, .packagedUnit, .solarPanel].contains(kind)
        return (length, candidate.pattern.literals, kind == nil ? 0 : 1, wholeUnit ? 1 : 0, candidate.listing.isSold ? 1 : 0,
                candidate.listing.source.isEnergyStar ? 1 : 0)
    }

    /// How many letters and digits of a model number the best-fitting listing accounts for. Tells
    /// whether a word printed after a model number is part of it.
    static func matchedLength(_ model: String) -> Int? {
        let printed = ListedModel.characters(model)
        return candidates(for: printed).compactMap { $0.pattern.matchedLength(printed) }.max()
    }

    /// Characters OCR mixes up on nameplates.
    static let lookalikes: [Character: [Character]] = [
        "0": ["O", "D"], "O": ["0"], "D": ["0"], "1": ["I", "L"], "I": ["1"], "L": ["1"],
        "5": ["S"], "S": ["5"], "8": ["B"], "B": ["8"], "2": ["Z"], "Z": ["2"], "6": ["G"], "G": ["6"],
    ]

    /// A model the lists don't have, but would with one look-alike character changed:
    /// "XE5OT10HS45U0" is XE50T10HS45U0. Only when exactly one change finds a listing.
    static func correction(_ model: String) -> (model: String, change: String, match: Match)? {
        let characters = Array(model.uppercased())
        var found: [(model: String, change: String, match: Match)] = []
        for index in characters.indices {
            for replacement in lookalikes[characters[index]] ?? [] {
                var fixed = characters
                fixed[index] = replacement
                if let match = lookup(String(fixed)) {
                    found.append((String(fixed), "Changed \(characters[index]) to \(replacement)", match))
                }
            }
        }
        return found.count == 1 ? found[0] : nil
    }

    /// Types ENERGY STAR certifies, so a DOE listing can say it isn't on ENERGY STAR's list.
    private static let energyStarKinds: [EquipmentKind] = [.heatPump, .furnace, .waterHeater, .boiler]

    /// The listing row: the certification or listing with its ratings, or "Not listed" for a type the lists cover.
    static func describe(_ label: CheckedLabel) -> (title: String, field: CheckedField)? {
        if let match = label.listing {
            let listing = match.energyStar ?? match.listing
            let source = listing.source
            var note = "\(source.isEnergyStar || source.isDOE ? "Certified" : "Listed") \(listing.product)"
            // The listing only when it reads differently from the label: wildcards, or a longer model number.
            if label.model.value.map({ ListedModel.characters($0) != ListedModel.characters(listing.model) }) ?? true {
                note += ", listed as \(listing.listedAs)"
                if match.count > 1 { note += " and \(match.count - 1) more like it" }
            }
            // Ranges are over the indoor units it's certified with.
            if listing.ratings?.contains("–") == true { note += ". Ratings depend on the indoor unit" }
            if source.isDOE, let kind = listing.kind, energyStarKinds.contains(kind) { note += ". Not on ENERGY STAR's list" }
            // California's archive says when a model was first listed; a listing that dropped off, when it was last.
            if !match.isSold {
                note += source.isArchive ? ". No longer sold" + (listing.firstListed.map { ": first listed \($0.prefix(4))" } ?? "")
                    : ". No longer sold: last listed \(monthAndYear(listing.lastListed))"
            }
            return (source.title, CheckedField(value: listing.ratings ?? "Listed", source: .rule, note: note))
        }
        guard label.model.value != nil else { return nil }
        if ([.airConditioner, .airConditionerOrHeatPump, .packagedUnit] + energyStarKinds).contains(label.kind) {
            return ("DOE", CheckedField(value: "Not listed", source: .rule,
                                        note: "Not in DOE's or ENERGY STAR's lists of models sold since \(since), or California's archive of older models"))
        }
        if [.solarInverter, .battery, .solarPanel].contains(label.kind) {
            return ("CEC listing", CheckedField(value: "Not listed", source: .rule,
                                                note: "Not on the California Energy Commission's lists of solar equipment sold since \(since)"))
        }
        return nil
    }

    /// How far back the lists go, e.g. "Oct 2026": the first build's download.
    static var since: String {
        sources.values.map(\.since).min().map(monthAndYear) ?? ""
    }

    /// "2026-10-29" as "Oct 2026".
    static func monthAndYear(_ day: String) -> String {
        let format = Date.ISO8601FormatStyle(timeZone: .current).year().month().day()
        return (try? Date(day, strategy: format))?.formatted(.dateTime.month(.abbreviated).year()) ?? day
    }

    /// Every listing, for the tests.
    static func allListings() -> [Listing] {
        query(selectListings) { listing(from: $0) }
    }

    // MARK: Reading the database

    private typealias Candidate = (listing: Listing, pattern: ListedModel)

    private static let database: OpaquePointer? = {
        guard let path = fileURL?.path else { return nil }
        var database: OpaquePointer?
        guard sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(database)
            return nil
        }
        return database
    }()

    private static let sources: [Int: Source] = Dictionary(uniqueKeysWithValues: query("SELECT id, name, list, retrieved, since FROM sources") {
        ($0.int(0), Source(name: $0.text(1) ?? "", list: $0.text(2) ?? "", retrieved: $0.text(3) ?? "", since: $0.text(4) ?? ""))
    })

    private static let selectListings =
        "SELECT model, maker, brands, kind, product, specs, ratings, source, listed_as, last_listed, first_listed FROM listings"

    private static func listing(from row: Row) -> Listing {
        let source = sources[row.int(7)] ?? Source(name: "", list: "", retrieved: "", since: "")
        let model = row.text(0) ?? ""
        return Listing(model: model, listedAs: row.text(8) ?? model, maker: row.text(1) ?? "",
                       brands: (row.text(2) ?? "").split(separator: "|").map(String.init),
                       kind: row.text(3).flatMap(EquipmentKind.init(rawValue:)), product: row.text(4) ?? "",
                       specs: row.text(5), ratings: row.text(6),
                       source: source, lastListed: row.text(9) ?? source.retrieved, firstListed: row.text(10))
    }

    /// Listings that start with the same three characters, plus those with a wildcard, choice or placeholder in
    /// their first three (L(E,G)M48DJ), which any model number might match. Cached, since the look-alike
    /// correction and field finding look up many near-identical codes.
    private static var cache: [String: [Candidate]] = [:]

    private static let unindexed = candidates(query(selectListings + " WHERE key = ''") { listing(from: $0) })

    private static func candidates(for printed: [Character]) -> [Candidate] {
        guard printed.count >= 5 else { return [] }
        let key = String(printed.prefix(3))
        if let cached = cache[key] { return cached }
        let found = candidates(query(selectListings + " WHERE key = ?", [key]) { listing(from: $0) }) + unindexed
        cache[key] = found
        return found
    }

    private static func candidates(_ listings: [Listing]) -> [Candidate] {
        listings.compactMap { listing in
            ListedModel(listing.model, kits: listing.source.hasKits).map { (listing, $0) }
        }
    }

    private struct Row {
        let statement: OpaquePointer

        func text(_ column: Int32) -> String? {
            sqlite3_column_text(statement, column).map { String(cString: $0) }
        }

        func int(_ column: Int32) -> Int {
            Int(sqlite3_column_int64(statement, column))
        }
    }

    private static func query<T>(_ sql: String, _ arguments: [String] = [], _ map: (Row) -> T) -> [T] {
        guard let database else { return [] }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, argument) in arguments.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), argument, -1, transient)
        }
        var rows: [T] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append(map(Row(statement: statement)))
        }
        return rows
    }
}

/// A model number as a list writes it, matched against one read off a label. In listings `*` is one
/// character or none (N5H5S24*K*AAA* is printed N5H5S24AKAAA), `(C,H,T)` or `[C,U]` is one of the
/// choices, `(B)` may be left off but counts when printed, a segment of only X and Y letters is a
/// placeholder for one character each (1707000-XX-Y is printed 1707000-21-M), and dashes, slashes and dots
/// don't count. ENERGY STAR, DOE and California's archive write add-on kits after a `+` (37MURAQ48AA3+KSAIC0701230),
/// unless it comes too early to be one (PRO+G50-38U RU62); the California Energy Commission's solar lists use
/// `+` as part of the name (Q.TRON BLK M-G2.H+ 430). Listings often leave off the last characters (4TWV0048A1 is 4TWV0048A1000AA),
/// and a printed model may stop at a space in the listing (PROPH50 is the start of PROPH50 T2 RH375-15).
struct ListedModel {
    enum Token {
        case character(Character), any, one, oneOf([String])

        /// Can match nothing at the end of a printed model.
        var isOptional: Bool {
            switch self {
            case .character, .one: false
            case .any: true
            case .oneOf(let choices): choices.contains("")
            }
        }
    }

    let tokens: [Token]
    /// Token positions where a printed model may end: at each space in the listing.
    let stops: Set<Int>
    /// Fixed characters. More means a more specific listing.
    let literals: Int

    private static let brackets: [Character: Character] = ["(": ")", "[": "]"]

    init?(_ listing: String, kits: Bool = true) {
        var tokens: [Token] = []
        var stops: Set<Int> = []
        // Placeholder segments become "?", one per letter: "1707000-XX-Y" is "1707000-??-?".
        let marked = listing.replacing(#/([-\s])([XxYy]{1,3})(?=[-\s]|$)/#) { $0.output.1 + String(repeating: "?", count: $0.output.2.count) }
        let beforeKit = marked.prefix { $0 != "+" }
        let hasKit = kits && beforeKit.count { $0.isLetter || $0.isNumber } >= 5
        let text = Array((hasKit ? beforeKit : Substring(marked)).uppercased())
        var index = 0
        while index < text.count {
            let character = text[index]
            index += 1
            if let close = Self.brackets[character], let end = text[index...].firstIndex(of: close) {
                let choices = String(text[index..<end]).split(separator: ",", omittingEmptySubsequences: false)
                    .map { $0.filter { $0.isLetter || $0.isNumber } }
                tokens.append(.oneOf(choices.count > 1 ? choices : choices + [""]))
                index = end + 1
            } else if character == "*" || character == "#" {
                tokens.append(.any)
            } else if character == "?" {
                tokens.append(.one)
            } else if character.isWhitespace {
                if !tokens.isEmpty { stops.insert(tokens.count) }
            } else if character.isLetter || character.isNumber {
                tokens.append(.character(character))
            }
        }
        // Trailing wildcards needn't be printed. Trailing optional parts stay, to tell WAH24-2(I) from WAH24-2(O).
        while let last = tokens.last, case .any = last { tokens.removeLast() }
        let literals = tokens.count { if case .character = $0 { true } else { false } }
        guard literals >= 5 else { return nil }
        self.tokens = tokens
        self.stops = stops.filter { $0 < tokens.count }
        self.literals = literals
    }

    /// A model number as compared: uppercase letters and digits only.
    static func characters(_ model: String) -> [Character] {
        Array(model.uppercased().filter { $0.isLetter || $0.isNumber })
    }

    func matches(_ model: String) -> Bool { matches(Self.characters(model)) }

    func matches(_ printed: [Character]) -> Bool { matchedLength(printed) != nil }

    /// How many printed characters the listing accounts for, or nil when it's a different model.
    func matchedLength(_ printed: [Character], token: Int = 0, position: Int = 0) -> Int? {
        if token == tokens.count { return position }
        if position == printed.count {
            return tokens[token...].allSatisfy(\.isOptional) || (position >= 6 && stops.contains(token)) ? position : nil
        }
        switch tokens[token] {
        case .character(let c):
            return printed[position] == c ? matchedLength(printed, token: token + 1, position: position + 1) : nil
        case .one:
            return matchedLength(printed, token: token + 1, position: position + 1)
        case .any:
            return matchedLength(printed, token: token + 1, position: position + 1)
                ?? matchedLength(printed, token: token + 1, position: position)
        case .oneOf(let choices):
            return choices.lazy.compactMap { choice in
                printed[position...].starts(with: choice)
                    ? matchedLength(printed, token: token + 1, position: position + choice.count) : nil
            }.first
        }
    }
}
