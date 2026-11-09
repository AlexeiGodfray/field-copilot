import Foundation
import Vision

/// One line of text found in a photo.
struct TextLine: Identifiable {
    let id = UUID()
    let text: String
    /// Where the line sits in the photo, as fractions of its width and height, origin top-left.
    let box: CGRect
}

/// Reads the text in a photo with Apple's on-device text recognition.
enum TextReader {
    static func read(_ imageData: Data) async throws -> [TextLine] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false  // model and serial numbers aren't words; don't "fix" them
        request.recognitionLanguages = [Locale.Language(identifier: "en-US")]  // no look-alike Cyrillic letters
        request.automaticallyDetectsLanguage = false
        let observations = try await request.perform(on: imageData)
        return observations.compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            // A 1×1 "image size" keeps the box in fractions while flipping Vision's
            // bottom-left origin to SwiftUI's top-left.
            let box = observation.boundingBox.toImageCoordinates(CGSize(width: 1, height: 1), origin: .upperLeft)
            return TextLine(text: plain(text), box: box)
        }
    }

    /// Cyrillic and Greek letters that look like Latin ones, as Vision sometimes returns them: "МАХ" is MAX.
    private static let lookalikes: [Character: Character] = [
        "А": "A", "В": "B", "Е": "E", "К": "K", "М": "M", "Н": "H", "О": "O", "Р": "P", "С": "C", "Т": "T", "Х": "X", "У": "Y",
        "а": "a", "е": "e", "о": "o", "р": "p", "с": "c", "х": "x", "у": "y", "Ι": "I", "Α": "A", "Β": "B", "Ε": "E", "Κ": "K",
        "Μ": "M", "Ν": "N", "Ο": "O", "Ρ": "P", "Τ": "T", "Χ": "X", "Ζ": "Z",
    ]

    /// Label text in plain ASCII. Even set to English, Vision returns look-alike Cyrillic letters and stray
    /// accented ones at the ends of lines ("3418949011Ś"), and the codes on labels are plain ASCII, so
    /// look-alikes become Latin letters and anything else outside ASCII is dropped.
    static func plain(_ text: String) -> String {
        String(text.compactMap { character in
            let latin = lookalikes[character] ?? character
            return latin.isASCII ? latin : nil
        })
    }
}
