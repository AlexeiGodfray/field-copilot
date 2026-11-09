import Foundation

/// When a unit was made, decoded from its serial number using the manufacturer's format.
struct SerialDate: Equatable {
    let year: Int
    /// Nil when the serial pins the year but not the month.
    let month: Int?
    /// How the date was read from the serial, e.g. "week 11, year 07 (Carrier format)".
    let explanation: String
}

/// Decodes manufacture dates from serial numbers. Each brand has its own format, and several
/// brands share serial shapes with different meanings (Rheem WWYY vs ICP YYWW), so the brand must
/// be known and each format only accepts its exact shape. A wrong format would give a confidently
/// wrong age.
///
/// Formats were checked against manufacturer documents and recall notices that list each maker's
/// serial ranges (Lennox nomenclature guide, Rheem TSB 1207, Bradford White's age page, CPSC and
/// Health Canada recalls for Carrier, Goodman, Trane, Rheem and A. O. Smith, Tesla's serial number
/// spec checked against 81 dated Tesla Energy serials), plus home-inspector references where nothing
/// official exists (ICP).
enum SerialDecoder {
    static func decode(brand: String?, serial: String?, kind: EquipmentKind = .unknown, now: Date = .now) -> SerialDate? {
        guard let brand, let serial else { return nil }
        let key = brand.uppercased().filter(\.isLetter)
        let code = serial.uppercased().filter { $0.isLetter || $0.isNumber }
        return formats.lazy
            .filter { $0.brands.contains(where: key.contains) }
            .compactMap { $0.decode(code, kind, now) }
            .first { isPlausible($0, now: now) }
    }

    /// Whether we have a format for this brand at all.
    static func knowsFormat(for brand: String) -> Bool {
        let key = brand.uppercased().filter(\.isLetter)
        return formats.contains { $0.brands.contains(where: key.contains) }
    }

    // MARK: Formats

    private struct Format {
        /// Brand names as uppercase letters only.
        let brands: [String]
        let decode: (_ serial: String, _ kind: EquipmentKind, _ now: Date) -> SerialDate?
    }

    private static let icpBrands = ["ICP", "INTERNATIONALCOMFORT", "HEIL", "TEMPSTAR", "COMFORTMAKER", "ARCOAIRE",
                                    "KEEPRITE", "AIRQUEST", "DAYNIGHT"]

