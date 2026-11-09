import CoreGraphics
import Foundation
import FoundationModels
import ImageIO

/// Real label photos against the right answers in the folder's truth.csv, one photo per line:
///   file,brand,type,model,serial
///   IMG_0011.PNG,Carrier,airConditioner,24ACA336A300,1107E27968
/// The type is the app's name for it (heatPump, waterHeater, solarPanel…). Photos the app turns away as
/// blurry are counted, not scored. Keep the folder out of git: these are customers' photos.
func measurePhotos(in folder: URL) async throws {
    heading("Photos: \(folder.path)")
    let truthFile = folder.appending(path: "truth.csv")
    guard let text = try? String(contentsOf: truthFile, encoding: .utf8) else { fatalError("No truth.csv in \(folder.path)") }
    let rows = text.split(whereSeparator: \.isNewline).map { $0.split(separator: ",", omittingEmptySubsequences: false).map {
        $0.trimmingCharacters(in: .whitespaces)
    } }.filter { $0.count >= 5 && $0[0] != "file" }
    let ai = SystemLanguageModel.default.availability == .available
    print("Apple Intelligence on this Mac: \(ai ? "available" : "not available, so only the rules are scored")")

    var scores: [String: [String: Int]] = [:]  // reader → right, missing or wrong → fields
    var turnedAway: [String] = []
    for row in rows {
        let (file, brand, model, serial) = (row[0], row[1], row[3], row[4])
        guard let kind = EquipmentKind.allCases.first(where: { $0.rawValue.lowercased() == row[2].lowercased()
                                                              || $0.displayName.lowercased() == row[2].lowercased() }) else {
            print("\(file): no type called \(row[2])")
            continue
        }
        let data = try Data(contentsOf: folder.appending(path: file))
        if let source = CGImageSourceCreateWithData(data as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
           PhotoQuality.measure(image)?.problems.contains(.blurry) == true {
            turnedAway.append(file)
            print("\n\(file): turned away as blurry, as the app does")
            continue
        }
        let lines = try await TextReader.read(data)
        let barcodes = (try? await BarcodeReader.read(data)) ?? []
        let rules = LabelRules.check(.empty, lines: lines, barcodes: barcodes)
        var readers: [(String, EquipmentLabel?, CheckedLabel?)] = [("rules alone", nil, rules)]
        if ai {
            let answer = try await LabelReader.read(lines)
            readers.insert(("Apple Intelligence alone", answer, nil), at: 0)
            readers.append(("the app", nil, rules.hasGaps ? LabelRules.check(answer, lines: lines, barcodes: barcodes) : rules))
        } else {
            readers.append(("the app", nil, rules))
        }
        print("\n\(file) (\(lines.count) lines, \(barcodes.count) barcodes)")
        for (reader, answer, checked) in readers {
            let got = checked.map { ($0.brand.value, $0.kind, $0.model.value, $0.serial.value) }
                ?? (answer!.brand, answer!.kind, answer!.model, answer!.serial)
            let marks = [
                got.0 == nil ? "–" : brandKey(got.0!).hasPrefix(brandKey(brand)) ? "✓" : "✗ \(got.0!)",
                got.1 == .unknown || got.1 == .airConditionerOrHeatPump ? "–" : got.1 == kind ? "✓" : "✗ \(got.1.displayName.lowercased())",
                got.2 == nil ? "–" : sameCode(got.2, model) ? "✓" : "✗ \(got.2!)",
                got.3 == nil ? "–" : sameCode(got.3, serial) ? "✓" : "✗ \(got.3!)",
            ]
            print("  \(reader.padded(26)) brand \(marks[0])   type \(marks[1])   model \(marks[2])   serial \(marks[3])")
            for mark in marks { scores[reader, default: [:]][mark == "✓" ? "right" : mark == "–" ? "missing" : "wrong", default: 0] += 1 }
        }
    }
    print("\nFields (brand, type, model, serial) over \(rows.count - turnedAway.count) photos read; \(turnedAway.count) turned away as blurry:")
    for reader in ["Apple Intelligence alone", "rules alone", "the app"] {
        guard let s = scores[reader] else { continue }
        print("  \(reader.padded(26)) \(s["right"] ?? 0) right, \(s["missing"] ?? 0) missing, \(s["wrong"] ?? 0) wrong")
    }
}
