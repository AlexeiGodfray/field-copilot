import Observation
import UIKit

/// One photo of a label and what was read from it.
@Observable
final class Scan: Identifiable {
    enum Step: Int, Comparable {
        case text, modelNumber, lists, appleIntelligence, done

        static func < (a: Step, b: Step) -> Bool { a.rawValue < b.rawValue }
    }

    /// Where the photo came from. Only a photo taken in the app is stamped with where it was taken.
    enum Source: String, Codable { case camera, library }

    let id: UUID
    let date: Date
    /// The photo, saved as a file in the app's storage.
    let photoURL: URL
    let source: Source
    /// Where it was taken, for a photo taken in the app with location allowed.
    let location: CaptureLocation?
    /// What makes the photo hard to read: blur, glare, darkness.
    var photoProblems: [PhotoQuality.Problem] = []
    @ObservationIgnored lazy var image = UIImage(contentsOfFile: photoURL.path) ?? UIImage()
    @ObservationIgnored lazy var thumbnail = image.preparingThumbnail(of: CGSize(width: 168, height: 168)) ?? image
    var lines: [TextLine] = []
    var barcodes: [Barcode] = []
    var label: CheckedLabel?
    var step = Step.text
    /// Whether the rules left gaps for Apple Intelligence to fill.
    var askedAppleIntelligence = false
    /// Apple Intelligence's answer, kept so a saved scan can be checked again without asking it again.
    var answer: EquipmentLabel?
    /// What went wrong or was skipped, in plain words.
    var message: String?
    /// Corrections a person made. The label is checked again with them.
    var edits = LabelEdits()
    /// What a person said about the unit, oldest first, as text.
    var voiceNotes: [VoiceNote] = []

    init(id: UUID = UUID(), date: Date = .now, photoURL: URL, source: Source, location: CaptureLocation? = nil) {
        self.id = id
        self.date = date
        self.photoURL = photoURL
        self.source = source
        self.location = location
    }

    /// Rules first: they're deterministic, instant, and fill most labels. Apple Intelligence is only
    /// asked about fields the rules left empty, and the rules check its answers.
    func read() async {
        defer { step = .done }
        do {
            let imageData = try Data(contentsOf: photoURL)
            async let textLines = TextReader.read(imageData)
            async let codes = BarcodeReader.read(imageData)
            lines = try await textLines
            barcodes = (try? await codes) ?? []  // no barcodes is normal; don't fail the photo over it
            photoProblems = UIImage(data: imageData)?.cgImage.flatMap { PhotoQuality.measure($0) }?.problems ?? []
        } catch {
            message = "Couldn't read this photo. Try a sharper, closer shot of the label."
            return
        }
        guard !lines.isEmpty else {
            message = "No text found. Try a sharper, closer shot of the label."
            return
        }

        step = .modelNumber
        let ruled = LabelRules.check(.empty, lines: lines, barcodes: barcodes, edits: edits)
        step = .lists
        label = ruled
        guard ruled.hasGaps else { return }

        askedAppleIntelligence = true
        if let reason = LabelReader.unavailableReason {
            message = "\(reason) Showing what the rules read on their own."
            return
        }
        step = .appleIntelligence
        do {
            let answer = try await LabelReader.read(lines)
            self.answer = answer
            label = LabelRules.check(answer, lines: lines, barcodes: barcodes, edits: edits)
        } catch {
            message = "Apple Intelligence couldn't read this label. Showing what the rules read on their own."
        }
    }

    // MARK: Corrections

    enum Field: String, Identifiable, CaseIterable {
        case brand, kind, model, serial, made

        var id: Self { self }

        var name: String {
            switch self {
            case .brand: "Brand"
            case .kind: "Type"
            case .model: "Model"
            case .serial: "Serial"
            case .made: "Made"
            }
        }
    }

    /// Checks the label again with the person's corrections. A scan with no text found gets a label to fill in
    /// once a correction is made.
    func recheck() {
        guard step == .done, label != nil || !lines.isEmpty || edits != LabelEdits() else { return }
        label = LabelRules.check(answer ?? .empty, lines: lines, barcodes: barcodes, edits: edits)
    }

    /// Starts an empty label for a photo with no text found, so a person can enter the details.
    func enterDetails() {
        label = LabelRules.check(.empty, lines: lines, barcodes: barcodes, edits: edits)
    }

    func edit(_ field: Field) -> String? {
        switch field {
        case .brand: edits.brand
        case .kind: edits.kind?.rawValue
        case .model: edits.model
        case .serial: edits.serial
        case .made: edits.manufactureDate
        }
    }