    private static let formats: [Format] = [
        Format(brands: ["LENNOX"]) { s, _, now in
            // PP YY M ####(#): plant, year, month letter (no I). "1913H18804" is August 2013.
            guard let m = s.wholeMatch(of: #/\d{2}(\d{2})([A-HJ-M])\d{4,5}/#),
                  let month = monthFromLetter(m.2) else { return nil }
            let year = fullYear(m.1, now)
            return SerialDate(year: year, month: month,
                              explanation: "year \(m.1), month \(m.2) = \(monthName(month)) (Lennox format)")
        },
        Format(brands: icpBrands) { s, _, now in
            // L YY WW #####: plant letter, year, week. "X172563114" is week 25 of 2017.
            // Same shape as Rheem HVAC serials, but year comes before week.
            guard let m = s.wholeMatch(of: #/[A-Z](\d{2})(\d{2})\d{5}/#) else { return nil }
            let year = fullYear(m.1, now)
            guard let week = Int(m.2), let month = monthOfWeek(week, year) else { return nil }
            return SerialDate(year: year, month: month,
                              explanation: "year \(m.1), week \(m.2) (ICP format)")
        },
        Format(brands: ["CARRIER", "BRYANT", "PAYNE", "DAYNIGHT"]) { s, _, now in
            // WW YY L #####: week, year, plant letter. "1107E27968" is week 11 of 2007.
            guard let m = s.wholeMatch(of: #/(\d{2})(\d{2})[A-Z]\d{5}/#) else { return nil }
            let year = fullYear(m.2, now)
            guard let week = Int(m.1), let month = monthOfWeek(week, year) else { return nil }
            return SerialDate(year: year, month: month,
                              explanation: "week \(m.1), year \(m.2) (Carrier format)")
        },
        Format(brands: ["RHEEM", "RUUD", "RICHMOND"]) { s, kind, now in decodeRheem(s, kind, now) },
        Format(brands: ["GOODMAN", "AMANA", "DAIKIN"]) { s, _, now in
            // YY MM ######, all digits: "1408123456" is August 2014.
            guard let m = s.wholeMatch(of: #/(\d{2})(\d{2})\d{6}/#),
                  let month = Int(m.2), (1...12).contains(month) else { return nil }
            return SerialDate(year: fullYear(m.1, now), month: month,
                              explanation: "year \(m.1), month \(m.2) (Goodman format)")
        },
        Format(brands: ["TRANE", "AMERICANSTANDARD"]) { s, _, now in
            // 2010 on, 10 characters: YY WW D #####. "13461ABCDE" is week 46 of 2013.
            if let m = s.wholeMatch(of: #/(\d{2})(\d{2})\d[A-Z0-9]{5}/#), fullYear(m.1, now) >= 2010 {
                let year = fullYear(m.1, now)
                guard let week = Int(m.2), let month = monthOfWeek(week, year) else { return nil }
                return SerialDate(year: year, month: month,
                                  explanation: "year \(m.1), week \(m.2) (Trane format since 2010)")
            }
            // 2002–2009, 8–9 characters: Y WW D ####. "81422S41G" is week 14 of 2008.
            if let m = s.wholeMatch(of: #/(\d)(\d{2})\d[A-Z0-9]{4,5}/#) {
                let year = 2000 + Int(m.1)!
                guard let week = Int(m.2), let month = monthOfWeek(week, year) else { return nil }
                return SerialDate(year: year, month: month,
                                  explanation: "year \(m.1), week \(m.2) (Trane format, 2002–2009)")
            }
            return nil  // 1983–2001 serials start with a year letter whose table sources disagree on
        },
        Format(brands: ["AOSMITH", "STATE", "RELIANCE", "AMERICANWATERHEATER", "USCRAFTMASTER"]) { s, _, now in
            // About 2008 on (American Water Heater since the 1990s): YY WW first. "1452A012345" is week 52 of 2014.
            if let m = s.prefixMatch(of: #/(\d{2})(\d{2})/#) {
                let year = fullYear(m.1, now)
                guard let week = Int(m.2), let month = monthOfWeek(week, year) else { return nil }
                return SerialDate(year: year, month: month,
                                  explanation: "year \(m.1), week \(m.2) (A. O. Smith format)")
            }
            // Before about 2008: an optional plant character, a month letter (no I), then YY. "C05…" is March 2005.
            // The letter table is confirmed for the 2000s (CPSC); sources disagree on earlier units, so give only the year.
            if let m = s.prefixMatch(of: #/[A-Z0-9]?([A-HJ-M])(\d{2})/#), let month = monthFromLetter(m.1) {
                let year = fullYear(m.2, now)
                guard year >= 2000 else {
                    return SerialDate(year: year, month: nil,
                                      explanation: "year \(m.2) (A. O. Smith format before 2000, whose month letters aren't confirmed)")
                }
                return SerialDate(year: year, month: month,
                                  explanation: "month \(m.1) = \(monthName(month)), year \(m.2) (A. O. Smith format before 2008)")
            }
            return nil
        },
        Format(brands: ["BRADFORDWHITE"]) { s, _, now in
            // Year letter, month letter. Year letters skip I, O, Q, R, U, V and repeat every 20 years,
            // so take the latest cycle that isn't in the future: "KM…" is December 2013 (or 1993).
            guard let m = s.prefixMatch(of: #/([A-Z])([A-Z])/#),
                  let index = Array("ABCDEFGHJKLMNPSTWXYZ").firstIndex(of: Character(String(m.1))),
                  let month = monthFromLetter(m.2)
            else { return nil }
            let base = 1984 + index  // A = 1984, 2004, 2024
            let thisYear = Calendar.current.component(.year, from: now)
            guard let year = [base + 40, base + 20, base].first(where: { $0 <= thisYear }) else { return nil }
            return SerialDate(year: year, month: month,
                              explanation: "year \(m.1) = \(year) (or \(year - 20)), month \(m.2) = \(monthName(month)) (Bradford White format)")
        },
        Format(brands: ["TESLA"]) { s, _, _ in
            // Tesla's serial number spec: build site (3), year (2), day of year (3), ID (6), as in
            // "TG126172000YTT" = Gigafactory 1, day 172 of 2026. Barcodes add an S in front. Only the month
            // is shown: nothing confirms the exact day. Early Powerwall 2 packs use T, year, month letter.
            if let m = s.wholeMatch(of: #/S?([A-Z][A-Z0-9]{2})(\d{2})(\d{3})[A-Z0-9]{6}/#),
               let year = Int(m.2).map({ 2000 + $0 }), year >= 2015, let day = Int(m.3), let month = monthOfDay(day, year) {
                return SerialDate(year: year, month: month, explanation: "year \(m.2), day \(m.3) of the year (Tesla format)")
            }
            if let m = s.wholeMatch(of: #/T(\d{2})([A-L])\d{6,7}/#), let year = Int(m.1).map({ 2000 + $0 }), year >= 2015,
               let month = Array("ABCDEFGHIJKL").firstIndex(of: Character(String(m.2))).map({ $0 + 1 }) {
                return SerialDate(year: year, month: month,
                                  explanation: "year \(m.1), month \(m.2) = \(monthName(month)) (older Tesla format)")
            }
            return nil
        },
    ]

    /// Rheem, Ruud and Richmond, water heaters and HVAC.
    /// - Water heaters before 2012 and some older furnaces: [letters] MM YY, then a letter or 6 digits.
    /// - Water heaters from 2012 and HVAC: [letters] plant letter, WW YY, 5 digits.
    /// - Some HVAC: plant letter and WW YY in the middle, "7351 M2806 16735".
    /// Month and week sit in the same place, so when the type and era don't settle it, only the year is given.
    private static func decodeRheem(_ s: String, _ kind: EquipmentKind, _ now: Date) -> SerialDate? {
        // The older style ended in 2012, so it only applies to month 1–12 and years up to 2012.
        if let m = s.wholeMatch(of: #/[A-Z]*(\d{2})(\d{2})(?:[A-Z]\d{5}|\d{6})/#),
           let month = Int(m.1), (1...12).contains(month), fullYear(m.2, now) <= 2012 {
            return SerialDate(year: fullYear(m.2, now), month: month,
                              explanation: "month \(m.1), year \(m.2) (older Rheem format)")
        }
        let match = s.wholeMatch(of: #/[A-Z]+(\d{2})(\d{2})\d{5}[A-Z]?/#).map { ($0.1, $0.2) }
            ?? s.firstMatch(of: #/\d[A-Z](\d{2})(\d{2})\d/#).map { ($0.1, $0.2) }
        guard let (first, yy) = match, let number = Int(first) else { return nil }
        let year = fullYear(yy, now)
        let isHVAC = [.airConditioner, .heatPump, .airConditionerOrHeatPump, .furnace, .airHandler].contains(kind)

        if number > 12 || year >= 2013 || isHVAC {
            guard let month = monthOfWeek(number, year) else { return nil }
            return SerialDate(year: year, month: month,
                              explanation: "week \(first), year \(yy) (Rheem format)")
        }
        if kind == .waterHeater, year <= 2011 {
            return SerialDate(year: year, month: number,
                              explanation: "month \(first), year \(yy) (Rheem water heater format before 2012)")
        }
        return SerialDate(year: year, month: nil,
                          explanation: "year \(yy) (Rheem format; the month depends on whether it's a water heater or an HVAC unit)")
    }

    // MARK: Helpers

    /// Month letters as most manufacturers use them: A = January … M = December, skipping I.
    private static func monthFromLetter(_ letter: Substring) -> Int? {
        Array("ABCDEFGHJKLM").firstIndex(of: Character(String(letter))).map { $0 + 1 }
    }

    /// A two-digit year as the latest full year that isn't in the future: 13 is 2013, 98 is 1998.
    private static func fullYear(_ digits: Substring, _ now: Date) -> Int {
        let yy = Int(digits)!
        let thisYear = Calendar.current.component(.year, from: now)
        return 2000 + yy <= thisYear ? 2000 + yy : 1900 + yy
    }

    /// The month a day of the year falls in. Nil for an impossible day.
    private static func monthOfDay(_ day: Int, _ year: Int) -> Int? {
        let calendar = Calendar(identifier: .gregorian)
        guard day >= 1, let january1 = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let date = calendar.date(byAdding: .day, value: day - 1, to: january1),
              calendar.component(.year, from: date) == year
        else { return nil }
        return calendar.component(.month, from: date)
    }

    /// The month a manufacturing week falls in, taking the middle of the week counted from January 1
    /// (how Rheem, Carrier and Trane count). Nil for an impossible week.
    private static func monthOfWeek(_ week: Int, _ year: Int) -> Int? {
        guard (1...53).contains(week) else { return nil }
        let calendar = Calendar(identifier: .gregorian)
        guard let january1 = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let midWeek = calendar.date(byAdding: .day, value: 7 * (week - 1) + 3, to: january1)
        else { return nil }
        return calendar.component(.year, from: midWeek) == year ? calendar.component(.month, from: midWeek) : 12
    }

    private static func isPlausible(_ date: SerialDate, now: Date) -> Bool {
        let calendar = Calendar.current
        let thisYear = calendar.component(.year, from: now)
        let thisMonth = calendar.component(.month, from: now)
        return date.year >= 1960 && (date.year < thisYear || (date.year == thisYear && (date.month ?? 1) <= thisMonth))
    }

    static func monthName(_ month: Int) -> String {
        DateFormatter().monthSymbols[month - 1]
    }
}

/// What the app shows for when a unit was made: the date printed on the label if there is one,
/// otherwise the date decoded from the serial.
enum ManufactureAge {
    static func describe(_ label: CheckedLabel, now: Date = .now) -> CheckedField {
        let fromSerial = SerialDecoder.decode(brand: label.brand.value, serial: label.serial.value, kind: label.kind, now: now)

        if let printed = label.manufactureDate.value,
           let match = printed.wholeMatch(of: #/(\d{4})(?:-(\d{2}))?/#), let year = Int(match.1) {
            let month = match.2.flatMap { Int($0) }
            // Printed month unreadable, but the serial agrees on the year: take the serial's month.
            if month == nil, label.manufactureDate.source != .person, let fromSerial, fromSerial.year == year,
               let serialMonth = fromSerial.month {
                return CheckedField(value: "\(text(year, serialMonth)) · \(age(year, serialMonth, now))", source: .rule,
                                    note: "Year from the label, month from the serial: \(fromSerial.explanation)")
            }
            // Printed: the date's own note (Apple Intelligence, a hard-to-read month), and whether the serial agrees.
            var notes = [label.manufactureDate.note]
            if let fromSerial {
                let agrees = fromSerial.year == year && (month == nil || fromSerial.month == nil || fromSerial.month == month)
                notes.append(agrees ? "The serial agrees" : "The serial suggests \(text(fromSerial.year, fromSerial.month)) instead")
            }
            let note = notes.compactMap { $0 }.joined(separator: ". ")
            return CheckedField(value: "\(text(year, month)) · \(age(year, month ?? 6, now))",
                                source: label.manufactureDate.source, note: note.isEmpty ? nil : note)
        }

        if let fromSerial {
            return CheckedField(value: "\(text(fromSerial.year, fromSerial.month)) · \(age(fromSerial.year, fromSerial.month ?? 6, now))",
                                source: .rule, note: "From the serial: \(fromSerial.explanation)")
        }

        guard label.serial.value != nil else { return CheckedField() }
        guard let brand = label.brand.value else {
            return CheckedField(note: "Need the brand to decode the serial")
        }
        return CheckedField(note: SerialDecoder.knowsFormat(for: brand)
            ? "This serial doesn't match \(brand)'s date format"
            : "Don't know \(brand)'s serial format yet")
    }

    /// "Aug 2013", or just "2013" when the month isn't known.
    static func text(_ year: Int, _ month: Int?) -> String {
        guard let month else { return String(year) }
        return "\(DateFormatter().shortMonthSymbols[month - 1]) \(year)"
    }

    /// A stored date, "2019-05" or "2019", as shown: "May 2019" or "2019".
    static func text(dateText: String) -> String {
        guard let match = dateText.wholeMatch(of: #/(\d{4})(?:-(\d{2}))?/#), let year = Int(match.1) else { return dateText }
        return text(year, match.2.flatMap { Int($0) })
    }

    /// "13 years old", counting whole years from the month it was made.
    static func age(_ year: Int, _ month: Int, _ now: Date) -> String {
        let calendar = Calendar.current
        let months = (calendar.component(.year, from: now) - year) * 12 + calendar.component(.month, from: now) - month
        let years = max(0, months / 12)
        switch years {
        case 0: return "under a year old"
        case 1: return "1 year old"
        default: return "\(years) years old"
        }
    }
}
