// Tests for the photo quality check on drawn labels: sharp, blurred, glare-spotted and dark.

import CoreGraphics
import Foundation

var qualityFailures = 0

func expectProblems(_ image: CGImage, _ expected: [PhotoQuality.Problem], _ why: String) {
    let quality = PhotoQuality.measure(image)
    if quality?.problems != expected {
        qualityFailures += 1
        print("FAIL  \(why): \(quality?.problems.map(\.rawValue) ?? ["nil"]) (want \(expected.map(\.rawValue)))")
    }
}

/// A gray background with a white label of black "text": rows of small bars.
func drawnLabel(width: Int = 1440, height: Int = 1080, blur: Int = 1, hotspot: Double = 0, light: Double = 1) -> CGImage {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    context.setFillColor(gray: 0.45 * light, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let label = CGRect(x: width / 6, y: height / 8, width: width * 2 / 3, height: height * 3 / 4)
    context.setFillColor(gray: 0.9 * light, alpha: 1)
    context.fill(label)
    context.setFillColor(gray: 0.05, alpha: 1)
    var y = label.maxY - 40
    var seed = 7
    while y > label.minY + 30 {
        var x = label.minX + 30
        while x < label.maxX - 40 {
            seed = (seed * 1103515245 + 12345) & 0x7fffffff
            let w = CGFloat(4 + seed % 14)
            context.fill(CGRect(x: x, y: y, width: w, height: 18))
            x += w + CGFloat(3 + seed % 5)
        }
        y -= 34
    }
    if hotspot > 0 {
        let radius = (hotspot * Double(width * height) / .pi).squareRoot()
        context.setFillColor(gray: 1, alpha: 1)
        context.fillEllipse(in: CGRect(x: Double(width) / 2 - radius, y: Double(height) / 2 - radius, width: radius * 2, height: radius * 2))
    }
    var image = context.makeImage()!
    if blur > 1 {  // shrink and enlarge again, losing detail
        let small = CGContext(data: nil, width: width / blur, height: height / blur, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        small.interpolationQuality = .high
        small.draw(image, in: CGRect(x: 0, y: 0, width: width / blur, height: height / blur))
        let big = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        big.interpolationQuality = .high
        big.draw(small.makeImage()!, in: CGRect(x: 0, y: 0, width: width, height: height))
        image = big.makeImage()!
    }
    return image
}

func runPhotoQualityTests() {
    expectProblems(drawnLabel(), [], "sharp label")
    expectProblems(drawnLabel(width: 4032, height: 3024), [], "sharp label at full camera resolution")
    expectProblems(drawnLabel(blur: 16), [.blurry], "blurred label")
    expectProblems(drawnLabel(hotspot: 0.03), [.glare], "glare hotspot over 3% of the frame")
    expectProblems(drawnLabel(light: 0.3), [.dark], "dark photo")

    // A live camera frame, sampled from a 1920 × 1440 frame as the camera does, scores like the still photo.
    let still = PhotoQuality.measure(drawnLabel(width: 1920, height: 1440))!
    let frame = drawnLabel(width: 1920, height: 1440)
    var bytes = [UInt8](repeating: 0, count: 1920 * 1440)
    bytes.withUnsafeMutableBytes { buffer in
        let context = CGContext(data: buffer.baseAddress, width: 1920, height: 1440, bitsPerComponent: 8, bytesPerRow: 1920,
                                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        context.draw(frame, in: CGRect(x: 0, y: 0, width: 1920, height: 1440))
    }
    let live = bytes.withUnsafeBufferPointer { PhotoQuality.measure(luma: $0.baseAddress!, width: 1920, height: 1440, rowBytes: 1920) }
    if live.problems != still.problems || abs(live.sharpness - still.sharpness) > still.sharpness * 0.5 {
        qualityFailures += 1
        print("FAIL  live frame scores \(Int(live.sharpness)), still photo \(Int(still.sharpness))")
    }

    print(qualityFailures == 0 ? "All photo quality checks passed" : "\(qualityFailures) photo quality check(s) FAILED")
}