    func setEdit(_ field: Field, _ value: String?) {
        let value = value?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        switch field {
        case .brand: edits.brand = value
        case .kind: edits.kind = value.flatMap(EquipmentKind.init(rawValue:))
        case .model: edits.model = value?.uppercased()
        case .serial: edits.serial = value?.uppercased()
        case .made: edits.manufactureDate = value
        }
        recheck()
    }

    /// What was read for a field, without the person's correction to it.
    func readValue(_ field: Field) -> String? {
        var withoutEdit = edits
        switch field {
        case .brand: withoutEdit.brand = nil
        case .kind: withoutEdit.kind = nil
        case .model: withoutEdit.model = nil
        case .serial: withoutEdit.serial = nil
        case .made: withoutEdit.manufactureDate = nil
        }
        let read = LabelRules.check(answer ?? .empty, lines: lines, barcodes: barcodes, edits: withoutEdit)
        switch field {
        case .brand: return read.brand.value
        case .kind: return read.kind == .unknown ? nil : read.kind.displayName
        case .model: return read.model.value
        case .serial: return read.serial.value
        case .made: return ManufactureAge.describe(read).value?.components(separatedBy: " · ").first
        }
    }

    // MARK: For display

    var title: String {
        guard let label else { return step == .done ? "No label found" : "Reading…" }
        return [label.brand.value, label.kind == .unknown ? nil : label.kind.displayName]
            .compactMap { $0 }.joined(separator: " · ").nonEmpty ?? "Unknown equipment"
    }

    /// "Mar 2007" and "19 years old", when the age is known.
    var made: (date: String, age: String)? {
        guard let label, let value = ManufactureAge.describe(label).value else { return nil }
        let parts = value.components(separatedBy: " · ")
        return parts.count == 2 ? (parts[0], parts[1]) : nil
    }

    /// When it was made, as the Made row shows it.
    var madeDate: (year: Int, month: Int?)? {
        guard let label else { return nil }
        if let value = label.manufactureDate.value, let match = value.wholeMatch(of: #/(\d{4})(?:-(\d{2}))?/#),
           let year = Int(match.1) {
            return (year, match.2.flatMap { Int($0) })
        }
        return SerialDecoder.decode(brand: label.brand.value, serial: label.serial.value, kind: label.kind).map { ($0.year, $0.month) }
    }

    /// Lines the brand, model or serial was read from, to highlight on the photo.
    var usedLines: Set<TextLine.ID> {
        guard let label else { return [] }
        let codes = [label.model.value, label.serial.value].compactMap { $0 }.map { LabelRules.compact($0) }
        let brand = label.brand.value?.uppercased().filter(\.isLetter)
        return Set(lines.filter { line in
            let text = LabelRules.compact(line.text)
            let hasCode = codes.contains { text.contains($0) || (text.count >= 4 && $0.contains(text)) }
            let hasBrand = brand.map { $0.count >= 3 && line.text.uppercased().filter(\.isLetter).contains($0) } ?? false
            return hasCode || hasBrand
        }.map(\.id))
    }

    /// "Taken in the app on Oct 22, 2026 at 3:45 PM", or when a library photo was added.
    var captureSummary: String {
        let when = date.formatted(date: .abbreviated, time: .shortened)
        return source == .camera ? "Taken in the app on \(when)" : "Chosen from the photo library on \(when)"
    }

    /// What's wrong with the photo, in plain words, for a warning.
    var photoWarning: String? {
        guard !photoProblems.isEmpty else { return nil }
        let phrases = photoProblems.map { problem in
            switch problem {
            case .blurry: "looks blurry"
            case .glare: "has glare"
            case .dark: "is dark"
            }
        }
        return "This photo \(phrases.formatted(.list(type: .and))), so some text may be misread. "
            + "Check the values, or take another photo."
    }

    /// A plain-text summary to share.
    var summary: String {
        guard let label else { return title }
        var rows = [title]
        if let model = label.model.value { rows.append("Model: \(model)") }
        if let serial = label.serial.value { rows.append("Serial: \(serial)") }
        if let made { rows.append("Made: \(made.date) (\(made.age))") }
        if let specs = label.size { rows.append("Specs: \(specs)") }
        if let listed = EquipmentDatabase.describe(label), let value = listed.field.value { rows.append("\(listed.title): \(value)") }
        rows += voiceNotes.map { "Note: \($0.text)" }
        rows.append(captureSummary)
        if let location { rows.append("Location: \(location.latitude.formatted(.number.precision(.fractionLength(5)))), "
                                      + "\(location.longitude.formatted(.number.precision(.fractionLength(5))))") }
        return rows.joined(separator: "\n")
    }
}

/// Something a person said about the unit, kept as text. The recording itself isn't saved.
struct VoiceNote: Codable, Identifiable, Equatable {
    var id = UUID()
    var date = Date.now
    var text: String
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
