// Tests for the deterministic serial-date decoder. Runs on the Mac, no simulator needed:
//   FieldCopilot/RuleTests/run.sh
// Cases come from manufacturer documents [MFR], government recall notices that list each
// maker's serial ranges [GOV], and home-inspector references where nothing official exists.

import Foundation

// Fixed "today" so expected ages don't drift. Cases come from manufacturer documents,
// recall notices and home-inspector references gathered in the research.
let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 21))!
var failures = 0
func expect(_ brand: String?, _ serial: String?, _ expected: String?, _ kind: EquipmentKind = .unknown, _ why: String) {
    let d = SerialDecoder.decode(brand: brand, serial: serial, kind: kind, now: now)
    let got = d.map { date in date.month.map { String(format: "%04d-%02d", date.year, $0) } ?? String(date.year) }
    let ok = got == expected
    if !ok { failures += 1 }
    print("\(ok ? "PASS" : "FAIL")  \(brand ?? "nil") \(serial ?? "nil") -> \(got ?? "nil") (want \(expected ?? "nil"))  \(why)")
}

print("-- Lennox")
expect("Lennox", "1913H18804", "2013-08", .heatPump, "your label")
expect("Lennox", "1912H09467", "2012-08", .airConditioner, "electrical-forensics")
expect("Lennox", "5178M99989", "1978-12", .unknown, "Lennox nomenclature guide [MFR]")
expect("Lennox", "1913I18804", nil, .unknown, "I is never a month letter")
print("-- ICP family")
expect("Arcoaire", "X172563114", "2017-06", .airConditioner, "your ICP label, printed Jun-2017")
expect("Heil", "E031136011", "2003-03", .unknown, "2003 week 11")
expect("Comfortmaker", "E072514528", "2007-06", .unknown, "2007 week 25")
expect("ICP", "1107E27968", nil, .unknown, "Carrier shape isn't an ICP serial")
print("-- Carrier / Bryant / Payne")
expect("Carrier", "1107E27968", "2007-03", .airConditioner, "your Carrier label, week 11")
expect("Carrier", "1811E08513", "2011-05", .heatPump, "Health Canada recall range start [GOV]")
expect("Bryant", "4511E01446", "2011-11", .heatPump, "Health Canada recall range end [GOV]")
expect("Payne", "3203E08663", "2003-08", .unknown, "week 32 of 2003")
expect("Carrier", "X172563114", nil, .unknown, "ICP shape isn't a Carrier serial")
expect("Day & Night", "X172563114", "2017-06", .unknown, "Day & Night: ICP shape")
expect("Day & Night", "1107E27968", "2007-03", .unknown, "Day & Night: Carrier shape")
print("-- Goodman / Amana / Daikin")
expect("Goodman", "1408123456", "2014-08", .unknown, "YYMM")
expect("Amana", "1609123456", "2016-09", .unknown, "CPSC 2017 recall [GOV]")
expect("Goodman", "0107415182", "2001-07", .unknown, "electrical-forensics")
expect("Goodman", "1413123456", nil, .unknown, "month 13 is impossible")
expect("Goodman", "2712123456", nil, .unknown, "Dec 2027 is in the future")
print("-- Trane / American Standard")
expect("Trane", "13461ABCDE", "2013-11", .unknown, "2010+: week 46")
expect("Trane", "11241KADBB", "2011-06", .unknown, "2010+: week 24")
expect("American Standard", "23494053FA", "2023-12", .unknown, "American Standard recall [MFR]")
expect("Trane", "16304ABCDE", "2016-07", .unknown, "CPSC 2016 recall: weeks 30–32 [GOV]")
expect("Trane", "81422S41G", "2008-04", .unknown, "2002–09: week 14 of 2008, not 1981")
expect("Trane", "7165RHA1G", "2007-04", .unknown, "2002–09: plate stamped April 2007")
expect("Trane", "6132FD1G", "2006-03", .unknown, "2002–09: March 2006")
expect("Trane", "F23456789", nil, .unknown, "pre-2002 year letters are disputed: no guess")
print("-- Rheem / Ruud / Richmond")
expect("Ruud", "Q031612345", "2016-01", .waterHeater, "Ruud age calculator: 01/15/2016 [MFR]")
expect("Ruud", "Q121612345", "2016-03", .waterHeater, "Ruud age calculator: 03/21/2016 [MFR]")
expect("Ruud", "Q451612345", "2016-11", .waterHeater, "Ruud age calculator: 11/04/2016 [MFR]")
expect("Rheem", "A011412345", "2014-01", .waterHeater, "Rheem recall: week 01 of 2014 [MFR]")
expect("Rheem", "M141209135", "2012-04", .waterHeater, "Rheem TSB 1207: week 14 of 2012 [MFR]")
expect("Rheem", "RHLNQ231299996", "2012-06", .waterHeater, "TSB 1207 photo: week 23, printed 30 May 2012 (±1 week)")
expect("Rheem", "RH0806B17262", "2006-08", .waterHeater, "old MMYY + letter: label says 08/2006")
expect("Rheem", "RN1292A29282", "1992-12", .waterHeater, "old MMYY: December 1992")
expect("Rheem", "0794F12345", "1994-07", .waterHeater, "old MMYY: July 1994")
expect("Rheem", "RHLN0106534307", "2006-01", .waterHeater, "old MMYY + 6 digits: January 2006")
expect("Rheem", "W421724596", "2017-10", .airConditioner, "HVAC: week 42 of 2017")
expect("Ruud", "W291013412", "2010-07", .airConditioner, "HVAC: week 29 of 2010")
expect("Rheem", "W121905227", "2019-03", .airConditioner, "HVAC: week 12 of 2019, not December")
expect("Rheem", "7351M280616735", "2006-07", .furnace, "HVAC mid-serial: CPSC 2009 recall [GOV]")
expect("Rheem", "OR177M280700097", "2007-07", .furnace, "HVAC mid-serial: week 28 of 2007")
expect("Rheem", "Q091112345", "2011", .unknown, "type unknown, 2011: month vs week can't be settled")
expect("Rheem", "Q0316123456", nil, .waterHeater, "old test serial was the wrong length")
print("-- A. O. Smith family")
expect("A. O. Smith", "1452A012345", "2014-12", .waterHeater, "week 52 of 2014")
expect("A. O. Smith", "1210A002243", "2012-03", .waterHeater, "week 10 of 2012")
expect("State", "1836111786352", "2018-09", .waterHeater, "13 digits, no letter: week 36 of 2018")
expect("A. O. Smith", "203707002601001", "2020-09", .waterHeater, "Palo Alto: early September 2020")
expect("American Water Heater", "9746123456", "1997-11", .waterHeater, "American: week 46 of 1997")
expect("A. O. Smith", "C05123456", "2005-03", .waterHeater, "CPSC 2005 recall: C05 = March 2005 [GOV]")
expect("Reliance", "MA04123456", "2004-01", .waterHeater, "CPSC 2005 recall: MA04 = January 2004 [GOV]")
expect("State", "J04123456", "2004-09", .waterHeater, "CPSC 2005 recall: J04 = September 2004 [GOV]")
expect("A. O. Smith", "2C062938405", "2006-03", .waterHeater, "plant digit + C06 = March 2006")
expect("A. O. Smith", "AJ89123", "1989", .waterHeater, "1989: month letters of that era disputed (InterNACHI says Oct, CPSC table says Sep)")
print("-- Bradford White")
expect("Bradford White", "KM1234567", "2013-12", .waterHeater, "K = 2013, M = December [MFR]")
expect("Bradford White", "HK16433183", "2011-10", .waterHeater, "Palo Alto: October 2011")
expect("Bradford White", "DH9477405", "2007-08", .waterHeater, "August 2007")
expect("Bradford White", "AF1234567", "2024-06", .waterHeater, "A restarted in 2024 [MFR]")
expect("Bradford White", "IA1234567", nil, .waterHeater, "I is never a year letter")
print("-- Tesla")
// Format from Tesla's serial number spec (service manuals); dates checked against install and commission
// dates in Tesla API data posted on GitHub [community].
expect("Tesla", "TG126172000YTT", "2026-06", .battery, "your Powerwall 3 label: day 172 of 2026")
expect("Tesla", "STG126172000YTT", "2026-06", .battery, "as the barcode carries it, with an S in front")
expect("Tesla", "TG124207002AS8", "2024-07", .battery, "commissioned 2024-09-05 [community]")
expect("Tesla", "TG124365001PWH", "2024-12", .battery, "day 365, commissioned 2025-02-21 [community]")
expect("Tesla", "TG120310000ABC", "2020-11", .battery, "Tesla told the owner November 2020 [forum]")
expect("Tesla", "CN321257G3J8UU", "2021-09", .transferSwitch, "Gateway 2 from a supplier site, installed 2021-12-12 [community]")
expect("Tesla", "GF2252840000V9", "2025-10", .transferSwitch, "Gateway 3 [community]")
expect("Tesla", "T17F0004753", "2017-06", .battery, "early Powerwall 2: T, year, month letter F = June [community]")
expect("Tesla", "TG127010000ABC", nil, .battery, "2027 is in the future")
expect("Tesla", "TG125400000ABC", nil, .battery, "there's no day 400")
expect("Tesla", "1707000-21-M", nil, .battery, "a part number has no date")
print("-- No guessing")
expect(nil, "1913H18804", nil, .unknown, "no brand")
expect("Mitsubishi", "1913H18804", nil, .unknown, "brand without a known format")

print("\n\(failures == 0 ? "All serial checks passed" : "\(failures) serial check(s) FAILED")")


print("\n-- Model numbers")
runModelTests()

print("\n-- Model numbers from manufacturer documents")
runSourcedModelTests()

print("\n-- Equipment database")
runDatabaseTests()

print("\n-- Reading label text")
runReadingTests()

print("\n-- Rules agree with the equipment database")
runAgreementTests()

print("\n-- What the app shows")
runDisplayTests()

print("\n-- Photo quality")
runPhotoQualityTests()
exit(failures + modelFailures + databaseFailures + readingFailures + agreementFailures + displayFailures + qualityFailures == 0 ? 0 : 1)
