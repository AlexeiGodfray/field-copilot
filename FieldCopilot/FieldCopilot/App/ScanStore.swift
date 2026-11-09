import Foundation
import Observation
import SwiftUI

/// Your scans, newest first, saved on the phone. Each photo is a file; scans.json keeps what was read
/// from it (text lines, barcodes, Apple Intelligence's answer) and the voice notes. The rules check each
/// label again when the app opens: it's instant, never asks Apple Intelligence again, and picks up rule fixes.
@Observable
final class ScanStore {
    var scans: [Scan] = []
    private let folder: URL

    static let defaultFolder = URL.applicationSupportDirectory.appending(path: "Scans")

    init(folder: URL = defaultFolder) {
        self.folder = folder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        load()
    }

    func scan(_ id: Scan.ID) -> Scan? {
        scans.first { $0.id == id }
    }

    /// Saves a new photo as a scan, newest first. Nil when the data isn't an image or can't be saved.
    func add(photo data: Data, source: Scan.Source, location: CaptureLocation? = nil) -> Scan? {
        guard UIImage(data: data) != nil else { return nil }
        let id = UUID()
        let url = folder.appending(path: "\(id).photo")
        guard (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        let scan = Scan(id: id, photoURL: url, source: source, location: location)
        scans.insert(scan, at: 0)
        return scan
    }

    func delete(_ scan: Scan) {
        guard let index = scans.firstIndex(where: { $0.id == scan.id }) else { return }
        delete(at: [index])
    }

    func delete(at offsets: IndexSet) {
        for index in offsets { try? FileManager.default.removeItem(at: scans[index].photoURL) }
        scans.remove(atOffsets: offsets)
        save()
    }

    /// Writes the finished scans. One still being read is saved when it finishes.
    func save() {
        let records = scans.filter { $0.step == .done }.map { ScanRecord($0) }
        try? JSONEncoder().encode(records).write(to: folder.appending(path: "scans.json"), options: .atomic)
    }

    private func load() {
        if let data = try? Data(contentsOf: folder.appending(path: "scans.json")),
           let records = try? JSONDecoder().decode([ScanRecord].self, from: data) {
            scans = records.map { Scan(record: $0, folder: folder) }
        }
        // A photo with no saved reading was still being read when the app closed: remove it.
        let kept = Set(scans.map(\.photoURL.lastPathComponent) + ["scans.json"])
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for file in files where !kept.contains(file) {
            try? FileManager.default.removeItem(at: folder.appending(path: file))
        }
    }
}

/// What's saved for a scan, apart from its photo.
struct ScanRecord: Codable {
    struct Line: Codable {
        let text: String
        let box: CGRect
    }

    struct Answer: Codable {
        let brand: String?
        let kind: String
        let model: String?
        let serial: String?
        let manufactureDate: String?
    }

    let id: UUID
    let date: Date
    let photo: String
    let lines: [Line]
    let barcodes: [Line]
    let answer: Answer?
    let askedAppleIntelligence: Bool
    let message: String?
    let edits: LabelEdits?
    /// Nil in scans saved before the camera, which all came from the library.
    let source: Scan.Source?
    let location: CaptureLocation?
    let photoProblems: [PhotoQuality.Problem]?
    let voiceNotes: [VoiceNote]?

    init(_ scan: Scan) {
        id = scan.id
        date = scan.date
        photo = scan.photoURL.lastPathComponent
        lines = scan.lines.map { Line(text: $0.text, box: $0.box) }
        barcodes = scan.barcodes.map { Line(text: $0.payload, box: $0.box) }
        answer = scan.answer.map {
            Answer(brand: $0.brand, kind: $0.kind.rawValue, model: $0.model, serial: $0.serial, manufactureDate: $0.manufactureDate)
        }
        askedAppleIntelligence = scan.askedAppleIntelligence
        message = scan.message
        edits = scan.edits == LabelEdits() ? nil : scan.edits
        source = scan.source
        location = scan.location
        photoProblems = scan.photoProblems.isEmpty ? nil : scan.photoProblems
        voiceNotes = scan.voiceNotes.isEmpty ? nil : scan.voiceNotes
    }
}

extension Scan {
    /// A saved scan, its label checked again by the rules.
    convenience init(record: ScanRecord, folder: URL) {
        self.init(id: record.id, date: record.date, photoURL: folder.appending(path: record.photo),
                  source: record.source ?? .library, location: record.location)
        photoProblems = record.photoProblems ?? []
        lines = record.lines.map { TextLine(text: $0.text, box: $0.box) }
        barcodes = record.barcodes.map { Barcode(payload: $0.text, box: $0.box) }
        answer = record.answer.map {
            EquipmentLabel(brand: $0.brand, kind: EquipmentKind(rawValue: $0.kind) ?? .unknown, model: $0.model,
                           serial: $0.serial, manufactureDate: $0.manufactureDate)
        }
        askedAppleIntelligence = record.askedAppleIntelligence
        message = record.message
        edits = record.edits ?? LabelEdits()
        voiceNotes = record.voiceNotes ?? []
        step = .done
        recheck()
    }
}
