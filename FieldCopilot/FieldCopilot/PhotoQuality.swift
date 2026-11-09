import CoreGraphics
import Foundation

/// Whether a photo of a label is good enough to read: sharp, not washed out by glare, not too dark.
/// Measured on a grayscale copy 720 pixels wide, over the middle of the frame where the label should be,
/// so live camera frames and saved photos are judged on the same scale.
nonisolated struct PhotoQuality: Equatable, Sendable {
    enum Problem: String, Codable, Sendable {
        case blurry, glare, dark
    }

    /// How crisp the edges are: the variance of the Laplacian, averaged over the sharpest quarter of
    /// the frame (where the text is), so blank metal around a label doesn't count against it.
    let sharpness: Double
    /// Mean brightness, 0 to 255.
    let brightness: Double
    /// Share of pixels blown out to white.
    let glare: Double

    static let width = 720
    // Calibrated on 5 label photos and blurred, darkened and glare-spotted copies, against whether the rules
    // still read the model and serial. Reading failed from a sharpness of about 100 down, and a glare hotspot
    // covering 1% of the frame already broke or changed serials. Clean photos had at most 0.2% blown out.
    static let minimumSharpness = 150.0
    static let maximumGlare = 0.01
    static let minimumBrightness = 55.0

    /// The problems, worst first.
    var problems: [Problem] {
        var problems: [Problem] = []
        if brightness < Self.minimumBrightness { problems.append(.dark) }
        if glare > Self.maximumGlare { problems.append(.glare) }
        if sharpness < Self.minimumSharpness { problems.append(.blurry) }
        return problems
    }

    /// Measures a whole image, scaled to the measuring width.
    static func measure(_ image: CGImage) -> PhotoQuality? {
        guard image.width > 0, image.height > 0 else { return nil }
        let height = max(1, Int((Double(image.height) * Double(width) / Double(image.width)).rounded()))
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? measure(gray: pixels, width: width, height: height) : nil
    }

    /// Measures a live camera frame's brightness plane, averaged down to the measuring width.
    static func measure(luma: UnsafePointer<UInt8>, width sourceWidth: Int, height sourceHeight: Int, rowBytes: Int) -> PhotoQuality {
        let height = max(1, sourceHeight * width / max(sourceWidth, 1))
        let block = max(1, sourceWidth / width)
        var pixels = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            let sy = y * sourceHeight / height
            for x in 0..<width {
                let sx = x * sourceWidth / width
                var total = 0, count = 0
                for dy in 0..<block where sy + dy < sourceHeight {
                    let row = luma + (sy + dy) * rowBytes
                    for dx in 0..<block where sx + dx < sourceWidth {
                        total += Int(row[sx + dx])
                        count += 1
                    }
                }
                pixels[y * width + x] = UInt8(total / max(count, 1))
            }
        }
        return measure(gray: pixels, width: width, height: height)
    }

    /// Measures a grayscale image, one byte per pixel, rows packed.
    static func measure(gray pixels: [UInt8], width: Int, height: Int) -> PhotoQuality {
        // The middle 80% of the frame.
        let x0 = width / 10, x1 = width - width / 10
        let y0 = height / 10, y1 = height - height / 10
        guard x1 - x0 > 4, y1 - y0 > 4 else { return PhotoQuality(sharpness: 0, brightness: 0, glare: 0) }

        var sum = 0.0, blownOut = 0, count = 0
        for y in y0..<y1 {
            for x in x0..<x1 {
                let value = pixels[y * width + x]
                sum += Double(value)
                if value >= 250 { blownOut += 1 }
                count += 1
            }
        }

        // Laplacian variance per tile, then the mean of the sharpest quarter of tiles.
        let columns = 8, rows = 8
        var tiles: [Double] = []
        for row in 0..<rows {
            for column in 0..<columns {
                let tx0 = max(x0 + (x1 - x0) * column / columns, 1)
                let tx1 = min(x0 + (x1 - x0) * (column + 1) / columns, width - 1)
                let ty0 = max(y0 + (y1 - y0) * row / rows, 1)
                let ty1 = min(y0 + (y1 - y0) * (row + 1) / rows, height - 1)
                var n = 0.0, mean = 0.0, m2 = 0.0
                for y in ty0..<ty1 {
                    for x in tx0..<tx1 {
                        let i = y * width + x
                        let laplacian = 4 * Double(pixels[i]) - Double(pixels[i - 1]) - Double(pixels[i + 1])
                            - Double(pixels[i - width]) - Double(pixels[i + width])
                        n += 1
                        let delta = laplacian - mean
                        mean += delta / n
                        m2 += delta * (laplacian - mean)
                    }
                }
                if n > 1 { tiles.append(m2 / (n - 1)) }
            }
        }
        let sharpest = tiles.sorted(by: >).prefix(max(1, tiles.count / 4))
        let sharpness = sharpest.reduce(0, +) / Double(sharpest.count)

        return PhotoQuality(sharpness: sharpness, brightness: sum / Double(count), glare: Double(blownOut) / Double(count))
    }
}
