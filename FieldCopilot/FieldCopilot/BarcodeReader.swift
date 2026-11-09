import Foundation
import Vision

/// One barcode found in a photo.
struct Barcode: Identifiable {
    let id = UUID()
    let payload: String
    /// Where the barcode sits in the photo, as fractions of its width and height, origin top-left.
    let box: CGRect
}

/// Reads barcodes and QR codes with Apple's on-device barcode detection. Unlike OCR, a barcode
/// either decodes exactly or not at all, so it's the most reliable way to read a serial.
enum BarcodeReader {
    static func read(_ imageData: Data) async throws -> [Barcode] {
        let observations = try await DetectBarcodesRequest().perform(on: imageData)
        return observations.compactMap { observation in
            guard let payload = observation.payloadString?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !payload.isEmpty
            else { return nil }
            let box = observation.boundingBox.toImageCoordinates(CGSize(width: 1, height: 1), origin: .upperLeft)
            return Barcode(payload: payload, box: box)
        }
    }
}
