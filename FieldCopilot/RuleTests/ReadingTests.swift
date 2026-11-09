// Tests for reading model and serial numbers off label text, including model numbers printed with
// spaces. Each case is the text OCR returns, one string per line.

import Foundation

var readingFailures = 0

func expectRead(_ texts: [String], model: String?, serial: String? = nil, _ why: String) {
    let label = LabelRules.check(.empty, lines: lines(texts))
    var problems: [String] = []
    if label.model.value != model { problems.append("model \(label.model.value ?? "nil") (want \(model ?? "nil"))") }
    if let serial, label.serial.value != serial { problems.append("serial \(label.serial.value ?? "nil") (want \(serial))") }
    if !problems.isEmpty {
        readingFailures += 1
        print("FAIL  \(why): \(problems.joined(separator: ", "))")
    }
}

func runReadingTests() {
    EquipmentDatabase.fileURL = URL(filePath: "FieldCopilot/Equipment.sqlite")

    // Model and serial on one line, and the short keywords MOD. and SER.
    expectRead(["MIDEA", "M/N: MOVB-24HDN10-M16G   S/N: 1823626128"], model: "MOVB-24HDN10-M16G", serial: "1823626128",
               "both on one line")
    expectRead(["SERIAL NO. Q121912345   MODEL NO. XE50T10HS45U0"], model: "XE50T10HS45U0", serial: "Q121912345", "serial first")
    expectRead(["MOD. N5A4S36DHDNAA", "SER. 1488G936049"], model: "N5A4S36DHDNAA", serial: "1488G936049", "MOD. and SER.")
    expectRead(["MODEL NO.XE50T10HS45U0", "SERIAL NO.Q121912345"], model: "XE50T10HS45U0", serial: "Q121912345", "keyword stuck to its value")
    check(TextReader.plain("МАХ. FUSE 30 А") == "MAX. FUSE 30 A" && TextReader.plain("3418949011Ś") == "3418949011",
          "OCR text in plain ASCII")
    expectRead(["FOR USE WITH MODEL CNPVP2417ALA COILS", "MODEL 24ACA336A300"], model: "24ACA336A300",
               "a keyword partway along a sentence isn't the model line")
    // A look-alike corrected in the first word of a spaced model keeps the words after it.
    expectRead(["MODEL 5FC 125"], model: "SFC 125", "corrected first word of a spaced model")

    // Spaced model numbers: later words join when a model-number rule or ENERGY STAR listing covers them.
    expectRead(["RHEEM", "MODEL NO. PROPH50 T2 RH375-15", "SERIAL NO. Q121912345"], model: "PROPH50 T2 RH375-15",
               serial: "Q121912345", "Rheem heat pump water heater")
    expectRead(["MODEL GS6 40 YBRT", "SERIAL 1234567890"], model: "GS6 40 YBRT", "State gas water heater")
    expectRead(["MODEL NO.", "GSX 40 YBRT 200"], model: "GSX 40 YBRT 200", "State on the next line, short first word")
    expectRead(["MODEL NO. PRO H40 T2 RU310BM"], model: "PRO H40 T2 RU310BM", "four words, short first word")
    expectRead(["MODEL: GCR-50 301"], model: "GCR-50 301", "A. O. Smith with its series number")
    expectRead(["MODEL HP1050H45DV 100"], model: "HP1050H45DV 100", "only ENERGY STAR knows the last word")

    // Where a model number ends.
    expectRead(["MODEL PROE50 T2 RH95 240V"], model: "PROE50 T2 RH95", "stops at a measurement")
    expectRead(["MODEL NO. PROE50 T2 RH95 Q121912345"], model: "PROE50 T2 RH95", "stops at a long code")
    expectRead(["MODEL 13HPX-048-230-18 SERIAL 1913H18804"], model: "13HPX-048-230-18", "stops at the next keyword")
    expectRead(["MODEL ABC1234 REV B"], model: "ABC1234", "an unknown format keeps the first word")

    // Unchanged behavior.
    expectRead(["MODEL NO. XE50T10HS45U0"], model: "XE50T10HS45U0", "no spaces")
    expectRead(["MODEL 13HPX -048 - 230-18"], model: "13HPX-048-230-18", "OCR spaces around dashes")
    expectRead(["SERIAL 1", "107E27968"], model: nil, serial: "1107E27968", "big first character on its own line")
    expectRead(["MODEL GS6", "SERIAL NO. 1234567890"], model: nil, serial: "1234567890",
               "a short word doesn't swallow the next field")

    // Battery and solar labels: a brand before the keyword, "PART NO." when there's no MODEL, and "SN:".
    // Lines as OCR read a real Tesla Powerwall 3 nameplate.
    let tesla = ["TESLA POWERWALL ENERGY", "STORAGE SYSTEM GRID", "TESLA PART NO.", "1707000 -21 - M", "SN: TG126172000YTT",
                 "SUPPORT UTILITY INTERACTIVE", "& STANDALONE INVERTER", "BATTERY ENERGY STORAGE SYSTEM (BESS) &"]
    expectRead(tesla, model: "1707000-21-M", serial: "TG126172000YTT", "Tesla Powerwall 3 nameplate")
    if LabelRules.check(.empty, lines: lines(tesla)).kind != .battery {
        readingFailures += 1
        print("FAIL  a Powerwall with a built-in inverter should read as a battery")
    }
    expectRead(["PART NO. 1185123", "MODEL NO. 24ACA336A300", "SERIAL NO. 1107E27968"], model: "24ACA336A300",
               "a part number above the model isn't the model")
    expectRead(["SNOW LOAD 40 PSF", "SERIAL NO. 1107E27968"], model: nil, serial: "1107E27968", "SN only as its own word")

    // Tesla's 2D barcode joins the part number and serial with a colon; it corrects a misread serial.
    let barcode = Barcode(payload: "P1707000-21-M:STG126172000YTT", box: .zero)
    let misread = LabelRules.check(.empty, lines: lines(["TESLA PART NO.", "1707000-21-M", "SN: TG12617200OYTT"]), barcodes: [barcode])
    if misread.serial.value != "TG126172000YTT" || misread.model.note != "Matches the barcode" {
        readingFailures += 1
        print("FAIL  Tesla barcode: serial \(misread.serial.value ?? "nil"), model note \(misread.model.note ?? "nil")")
    }

    print(readingFailures == 0 ? "All reading checks passed" : "\(readingFailures) reading check(s) FAILED")
}
