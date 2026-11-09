import CoreGraphics
import CoreImage
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Nameplates drawn from listed models (brand, MODEL and SERIAL in one of five layouts, among lines like
/// voltage and refrigerant), damaged four ways, read with Vision OCR and the rules alone. The layouts are
/// ours, so this measures OCR and the rules under damage, not how well they handle real labels' layouts.
func measureSynthetic(labels count: Int) async throws {
    heading("Synthetic: \(count) drawn nameplates × 4 kinds of damage, rules only")
    let sample = syntheticSample(count)
    let levels = ["clean", "slight blur, tilt", "blur, noise, low contrast", "glare"]
    var results: [String: [Int: [String: Int]]] = [:]  // field → damage → right, missing or wrong → count
    var byLayout: [Int: (right: Int, total: Int)] = [:]
    var wrong: [String] = []
    let start = ContinuousClock.now
    for (n, listing) in sample.enumerated() {
        let model = printed(listing, fill: "ABCDEFGHJKLMNPRSTUVWXYZ0123456789".randomElement(using: &random)!)
        let layout = n % layouts.count
        let serial = syntheticSerial()
        let font = fonts.randomElement(using: &random)!
        let clean = draw(rows(brand: listing.brands[0], model: model, serial: serial, layout: layout, kind: listing.kind!), font: font)
        for level in levels.indices {
            let lines = try await TextReader.read(png(damage(clean, level: level)))
            let label = LabelRules.check(.empty, lines: lines)
            let brand = label.brand.value
            let scores = [
                ("model", label.model.value == nil ? "missing" : sameCode(label.model.value, model) ? "right" : "wrong"),
                ("serial", label.serial.value == nil ? "missing" : sameCode(label.serial.value, serial) ? "right" : "wrong"),
                // The listing's maker counts: an ICP model sold as Heil may be named ICP.
                ("brand", brand == nil ? "missing"
                    : (listing.brands + [listing.maker]).contains { brandKey($0) == brandKey(brand!) }
                    || brandKey(listing.brands[0]).hasPrefix(brandKey(brand!)) ? "right" : "wrong"),
                ("type", label.kind == .unknown ? "missing" : label.kind == listing.kind ? "right" : "wrong"),
            ]
            for (field, score) in scores { results[field, default: [:]][level, default: [:]][score, default: 0] += 1 }
            if level <= 1 {
                byLayout[layout, default: (0, 0)].total += 1
                if scores[0].1 == "right" { byLayout[layout]!.right += 1 }
            }
            if scores.contains(where: { $0.1 == "wrong" }) {
                wrong.append("[\(levels[level])] \(listing.kind!.displayName) \(listing.brands[0]) \(model) / \(serial) → "
                              + "\(brand ?? "–") \(label.kind.displayName) \(label.model.value ?? "–") / \(label.serial.value ?? "–")")
            }
        }
    }
    print("\(sample.count * levels.count) images in \(ContinuousClock.now - start)\n")
    for field in ["model", "serial", "brand", "type"] {
        print(field.uppercased())
        for level in levels.indices {
            let counts = results[field]![level]!
            let total = counts.values.reduce(0, +)
            print("  \(levels[level].padded(27)) right \(percent(counts["right"] ?? 0, total).rightAligned(6))   "
                  + "missing \(percent(counts["missing"] ?? 0, total).rightAligned(6))   WRONG \(percent(counts["wrong"] ?? 0, total).rightAligned(6))")
        }
    }
    print("\nModel right by layout, clean and slight damage:")
    for (layout, name) in layouts.enumerated() {
        let count = byLayout[layout] ?? (0, 0)
        print("  \(name.padded(26)) \(percent(count.right, count.total))")
    }
    print("\nSome wrong answers:")
    for example in wrong.prefix(10) { print("  \(example)") }
}

private let layouts = ["MODEL NO. x / SERIAL NO. y", "M/N: x  S/N: y", "keyword above value", "two-column table", "MOD. x / SER. y"]
private let fonts = ["Helvetica", "Helvetica-Bold", "ArialMT", "Courier", "DINCondensed-Bold", "AvenirNextCondensed-Medium",
                     "Futura-Medium", "Menlo-Regular"]

/// Listed models with a brand, weighted toward what's installed most.
private func syntheticSample(_ count: Int) -> [EquipmentDatabase.Listing] {
    let weights: [(EquipmentKind, Int)] = [(.heatPump, 3), (.airConditioner, 2), (.furnace, 2), (.waterHeater, 2), (.packagedUnit, 1),
                                           (.boiler, 1), (.solarInverter, 1), (.battery, 1), (.solarPanel, 1)]
    let pool = EquipmentDatabase.allListings().filter { listing in
        guard let kind = listing.kind, weights.contains(where: { $0.0 == kind }), !listing.brands.isEmpty,
              !listing.listedAs.contains("("), !listing.listedAs.contains("[") else { return false }
        return ListedModel.characters(printed(listing)).count >= 6 && !printed(listing).contains("  ")
    }
    let byKind = Dictionary(grouping: pool, by: { $0.kind! })
    let kinds = weights.flatMap { Array(repeating: $0.0, count: $0.1) }
    return (0..<count).compactMap { _ in byKind[kinds.randomElement(using: &random)!]?.randomElement(using: &random) }
}

private func syntheticSerial() -> String {
    func digits(_ n: Int) -> String { String((0..<n).map { _ in "0123456789".randomElement(using: &random)! }) }
    func letters(_ n: Int) -> String { String((0..<n).map { _ in "ABCDEFGHJKLMNPRSTUVWXYZ".randomElement(using: &random)! }) }
    return switch Int.random(in: 0..<5, using: &random) {
    case 0: digits(4) + letters(1) + digits(5)
    case 1: letters(1) + digits(9)
    case 2: digits(10)
    case 3: letters(2) + digits(8)
    default: digits(4) + letters(1) + digits(6)
    }
}

/// The label's lines as (text, column, size): the brand, other lines above and below, and model and serial
/// in the given layout.
private func rows(brand: String, model: String, serial: String, layout: Int, kind: EquipmentKind) -> [(String, Int, Double)] {
    let other = [.solarPanel, .solarInverter, .battery].contains(kind)
        ? ["RATED POWER 400 W", "Voc 49.5 V  Isc 10.2 A", "MAX SYSTEM VOLTAGE 1000 V", "UL 1741 / IEEE 1547", "NOMINAL AC VOLTAGE 240 V",
           "OPERATING TEMP -40 TO 60 C", "MADE IN CHINA"]
        : [.furnace, .waterHeater, .boiler].contains(kind)
        ? ["INPUT 40,000 BTU/H", "NATURAL GAS", "MANIFOLD PRESSURE 3.5 IN W.C.", "MAX WORKING PRESSURE 150 PSI", "ANSI Z21.10.1 CSA 4.1",
           "120/240 VOLTS 60 HZ", "MFD 06/2020"]
        : ["VOLTS 208/230  PH 1  HZ 60", "REFRIGERANT R-410A  FACTORY CHARGE 6 LBS 2 OZ", "MIN. CIRCUIT AMPACITY 18.6",
           "MAX. FUSE OR CKT. BKR. 30 A", "DESIGN PRESSURE HIGH 600 PSIG  LOW 250 PSIG", "MFD 03/2019", "MADE IN USA",
           "UL LISTED E123456", "COMPRESSOR RLA 13.5  LRA 77", "FAN MOTOR FLA 1.2  HP 1/6"]
    let codes: [(String, Int, Double)] = switch layout {
    case 0: [("MODEL NO. \(model)", 0, 1.0), ("SERIAL NO. \(serial)", 0, 1.0)]
    case 1: [("M/N: \(model)    S/N: \(serial)", 0, 1.0)]
    case 2: [("MODEL NUMBER", 0, 0.8), (model, 0, 1.1), ("SERIAL NUMBER", 0, 0.8), (serial, 0, 1.1)]
    case 3: [("MODEL", 0, 1.0), (model, 1, 1.0), ("SERIAL", 0, 1.0), (serial, 1, 1.0)]
    default: [("MOD. \(model)", 0, 1.0), ("SER. \(serial)", 0, 1.0)]
    }
    let picked = other.shuffled(using: &random).prefix(Int.random(in: 3...6, using: &random)).map { ($0, 0, 0.8) }
    let split = Int.random(in: 0...picked.count, using: &random)
    return [(brand.uppercased(), 0, 2.0)] + picked.prefix(split) + codes + picked.dropFirst(split)
}

private func draw(_ rows: [(String, Int, Double)], font: String) -> CGImage {
    let width = 1600, height = 1100
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let shade = CGFloat.random(in: 0.82...0.97, using: &random)
    context.setFillColor(CGColor(red: shade, green: shade, blue: shade * 0.98, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let base = CGFloat.random(in: 34...44, using: &random)
    var y = CGFloat(height) - 90
    var index = 0
    while index < rows.count {
        let (text, _, scale) = rows[index]
        // In the table layout a value in column 1 sits on the same row as its keyword, in a box.
        let value = index + 1 < rows.count && rows[index + 1].1 == 1 ? rows[index + 1].0 : nil
        for (string, x) in [(text, 80.0)] + (value.map { [($0, 640.0)] } ?? []) {
            let attributes: [NSAttributedString.Key: Any] = [
                .init(kCTFontAttributeName as String): CTFontCreateWithName(font as CFString, base * scale, nil),
                .init(kCTForegroundColorAttributeName as String): CGColor(gray: 0.08, alpha: 1),
            ]
            context.textPosition = CGPoint(x: x, y: y)
            CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes)), context)
        }
        if value != nil {
            context.setStrokeColor(CGColor(gray: 0.2, alpha: 1))
            context.stroke(CGRect(x: 60, y: y - 14, width: 1300, height: base * scale + 24))
        }
        y -= base * scale * 1.75
        index += value == nil ? 1 : 2
    }
    return context.makeImage()!
}

private let imageContext = CIContext()

/// 0 clean, 1 slight blur and tilt, 2 blur with noise and low contrast, 3 a glare spot.
private func damage(_ image: CGImage, level: Int) -> CGImage {
    guard level > 0 else { return image }
    var picture = CIImage(cgImage: image)
    let extent = picture.extent
    let degrees = Double.random(in: -1...1, using: &random) * [0, 2, 5, 3][level]
    picture = picture.transformed(by: CGAffineTransform(rotationAngle: degrees * .pi / 180)).clampedToExtent().cropped(to: extent)
    picture = picture.applyingGaussianBlur(sigma: [0, 1.0, 2.2, 1.5][level]).cropped(to: extent)
    if level >= 2 {
        picture = picture.applyingFilter("CIColorControls", parameters: ["inputContrast": level == 2 ? 0.55 : 0.8, "inputBrightness": 0.08])
        let noise = CIFilter(name: "CIRandomGenerator")!.outputImage!.cropped(to: extent).applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0.12, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0.12, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0.12, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ])
        picture = noise.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: picture]).cropped(to: extent)
    }
    if level == 3 {
        let center = CIVector(x: Double.random(in: 300...1300, using: &random), y: Double.random(in: 200...900, using: &random))
        let glare = CIFilter(name: "CIRadialGradient", parameters: [
            "inputCenter": center, "inputRadius0": 40, "inputRadius1": 260,
            "inputColor0": CIColor(red: 1, green: 1, blue: 1, alpha: 0.95), "inputColor1": CIColor(red: 1, green: 1, blue: 1, alpha: 0),
        ])!.outputImage!.cropped(to: extent)
        picture = glare.applyingFilter("CISourceOverCompositing", parameters: [kCIInputBackgroundImageKey: picture]).cropped(to: extent)
    }
    return imageContext.createCGImage(picture, from: extent)!
}

private func png(_ image: CGImage) -> Data {
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
    return data as Data
}
